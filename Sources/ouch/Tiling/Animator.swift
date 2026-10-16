import AppKit
import QuartzCore


final class Animator {
    struct Move {
        let window: Window
        let to: CGRect
        let bounds: CGRect
        var from: CGRect? = nil
    }

    fileprivate struct Item {
        let move: Move
        let from: CGRect
        let start: CFTimeInterval
        let duration: Double
        let curve: AnimationCurve
        let bounce: Double
    }

    private var items: [CGWindowID: Item] = [:]
    private var landing: [CGWindowID: (move: Move, number: Int)] = [:]
    private var landings = 0
    private var quietUntil: [CGWindowID: CFTimeInterval] = [:]
    private var writers: [pid_t: AXWriter] = [:]
    private var timer: Timer?
    private var timing = Timing()
    private var frameRun: FrameRun?
    var onMinimumSize: ((CGWindowID, CGSize) -> Void)?

    func isBusy(_ id: CGWindowID) -> Bool {
        items[id] != nil || landing[id] != nil || (quietUntil[id] ?? 0) > CACurrentMediaTime()
    }

    func isMoving(_ id: CGWindowID, to frame: CGRect) -> Bool {
        (items[id]?.move.to ?? landing[id]?.move.to) == frame
    }

    func cancel(_ id: CGWindowID) {
        let item = items.removeValue(forKey: id), landed = landing.removeValue(forKey: id)
        guard let w = item?.move.window ?? landed?.move.window else { return }
        writer(w.pid).cancel(id)
    }

    func quiet(_ id: CGWindowID, for seconds: Double = 0.4) {
        quietUntil[id] = CACurrentMediaTime() + seconds
    }

    func animate(_ moves: [Move], duration: Double, curve: AnimationCurve = .easeOut, bounce: Double = 0) {
        let now = CACurrentMediaTime()
        for m in moves {
            let id = m.window.id
            let from: CGRect
            if let running = items[id] {
                from = running.frame(at: now)
            } else if let landed = landing.removeValue(forKey: id) {
                from = m.from ?? landed.move.to
            } else {
                from = m.from ?? m.window.cachedFrame
            }
            if duration < 0.01 || from.isNull || from.approxEqual(m.to, tolerance: 2) {
                items[id] = nil
                land(m)
            } else {
                items[id] = Item(move: m, from: from, start: now, duration: duration, curve: curve, bounce: bounce)
            }
        }
        if !items.isEmpty && timer == nil {
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            frameRun = PerfMonitor.begin("window-move")
            tick()
        }
    }

    private func writer(_ pid: pid_t) -> AXWriter {
        if let w = writers[pid] { return w }
        let w = AXWriter(pid: pid)
        writers[pid] = w
        return w
    }

