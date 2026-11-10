import AppKit
import QuartzCore

package enum AnimationCurve: Hashable {
    case easeOut, easeInOut, linear, spring, bounce, overshoot
    case bezier(Double, Double, Double, Double)

    package static let named: [AnimationCurve] = [.easeOut, .easeInOut, .linear, .spring, .bounce, .overshoot]

    package init?(_ text: String) {
        let compact = text.lowercased().filter { !" -_".contains($0) }
        switch compact {
        case "easeout", "ease", "default": self = .easeOut
        case "easeinout": self = .easeInOut
        case "linear": self = .linear
        case "spring", "springy": self = .spring
        case "bounce", "bouncy": self = .bounce
        case "overshoot", "back", "easeoutback": self = .overshoot
        default:
            var body = text.lowercased().filter { !$0.isWhitespace }
            if let open = body.firstIndex(of: "("), body.hasSuffix(")") {
                guard ["cubicbezier", "bezier"].contains(body[..<open].filter { !"-_".contains($0) }) else {
                    return nil
                }
                body = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            }
            let numbers = body.split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 4, body.split(separator: ",").count == 4,
                  (0...1).contains(numbers[0]), (0...1).contains(numbers[2]) else { return nil }
            self = .bezier(numbers[0], numbers[1], numbers[2], numbers[3])
        }
    }

    package var name: String {
        switch self {
        case .easeOut: "ease-out"
        case .easeInOut: "ease-in-out"
        case .linear: "linear"
        case .spring: "spring"
        case .bounce: "bounce"
        case .overshoot: "overshoot"
        case let .bezier(firstX, firstY, secondX, secondY):
            "cubic-bezier("
                + [firstX, firstY, secondX, secondY].map { String(format: "%g", $0) }.joined(separator: ", ")
                + ")"
        }
    }

    package var title: String {
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

    package var isBezier: Bool { if case .bezier = self { true } else { false } }
    package var usesBounce: Bool { self == .spring || self == .bounce || self == .overshoot }

    package func progress(_ rawTime: Double, bounce rawBounce: Double) -> Double {
        let time = min(1, max(0, rawTime)), bounce = min(1, max(0, rawBounce))
        guard time < 1 else { return 1 }
        switch self {
        case .easeOut:
            return 1 - pow(1 - time, 3)
        case .easeInOut:
            return time < 0.5 ? 4 * time * time * time : 1 - pow(2 - 2 * time, 3) / 2
        case .linear:
            return time
        case .overshoot:
            let strength = 3.4 * bounce, shifted = time - 1
            return 1 + (strength + 1) * shifted * shifted * shifted + strength * shifted * shifted
        case .spring:
            return Self.springProgress(time, bounce: bounce)
        case .bounce:
            return Self.bounceProgress(time, bounce: bounce)
        case let .bezier(firstX, firstY, secondX, secondY):
            return Self.bezierProgress(time, firstX, firstY, secondX, secondY)
        }
    }

    private static func springProgress(_ time: Double, bounce: Double) -> Double {
        let zeta = 1 - 0.75 * bounce, omega = max(9.2, 6.5 / zeta)
        if zeta >= 1 { return 1 - exp(-omega * time) * (1 + omega * time) }
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * time) * (cos(damped * time) + zeta * omega / damped * sin(damped * time))
    }

    private static func bounceProgress(_ time: Double, bounce: Double) -> Double {
        let restitution = 0.3 + 0.4 * bounce
        var count = 0, total = 1.0, height = restitution
        while count < 12, pow(restitution, Double(2 * (count + 1))) > 0.003 {
            total += 2 * height
            count += 1
            height *= restitution
        }
        var x = time * total
        if x < 1 { return x * x }
        x -= 1
        height = restitution
        for _ in 0..<count {
            let arc = 2 * height
            if x < arc {
                let position = x / arc * 2 - 1
                return 1 - height * height * (1 - position * position)
            }
            x -= arc
            height *= restitution
        }
        return 1
    }

    private static func bezierProgress(
        _ time: Double, _ firstX: Double, _ firstY: Double, _ secondX: Double, _ secondY: Double
    ) -> Double {
        func coord(_ param: Double, _ first: Double, _ second: Double) -> Double {
            3 * (1 - param) * (1 - param) * param * first + 3 * (1 - param) * param * param * second
                + param * param * param
        }
        var low = 0.0, high = 1.0, param = time
        for _ in 0..<30 {
            let x = coord(param, firstX, secondX)
            if abs(x - time) < 1e-6 { break }
            if x < time { low = param } else { high = param }
            param = (low + high) / 2
        }
        return coord(param, firstY, secondY)
    }

    package func arrival(bounce: Double) -> Double {
        (0...500).lazy.map { Double($0) / 500 }.first { progress($0, bounce: bounce) >= 0.99 } ?? 1
    }
}
