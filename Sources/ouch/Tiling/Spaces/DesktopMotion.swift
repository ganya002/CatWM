import AppKit
import QuartzCore

@MainActor final class DesktopMotion: NSObject {
    private let screen: NSScreen
    private var callback: ((CADisplayLink) -> Void)?

    init(screen: NSScreen) { self.screen = screen }

    func animate(from: Double, to target: Double, with settings: NativeDesktopController.Settings,
                 update: @escaping (Double) throws -> Void) async throws {
        let duration = settings.duration * min(1, abs(target - from))
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

    func frames(_ count: Int) async throws {
        var frames = 0
        try await run(limit: 1, message: "The display stopped before the menu bar settled", fast: true) { _ in
            frames += 1
            return frames >= count
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
        let completion = Completion()
        let link = screen.displayLink(target: self, selector: #selector(step))
        if fast { link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120) }
        callback = { link in
            do {
                if try tick(link) { link.invalidate(); completion.finish(.success(())) }
            } catch { link.invalidate(); completion.finish(.failure(error)) }
        }
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(limit)) } catch { return }
            completion.finish(.failure(DesktopTransitionError.check(message)))
        }
        defer { timeout.cancel(); link.invalidate(); callback = nil }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                completion.wait(continuation)
                link.add(to: .main, forMode: .common)
            }
        } onCancel: {
            Task { @MainActor in completion.finish(.failure(CancellationError())) }
        }
    }

    @objc private func step(_ link: CADisplayLink) { callback?(link) }

    @MainActor private final class Completion {
        private var continuation: CheckedContinuation<Void, Error>?
        private var result: Result<Void, Error>?

        func wait(_ continuation: CheckedContinuation<Void, Error>) {
            if let result { continuation.resume(with: result) } else { self.continuation = continuation }
        }

        func finish(_ result: Result<Void, Error>) {
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}
