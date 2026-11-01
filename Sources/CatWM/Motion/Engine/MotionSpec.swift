import Foundation

struct MotionSpec: Equatable {
    var duration: Double
    var curve: AnimationCurve
    var bounce: Double

    static let instant = MotionSpec(duration: 0, curve: .linear, bounce: 0)

    init(duration: Double, curve: AnimationCurve, bounce: Double) {
        self.duration = duration
        self.curve = curve
        self.bounce = bounce
    }

    init(_ config: Config) {
        self.init(duration: config.animate ? config.animationDuration : 0,
                  curve: config.animationCurve, bounce: config.animationBounce)
    }

    func scaled(by factor: Double) -> MotionSpec {
        MotionSpec(duration: duration * factor, curve: curve, bounce: bounce)
    }
}
