import Foundation

package struct MotionStyle: Sendable {
    package let name: String
    package var animate = true
    package var curve: AnimationCurve = .easeOut
    package var duration = 0.2
    package var bounce = 0.5

    package static let all: [MotionStyle] = [
        MotionStyle(name: "None", animate: false),
        MotionStyle(name: "Snappy", duration: 0.12),
        MotionStyle(name: "Relaxed", curve: .easeInOut, duration: 0.35)
    ]

    package var id: String { name.lowercased() }

    package func matches(_ config: Config) -> Bool {
        guard animate else { return !config.animate }
        return config.animate && config.animationCurve == curve
            && abs(config.animationDuration - duration) < 0.005
            && (!curve.usesBounce || abs(config.animationBounce - bounce) < 0.005)
    }

    package func apply(to config: inout Config) {
        config.animate = animate
        guard animate else { return }
        config.animationCurve = curve
        config.animationDuration = duration
        if curve.usesBounce { config.animationBounce = bounce }
    }

    package var fields: [String: JSON] {
        var fields: [String: JSON] = ["enabled": .bool(animate)]
        guard animate else { return fields }
        fields["curve"] = .string(curve.name)
        fields["duration"] = .number(duration)
        if curve.usesBounce { fields["bounce"] = .number(bounce) }
        return fields
    }
}