    func afterPendingWrites(_ completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for writer in writers.values {
            group.enter()
            writer.run { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        timing.tick(at: now)
        for (id, item) in items {
            if now - item.start >= item.duration {
                items[id] = nil
                land(item.move)
            } else {
                writer(item.move.window.pid).step(item.move.window, to: item.frame(at: now))
            }
        }
        timing.ticks.add(CACurrentMediaTime() - now)
        if items.isEmpty {
            timer?.invalidate(); timer = nil
            let stats = writers.map { ($0.key, $0.value.takeStats()) }
            frameRun?.end(apps: stats.compactMap(Self.slowApp))
            frameRun = nil
            timing.log(stats)
            timing = Timing()
        }
    }

    private static func slowApp(_ pid: pid_t, _ s: AXWriter.Stats) -> PerfMonitor.SlowApp? {
        guard s.position.count > 0, let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        let step = (s.size.count > 0 ? s.size.total / Double(s.size.count) : 0) + s.position.total / Double(s.position.count)
        return .init(bundle: bundle, stepMs: step * 1000, skipped: Double(s.skipped) / Double(s.skipped + s.position.count))
    }

    private func land(_ m: Move) {
        let id = m.window.id
        landings += 1
        let number = landings
        landing[id] = (m, number)
        quietUntil[id] = CACurrentMediaTime() + 0.4
        writer(m.window.pid).land(m.window, at: m.to) { [weak self] in
            guard let self, self.landing[id]?.number == number else { return }
            self.landing[id] = nil
            CursorRefresh.soon()
            self.quietUntil[id] = CACurrentMediaTime() + 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.verify(m) }
        }
    }

    private func verify(_ m: Move) {
        let w = m.window
        guard items[w.id] == nil, landing[w.id] == nil else { return }
        quietUntil[w.id] = CACurrentMediaTime() + 0.4
        writer(w.pid).run { [weak self] in
            var actual = w.frame
            guard !actual.isNull, !actual.approxEqual(m.to, tolerance: 2) else { return }
            EnhancedUI.suspend(w.pid)
            w.setFrame(m.to)
            actual = w.frame
            var minimum: CGSize?
            if !actual.isNull, actual.width > m.to.width + 1 || actual.height > m.to.height + 1 {
                minimum = CGSize(width: actual.width > m.to.width + 1 ? actual.width : 0,
                                 height: actual.height > m.to.height + 1 ? actual.height : 0)
                var o = m.to.origin
                o.x = max(m.bounds.minX, min(o.x, m.bounds.maxX - actual.width))
                o.y = max(m.bounds.minY, min(o.y, m.bounds.maxY - actual.height))
                w.setPosition(o)
            }
            EnhancedUI.resume(w.pid)
            DispatchQueue.main.async {
                guard let self else { return }
                self.quietUntil[w.id] = CACurrentMediaTime() + 0.4
                if let minimum { self.onMinimumSize?(w.id, minimum) }
            }
        }
    }
}


fileprivate final class AXWriter {
    private enum Op { case step(CGRect), land(CGRect, done: () -> Void) }
    private struct Pending { let window: Window; let op: Op; let epoch: Int }
    struct Stats { var size = Stat(), position = Stat(), land = Stat(), skipped = 0 }

    let pid: pid_t
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [CGWindowID: Pending] = [:]
    private var epochs: [CGWindowID: Int] = [:]
    private var draining = false
    private var stats = Stats()
    private var animating: Set<CGWindowID> = []
    private var lastSize: [CGWindowID: CGSize] = [:]

    init(pid: pid_t) {
        self.pid = pid
        queue = DispatchQueue(label: "ouch.ax.\(pid)", qos: .userInteractive)
    }

    func step(_ w: Window, to frame: CGRect) { submit(w, .step(frame)) }
    func land(_ w: Window, at frame: CGRect, done: @escaping () -> Void) { submit(w, .land(frame, done: done)) }

    func cancel(_ id: CGWindowID) {
        lock.withLock { pending[id] = nil; epochs[id, default: 0] += 1 }
        queue.async { [self] in if animating.remove(id) != nil { EnhancedUI.resume(pid) } }
    }

    func run(_ f: @escaping () -> Void) { queue.async(execute: f) }

    func takeStats() -> Stats {
        lock.withLock { defer { stats = Stats() }; return stats }
    }

    private func submit(_ w: Window, _ op: Op) {
        let start = lock.withLock { () -> Bool in
            if case .step = pending[w.id]?.op { stats.skipped += 1 }
            pending[w.id] = Pending(window: w, op: op, epoch: epochs[w.id] ?? 0)
            defer { draining = true }
            return !draining
        }
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            let batch = lock.withLock { () -> [Pending] in
                let b = Array(pending.values)
                pending = [:]
                if b.isEmpty { draining = false }
                return b
            }
            if batch.isEmpty { return }
            for p in batch where lock.withLock({ epochs[p.window.id] ?? 0 }) == p.epoch { apply(p) }
        }
    }

