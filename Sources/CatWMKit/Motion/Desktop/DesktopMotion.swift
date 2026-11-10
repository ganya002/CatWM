import AppKit
import QuartzCore

@MainActor package final class DesktopMotion: NSObject {
    private var preparedTarget: CFTimeInterval?
    private let screen: NSScreen?
    private var callback: ((CADisplayLink) -> Void)?
    private var sample: Sample?

    private struct Sample {
        package let value: Double
        package let time: CFTimeInterval
        package let velocity: Double
    }

    package init(screen: NSScreen?) { self.screen = screen }

    package func animate(from: Double, to target: Double, with settings: MotionSpec,
                         update: @escaping (Double) throws -> Void) async throws {
        let prepared = preparedTarget
        preparedTarget = nil
        let start = CACurrentMediaTime()
        let inherited = inheritedVelocity(at: start)
        let spec = settings.scaled(by: max(Self.shortest, min(1, abs(target - from))))
        let trajectory = Trajectory(from: from, to: target, spec: spec, velocity: inherited)
        func submit(_ value: Double, at time: CFTimeInterval) throws {
            try update(value)
            remember(value, at: time)
        }
        if spec.duration <= 0 { try submit(target, at: start); return }
        try submit(from, at: start)
        if let prepared, prepared > start {
            try Task.checkCancellation()
            let elapsed = prepared - start
            try submit(trajectory.value(at: elapsed), at: prepared)
            if elapsed >= spec.duration { return }
        }
        try await run(limit: spec.duration + 2, message: "Display link stopped before the animation finished",
                      fast: true) { link in
            let elapsed = max(0, link.targetTimestamp - start)
            try submit(trajectory.value(at: elapsed), at: link.targetTimestamp)
            return elapsed >= spec.duration
        }
    }

    package func frames(_ count: Int) async throws {
        preparedTarget = nil
        var frames = 0
        try await run(limit: 1, message: "The display stopped before the menu bar settled", fast: true) { link in
            frames += 1
            if frames >= count { self.preparedTarget = link.targetTimestamp }
            return frames >= count
        }
    }

    package func follow(until finished: @escaping () -> Bool, update: @escaping () throws -> Double) async throws {
        preparedTarget = nil
        try await run(limit: 180, message: "The Desktop swipe did not end", fast: false) { link in
            self.remember(try update(), at: link.targetTimestamp)
            return finished()
        }
    }

    private static let shortest = 0.4
    private static let freshness = 0.06
    private static let fastest = 24.0

    private func remember(_ value: Double, at time: CFTimeInterval) {
        guard let last = sample, time > last.time else {
            sample = Sample(value: value, time: time, velocity: 0)
            return
        }
        let step = (value - last.value) / (time - last.time)
        let blended = last.velocity == 0 ? step : last.velocity * 0.3 + step * 0.7
        sample = Sample(value: value, time: time, velocity: blended)
    }

    private func inheritedVelocity(at time: CFTimeInterval) -> Double? {
        defer { sample = nil }
        guard let sample, time - sample.time < Self.freshness else { return nil }
        return min(Self.fastest, max(-Self.fastest, sample.velocity))
    }

    private func run(limit: Double, message: String, fast: Bool,
                     tick: @escaping (CADisplayLink) throws -> Bool) async throws {
        let completion = Completion()
        guard let link = screen?.displayLink(target: self, selector: #selector(step)) else {
            throw DesktopTransitionError.check("The display has no screen")
        }
        if fast { link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120) }
        callback = { link in
            do {
                if try tick(link) { link.invalidate(); completion.finish(.success(())) }
            } catch { link.invalidate(); completion.finish(.failure(error)) }
        }
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(limit)) } catch { return } // style-ok: limit for a stopped link
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

        package func wait(_ continuation: CheckedContinuation<Void, Error>) {
            if let result { continuation.resume(with: result) } else { self.continuation = continuation }
        }

        package func finish(_ result: Result<Void, Error>) {
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}
