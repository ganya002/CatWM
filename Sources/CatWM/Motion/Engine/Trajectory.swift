import Foundation

struct Trajectory: Equatable {
    let origin: Double
    private(set) var destination: Double
    let duration: Double
    let curve: AnimationCurve
    let bounce: Double
    private let carry: Double

    init(from origin: Double, to destination: Double, spec: MotionSpec, velocity: Double? = nil) {
        self.origin = origin
        self.destination = destination
        duration = spec.duration
        curve = spec.curve
        bounce = spec.bounce
        guard let velocity, spec.duration > 0 else { carry = 0; return }
        let probe = 1e-3
        let slope = spec.curve.progress(probe, bounce: spec.bounce) / probe
        carry = velocity * spec.duration - (destination - origin) * slope
    }

    func retargeted(to end: Double) -> Trajectory {
        var copy = self
        copy.destination = end
        return copy
    }

    func value(at elapsed: Double) -> Double {
        guard duration > 0 else { return destination }
        let time = min(1, max(0, elapsed / duration))
        let settle = time * (1 - time) * (1 - time)
        return origin + (destination - origin) * curve.progress(time, bounce: bounce) + carry * settle
    }

    func velocity(at elapsed: Double) -> Double {
        guard duration > 0, elapsed < duration else { return 0 }
        let step = min(1e-3, duration / 100)
        let before = max(0, elapsed - step), after = min(duration, elapsed + step)
        return (value(at: after) - value(at: before)) / (after - before)
    }
}
