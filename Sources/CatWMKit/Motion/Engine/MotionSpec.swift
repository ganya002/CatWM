import Foundation

package struct MotionSpec: Equatable {
    package var duration: Double
    package var curve: AnimationCurve
    package var bounce: Double

    package static let instant = MotionSpec(duration: 0, curve: .linear, bounce: 0)

    package init(duration: Double, curve: AnimationCurve, bounce: Double) {
        self.duration = duration
        self.curve = curve
        self.bounce = bounce
    }

    package init(_ config: Config) {
        self.init(duration: config.animate ? config.animationDuration : 0,
                  curve: config.animationCurve, bounce: config.animationBounce)
    }

    package func scaled(by factor: Double) -> MotionSpec {
        MotionSpec(duration: duration * factor, curve: curve, bounce: bounce)
    }
}