    private func apply(_ p: Pending) {
        let w = p.window
        if animating.insert(w.id).inserted { EnhancedUI.suspend(pid) }
        switch p.op {
        case let .step(f):
            var s = 0.0
            if lastSize[w.id] != f.size {
                s = measure { w.setSize(f.size) }
                lastSize[w.id] = f.size
            }
            let o = measure { w.setPosition(f.origin) }
            lock.withLock { if s > 0 { stats.size.add(s) }; stats.position.add(o) }
        case let .land(f, done):
            lastSize[w.id] = nil
            let t = measure { w.setFrame(f) }
            animating.remove(w.id)
            EnhancedUI.resume(pid)
            lock.withLock { stats.land.add(t) }
            DispatchQueue.main.async(execute: done)
        }
    }
}

fileprivate struct Stat {
    var count = 0, total = 0.0, max = 0.0
    mutating func add(_ seconds: Double) { count += 1; total += seconds; max = Swift.max(max, seconds) }
    var text: String { count == 0 ? "-" : String(format: "avg %.2fms max %.2fms ×%d", total / Double(count) * 1000, max * 1000, count) }
}

private func measure(_ f: () -> Void) -> Double {
    let t = CACurrentMediaTime()
    f()
    return CACurrentMediaTime() - t
}


private extension Animator {
    struct Timing {
        var ticks = Stat(), gaps = Stat()
        var firstTick: CFTimeInterval?, lastTick: CFTimeInterval?

        mutating func tick(at now: CFTimeInterval) {
            if let lastTick { gaps.add(now - lastTick) }
            if firstTick == nil { firstTick = now }
            lastTick = now
        }

        func log(_ writers: [(pid_t, AXWriter.Stats)]) {
            let apps = writers.filter { $0.1.size.count + $0.1.position.count + $0.1.land.count > 0 }
            guard Log.verbose, ticks.count > 0 else { return }
            Log.debug(String(format: "animate: %d ticks in %.0fms (timer 8.33ms) | tick %@ | gap %@",
                             ticks.count, (CACurrentMediaTime() - (firstTick ?? 0)) * 1000, ticks.text, gaps.text))
            for (pid, s) in apps.sorted(by: { $0.1.size.total + $0.1.position.total > $1.1.size.total + $1.1.position.total }) {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
                Log.debug("animate:   \(name) (\(pid)) size \(s.size.text) | position \(s.position.text) | land \(s.land.text) | skipped \(s.skipped)")
            }
        }
    }
}


enum CursorRefresh {
    private static var work: DispatchWorkItem?

