import AppKit
import QuartzCore

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
