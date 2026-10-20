import AppKit
import QuartzCore

@MainActor final class DesktopMotion: NSObject {
    private let screen: NSScreen
    private var callback: ((CADisplayLink) -> Void)?

    init(screen: NSScreen) { self.screen = screen }

    func animate(from: Double, to target: Double, with settings: NativeDesktopController.Settings,
                 update: @escaping (Double) throws -> Void) async throws {
        let duration = settings.duration
        if duration <= 0 { try update(target); return }
        let start = CACurrentMediaTime()
        try update(from)
        try await run(limit: duration + 2, message: "Display link stopped before the animation finished",
                      fast: true) { link in
            let time = min(1, max(0, (link.targetTimestamp - start) / duration))
            try update(from + (target - from) * settings.curve.progress(time, bounce: settings.bounce))
            return time >= 1
        }
    }

    func follow(until finished: @escaping () -> Bool, update: @escaping () throws -> Void) async throws {
        try await run(limit: 180, message: "The Desktop swipe did not end", fast: false) { _ in
            try update()
            return finished()
        }
    }

    private func run(limit: Double, message: String, fast: Bool,
                     tick: @escaping (CADisplayLink) throws -> Bool) async throws {
        var failure: Error?
        var complete = false
        let link = screen.displayLink(target: self, selector: #selector(step))
        if fast { link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120) }
        callback = { link in
            do { complete = try tick(link) } catch { failure = error; complete = true }
            if complete { link.invalidate() }
        }
        defer { link.invalidate(); callback = nil }
        link.add(to: .main, forMode: .common)
        guard await poll(limit, until: { complete }) else { throw DesktopTransitionError.check(message) }
        if let failure { throw failure }
    }

    @objc private func step(_ link: CADisplayLink) { callback?(link) }
}
