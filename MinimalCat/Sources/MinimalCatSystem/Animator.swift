import AppKit
import QuartzCore

/// Moves windows with a short ease-out. Each app gets its own queue, so one slow app can't hold up the others,
/// and a queue only ever writes the newest frame. Use it from the main thread.
final class Animator {
    static let duration: CFTimeInterval = 0.12
    static let instantAbove = 6

    struct Target {
        let element: AXUIElement
        let id: CGWindowID
        let pid: pid_t
        let start: CGRect
        let end: CGRect
    }

    private struct Flight { let target: Target; let start: CFTimeInterval }
    /// Where each moving window goes, until its app confirms the last write. The window server lags behind.
    private(set) var heading: [CGWindowID: CGRect] = [:]
    private var flights: [CGWindowID: Flight] = [:]
    private var timer: Timer?
    private var writers: [pid_t: Writer] = [:]

    func move(_ targets: [Target]) {
        let instant = targets.count > Self.instantAbove || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let now = CACurrentMediaTime()
        for target in targets {
            heading[target.id] = target.end
            if instant {
                flights[target.id] = nil
                writer(target.pid).write(target.element, id: target.id, frame: target.end, final: true)
            } else {
                flights[target.id] = Flight(target: target, start: now)
            }
        }
        guard !flights.isEmpty, timer == nil else { return }
        timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        timer.map { RunLoop.main.add($0, forMode: .common) }
        tick()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        for (id, flight) in flights {
            let progress = min(1, (now - flight.start) / Self.duration)
            let eased = 1 - pow(1 - progress, 3)
            let origin = flight.target.start, goal = flight.target.end
            let frame = CGRect(x: origin.minX + (goal.minX - origin.minX) * eased,
                               y: origin.minY + (goal.minY - origin.minY) * eased,
                               width: origin.width + (goal.width - origin.width) * eased,
                               height: origin.height + (goal.height - origin.height) * eased).integral
            writer(flight.target.pid).write(flight.target.element, id: id, frame: progress >= 1 ? goal : frame,
                                           final: progress >= 1)
            if progress >= 1 { flights[id] = nil }
        }
        if flights.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func writer(_ pid: pid_t) -> Writer {
        if let writer = writers[pid] { return writer }
        let writer = Writer(pid: pid) { [weak self] id, frame in
            DispatchQueue.main.async { if self?.heading[id] == frame { self?.heading[id] = nil } }
        }
        writers[pid] = writer
        return writer
    }
}

private final class Writer {
    private let pid: pid_t
    private let queue: DispatchQueue
    private let lock = NSLock()
    private struct Pending { let id: CGWindowID; let element: AXUIElement; let frame: CGRect; let final: Bool }
    private var pending: [CGWindowID: Pending] = [:]
    private var draining = false
    private var enhancedWasOn = false
    private let landed: (CGWindowID, CGRect) -> Void

    init(pid: pid_t, landed: @escaping (CGWindowID, CGRect) -> Void) {
        self.pid = pid
        self.landed = landed
        queue = DispatchQueue(label: "minimalcat.ax.\(pid)", qos: .userInteractive)
    }

    func write(_ element: AXUIElement, id: CGWindowID, frame: CGRect, final: Bool) {
        let start = lock.withLock { () -> Bool in
            let wasFinal = pending[id]?.final ?? false
            pending[id] = Pending(id: id, element: element, frame: frame, final: final || wasFinal)
            defer { draining = true }
            return !draining
        }
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        let app = AXUIElement.app(pid)
        // Enhanced UI (set by VoiceOver and some browsers) makes each frame write animate inside the app.
        if app.flag("AXEnhancedUserInterface") {
            enhancedWasOn = true
            app.set("AXEnhancedUserInterface", kCFBooleanFalse)
        }
        while true {
            let batch = lock.withLock { () -> [Pending] in
                let items = Array(pending.values)
                pending = [:]
                if items.isEmpty { draining = false }
                return items
            }
            if batch.isEmpty { break }
            for item in batch {
                if item.final {
                    item.element.setFrame(item.frame)
                    landed(item.id, item.frame)
                } else {
                    item.element.setStep(item.frame)
                }
            }
        }
        if enhancedWasOn {
            enhancedWasOn = false
            app.set("AXEnhancedUserInterface", kCFBooleanTrue)
        }
    }
}

private extension AXUIElement {
    func setStep(_ frame: CGRect) {
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            return
        }
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, sizeValue)
    }
}
