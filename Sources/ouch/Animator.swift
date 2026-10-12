import AppKit
import QuartzCore

/// Animates windows between frames by stepping their AX frame, then lands, verifies and corrects.
final class Animator {
    struct Move {
        let window: Window
        let to: CGRect
        let bounds: CGRect // visible area of the target screen, used to keep oversized windows on it
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
    private var quietUntil: [CGWindowID: CFTimeInterval] = [:]
    private var timer: Timer?
    /// Called when a window turns out to be bigger than its slot even after retrying.
    var onMinimumSize: ((CGWindowID, CGSize) -> Void)?

    /// True while we are moving the window ourselves, so its move/resize notifications are ours.
    func isBusy(_ id: CGWindowID) -> Bool {
        items[id] != nil || (quietUntil[id] ?? 0) > CACurrentMediaTime()
    }

    /// Stops animating a window (it's about to be parked somewhere else).
    func cancel(_ id: CGWindowID) {
        guard let item = items.removeValue(forKey: id) else { return }
        EnhancedUI.resume(item.move.window.pid)
    }

    /// Treat the next move/resize notifications for this window as our own.
    func quiet(_ id: CGWindowID, for seconds: Double = 0.4) {
        quietUntil[id] = CACurrentMediaTime() + seconds
    }

    func animate(_ moves: [Move], duration: Double, curve: AnimationCurve = .easeOut, bounce: Double = 0) {
        let now = CACurrentMediaTime()
        for m in moves {
            let id = m.window.id
            let from: CGRect
            if let running = items[id] {
                from = running.frame(at: now) // retarget smoothly from where it is mid-flight
            } else {
                from = m.window.frame
                EnhancedUI.suspend(m.window.pid)
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
            tick()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        for (id, item) in items {
            if now - item.start >= item.duration {
                items[id] = nil
                land(item.move)
            } else {
                let f = item.frame(at: now)
                item.move.window.setSize(f.size)
                item.move.window.setPosition(f.origin)
            }
        }
        if items.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func land(_ m: Move) {
        m.window.setFrame(m.to)
        quietUntil[m.window.id] = CACurrentMediaTime() + 0.4
        EnhancedUI.resume(m.window.pid)
        // Many apps apply frames asynchronously or snap to their own grid; check once it settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.verify(m) }
    }

    private func verify(_ m: Move) {
        let w = m.window
        guard items[w.id] == nil else { return } // re-animated since
        var actual = w.frame
        guard !actual.isNull, !actual.approxEqual(m.to, tolerance: 2) else { return }

        quietUntil[w.id] = CACurrentMediaTime() + 0.4
        EnhancedUI.suspend(w.pid)
        w.setFrame(m.to)
        actual = w.frame
        // Still too big => the app has a minimum size. Keep it anchored to its slot but on screen,
        // instead of hanging off the edge or covering the menu bar.
        if !actual.isNull, actual.width > m.to.width + 1 || actual.height > m.to.height + 1 {
            onMinimumSize?(w.id, CGSize(width: actual.width > m.to.width + 1 ? actual.width : 0,
                                        height: actual.height > m.to.height + 1 ? actual.height : 0))
            var o = m.to.origin
            o.x = max(m.bounds.minX, min(o.x, m.bounds.maxX - actual.width))
            o.y = max(m.bounds.minY, min(o.y, m.bounds.maxY - actual.height))
            w.setPosition(o)
        }
        EnhancedUI.resume(w.pid)
    }
}

private extension Animator.Item {
    func frame(at now: CFTimeInterval) -> CGRect {
        let t = min(1, max(0, (now - start) / duration))
        let e = CGFloat(curve.progress(t, bounce: bounce))
        let to = move.to
        // Springs and overshoot go past the target, so keep a shrinking window from inverting.
        return CGRect(x: from.minX + (to.minX - from.minX) * e,
                      y: from.minY + (to.minY - from.minY) * e,
                      width: max(1, from.width + (to.width - from.width) * e),
                      height: max(1, from.height + (to.height - from.height) * e)).pixelAligned
    }
}

/// How a window travels to its new frame. `progress` maps time (0...1) to distance covered;
/// springs, overshoot and some béziers pass 1 on the way, a bounce comes back short of it.
enum AnimationCurve: Hashable {
    case easeOut, easeInOut, linear, spring, bounce, overshoot
    /// CSS-style cubic-bezier(x1, y1, x2, y2); y outside 0...1 overshoots.
    case bezier(Double, Double, Double, Double)

    static let named: [AnimationCurve] = [.easeOut, .easeInOut, .linear, .spring, .bounce, .overshoot]

    /// Accepts `ease-out`, `spring`, `bounce`, …, and `cubic-bezier(x1, y1, x2, y2)` (or just the four numbers).
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
            var body = s
            if let open = body.firstIndex(of: "("), body.hasSuffix(")") {
                guard ["cubicbezier", "bezier"].contains(body[..<open]) else { return nil }
                body = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            }
            let n = body.split(separator: ",").compactMap { Double($0) }
            guard n.count == 4, body.split(separator: ",").count == 4, (0...1).contains(n[0]), (0...1).contains(n[2]) else { return nil }
            self = .bezier(n[0], n[1], n[2], n[3])
        }
    }

    /// The config file spelling.
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
    /// Whether the bounciness setting changes this curve.
    var usesBounce: Bool { self == .spring || self == .bounce || self == .overshoot }

    /// Distance covered at time `t` (both 0...1). `bounce` (0...1) is how lively springs, bounces and overshoot are.
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
            // easeOutBack; at 0 bounciness it's plain ease-out cubic.
            let s = 3.4 * b, u = t - 1
            return 1 + (s + 1) * u * u * u + s * u * u
        case .spring:
            // Damped spring, tuned to have settled (within ~0.2%) when the duration is up.
            let zeta = 1 - 0.75 * b, w = max(9.2, 6.5 / zeta)
            if zeta >= 1 { return 1 - exp(-w * t) * (1 + w * t) }
            let wd = w * (1 - zeta * zeta).squareRoot()
            return 1 - exp(-zeta * w * t) * (cos(wd * t) + zeta * w / wd * sin(wd * t))
        case .bounce:
            // A dropped ball: falls onto the target, then each bounce keeps `e` of its speed.
            let e = 0.3 + 0.4 * b
            var arcs: [Double] = [] // durations of the bounces, in units of the fall time
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
            // Find the curve parameter whose x is t (x is monotonic since x1, x2 are in 0...1).
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

    /// When the window first reaches its target (0...1), e.g. for an impact effect.
    func arrival(bounce: Double) -> Double {
        (0...500).lazy.map { Double($0) / 500 }.first { progress($0, bounce: bounce) >= 0.99 } ?? 1
    }
}