    static func soon(after delay: Double = 0.08) {
        work?.cancel()
        let w = DispatchWorkItem { post() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private static func post() {
        guard NSEvent.pressedMouseButtons == 0,
              let here = CGEvent(source: nil)?.location,
              let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                              mouseCursorPosition: here, mouseButton: .left) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    static func isOurs(_ e: NSEvent) -> Bool {
        e.cgEvent?.getIntegerValueField(.eventSourceUserData) == Hotkeys.syntheticMarker
    }
}


private extension Animator.Item {
    func frame(at now: CFTimeInterval) -> CGRect {
        let t = min(1, max(0, (now - start) / duration))
        let e = CGFloat(curve.progress(t, bounce: bounce))
        let to = move.to
        return CGRect(x: from.minX + (to.minX - from.minX) * e,
                      y: from.minY + (to.minY - from.minY) * e,
                      width: max(1, from.width + (to.width - from.width) * e),
                      height: max(1, from.height + (to.height - from.height) * e)).pixelAligned
    }
}

enum AnimationCurve: Hashable {
    case easeOut, easeInOut, linear, spring, bounce, overshoot
    case bezier(Double, Double, Double, Double)

    static let named: [AnimationCurve] = [.easeOut, .easeInOut, .linear, .spring, .bounce, .overshoot]

    init?(_ text: String) {
        let s = text.lowercased().filter { !" -_".contains($0) }
        switch s {
        case "easeout", "ease", "default": self = .easeOut
        case "easeinout": self = .easeInOut
        case "linear": self = .linear
        case "spring", "springy": self = .spring
        case "bounce", "bouncy": self = .bounce
        case "overshoot", "back", "easeoutback": self = .overshoot
        default:
            var body = text.lowercased().filter { !$0.isWhitespace }
            if let open = body.firstIndex(of: "("), body.hasSuffix(")") {
                guard ["cubicbezier", "bezier"].contains(body[..<open].filter { !"-_".contains($0) }) else { return nil }
                body = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            }
            let n = body.split(separator: ",").compactMap { Double($0) }
            guard n.count == 4, body.split(separator: ",").count == 4, (0...1).contains(n[0]), (0...1).contains(n[2]) else { return nil }
            self = .bezier(n[0], n[1], n[2], n[3])
        }
    }

    var name: String {
        switch self {
        case .easeOut: "ease-out"
        case .easeInOut: "ease-in-out"
        case .linear: "linear"
        case .spring: "spring"
        case .bounce: "bounce"
        case .overshoot: "overshoot"
        case let .bezier(a, b, c, d): "cubic-bezier(" + [a, b, c, d].map { String(format: "%g", $0) }.joined(separator: ", ") + ")"
        }
    }

    var title: String {
        switch self {
        case .easeOut: "Ease Out"
        case .easeInOut: "Ease In and Out"
        case .linear: "Linear"
        case .spring: "Spring"
        case .bounce: "Bounce"
        case .overshoot: "Overshoot"
        case .bezier: "Custom Bézier"
        }
    }

    var isBezier: Bool { if case .bezier = self { true } else { false } }
    var usesBounce: Bool { self == .spring || self == .bounce || self == .overshoot }

    func progress(_ t: Double, bounce b: Double) -> Double {
        let t = min(1, max(0, t)), b = min(1, max(0, b))
        guard t < 1 else { return 1 }
        switch self {
        case .easeOut:
            return 1 - pow(1 - t, 3)
        case .easeInOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(2 - 2 * t, 3) / 2
        case .linear:
            return t
        case .overshoot:
            let s = 3.4 * b, u = t - 1
            return 1 + (s + 1) * u * u * u + s * u * u
        case .spring:
            let zeta = 1 - 0.75 * b, w = max(9.2, 6.5 / zeta)
            if zeta >= 1 { return 1 - exp(-w * t) * (1 + w * t) }
            let wd = w * (1 - zeta * zeta).squareRoot()
            return 1 - exp(-zeta * w * t) * (cos(wd * t) + zeta * w / wd * sin(wd * t))
        case .bounce:
            let e = 0.3 + 0.4 * b
            var arcs: [Double] = []
            while arcs.count < 12, pow(e, Double(2 * (arcs.count + 1))) > 0.003 { arcs.append(2 * pow(e, Double(arcs.count + 1))) }
            var x = t * (1 + arcs.reduce(0, +))
            if x < 1 { return x * x }
            x -= 1
            for (i, d) in arcs.enumerated() {
                if x < d {
                    let u = x / d * 2 - 1
                    return 1 - pow(e, Double(2 * (i + 1))) * (1 - u * u)
                }
                x -= d
            }
            return 1
        case let .bezier(x1, y1, x2, y2):
            func coord(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
                3 * (1 - s) * (1 - s) * s * p1 + 3 * (1 - s) * s * s * p2 + s * s * s
            }
            var lo = 0.0, hi = 1.0, s = t
            for _ in 0..<30 {
                let x = coord(s, x1, x2)
                if abs(x - t) < 1e-6 { break }
                if x < t { lo = s } else { hi = s }
                s = (lo + hi) / 2
            }
            return coord(s, y1, y2)
        }
    }

    func arrival(bounce: Double) -> Double {
        (0...500).lazy.map { Double($0) / 500 }.first { progress($0, bounce: bounce) >= 0.99 } ?? 1
    }
}
