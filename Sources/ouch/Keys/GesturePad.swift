// Keys: trackpad gesture binds as the keyboard help draws them.
import AppKit
import SwiftUI

/// One trackpad bind as the keyboard help draws it: how many fingers, which way they move, and the
/// workspaces it goes between.
struct GestureBind: Identifiable {
    let mods: NSEvent.ModifierFlags
    let fingers: Int
    /// The way the fingers move, y down.
    let direction: CGVector
    /// "two fingers up"
    let phrase: String
    /// "Next workspace"
    let title: String
    /// Workspace numbers to slide across the pad, when the bind changes workspace.
    let from: String?, to: String?
    let id: String

    /// Scroll binds use two fingers, swipes three. Scrolling follows the system's direction setting:
    /// with natural scrolling (the default) a scroll down is fingers moving up.
    init?(_ b: KeyBinding, current: Int) {
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        let flip: CGFloat = natural ? 1 : -1
        let dir: CGVector
        switch b.keyCode {
        case SpecialKey.swipeLeft: dir = CGVector(dx: -1, dy: 0)
        case SpecialKey.swipeRight: dir = CGVector(dx: 1, dy: 0)
        case SpecialKey.swipeUp: dir = CGVector(dx: 0, dy: -1)
        case SpecialKey.swipeDown: dir = CGVector(dx: 0, dy: 1)
        case SpecialKey.mouseUp: dir = CGVector(dx: 0, dy: flip)
        case SpecialKey.mouseDown: dir = CGVector(dx: 0, dy: -flip)
        case SpecialKey.mouseLeft: dir = CGVector(dx: flip, dy: 0)
        case SpecialKey.mouseRight: dir = CGVector(dx: -flip, dy: 0)
        default: return nil
        }
        mods = KeyHelp.mods(b.mods)
        fingers = SpecialKey.isSwipe(b.keyCode) ? 3 : 2
        direction = dir
        let way = dir.dx < 0 ? "left" : dir.dx > 0 ? "right" : dir.dy < 0 ? "up" : "down"
        phrase = "\(fingers == 3 ? "three" : "two") fingers \(way)"
        let single = BindRow(mods: "", key: "", dispatcher: b.dispatcher, args: b.arg)
        let t = Actions.match(single)?.title ?? "\(b.dispatcher) \(b.arg)"
        title = t.prefix(1) + t.dropFirst().lowercased()
        id = "\(b.keyCode) \(b.mods.rawValue)"

        let arg = b.arg.trimmingCharacters(in: .whitespaces).lowercased()
        var target: Int?
        if ["workspace", "movetoworkspace", "movetoworkspacesilent"].contains(b.dispatcher) {
            if let n = Int(arg) { target = n }
            else if arg.hasSuffix("+1") { target = current % 10 + 1 }
            else if arg.hasSuffix("-1") { target = current == 1 ? 10 : current - 1 }
        }
        from = target.map { _ in "\(current)" }
        to = target.map { "\($0)" }
    }
}

/// A trackpad looping its gesture binds: one hand of fingertips with a palm glow under it, a light
/// streak behind it, a ripple where it lands and lifts, and the workspace numbers sliding faintly
/// across the surface. 2.4 s per loop, the next bind each time round.
struct GesturePad: View {
    let gestures: [GestureBind]
    static let width: CGFloat = 264
    static let height: CGFloat = 172
    private static let loop = 2.4
    /// One clock for every pad, so redrawing the help (⇧ changes the layer) doesn't restart the loop.
    private static let epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Under Reduce Motion the pad shows each bind as a still, mid-gesture, and steps between them.
        Group {
            if reduceMotion {
                TimelineView(.periodic(from: Self.epoch, by: Self.loop)) { ctx in frame(ctx.date, still: true) }
            } else {
                TimelineView(.animation) { ctx in frame(ctx.date, still: false) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gestures.map { "\(ConfigDocument.modifierCaps($0.mods).joined()) \($0.phrase): \($0.title)" }.joined(separator: ", "))
    }

    private func frame(_ date: Date, still: Bool) -> some View {
        let t = max(0, date.timeIntervalSince(Self.epoch))
        let g = gestures[Int(t / Self.loop) % gestures.count]
        let f = still ? 0.55 : t.truncatingRemainder(dividingBy: Self.loop) / Self.loop
        return VStack(spacing: 10) {
            surface(g, f)
            caption(g)
        }
    }

    // MARK: Timing

    /// The loop as fractions: land, travel, lift.
    private struct Pose {
        var progress: Double // 0...1 along the path, eased
        var presence: Double // fingers' opacity
        var down: Double? // touch-down ripple, 0...1
        var lift: Double? // lift ripple, 0...1
    }

    private func pose(_ f: Double) -> Pose {
        func span(_ a: Double, _ b: Double) -> Double { min(1, max(0, (f - a) / (b - a))) }
        let land = 0.08, travelStart = 0.14, travelEnd = 0.7, liftAt = 0.72
        let presence = f < land ? span(0.02, land) : f < travelEnd ? 1 : 1 - span(travelEnd, 0.8)
        return Pose(progress: Self.ease(span(travelStart, travelEnd)), presence: presence,
                    down: f >= land && f < land + 0.3 ? span(land, land + 0.3) : nil,
                    lift: f >= liftAt && f < liftAt + 0.28 ? span(liftAt, liftAt + 0.28) : nil)
    }

    /// cubic-bezier(.5, 0, .2, 1), solved for x by bisection.
    static func ease(_ x: Double) -> Double {
        let (x1, y1, x2, y2) = (0.5, 0.0, 0.2, 1.0)
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            if bez(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return bez(t, y1, y2)
    }

    // MARK: Drawing

    private func surface(_ g: GestureBind, _ f: Double) -> some View {
        let w = Self.width, h = Self.height
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let p = pose(f)
        let d = g.direction
        let travel = d.dx != 0 ? w * 0.42 : h * 0.4
        let center = CGPoint(x: w / 2, y: h / 2 + 8)
        let from = CGPoint(x: center.x - d.dx * travel / 2, y: center.y - d.dy * travel / 2)
        let hand = CGPoint(x: from.x + d.dx * travel * p.progress, y: from.y + d.dy * travel * p.progress)
        let end = CGPoint(x: from.x + d.dx * travel, y: from.y + d.dy * travel)
        let slide = d.dx != 0 ? w * 0.55 : h * 0.6

        return ZStack {
            shape.fill(Theme.well)
            shape.strokeBorder(Theme.hairline, lineWidth: 1)

            // Workspace numbers sliding across in the fingers' direction, faintly.
            if let a = g.from, let b = g.to {
                Group {
                    Text(a).offset(x: d.dx * slide * p.progress, y: d.dy * slide * p.progress)
                        .opacity(0.14 * (1 - p.progress))
                    Text(b).offset(x: -d.dx * slide * (1 - p.progress), y: -d.dy * slide * (1 - p.progress))
                        .opacity(0.14 * p.progress)
                }
                .font(Theme.display(64)).monospacedDigit()
            }

            // One streak behind the whole hand, from where it landed.
            Path { path in path.move(to: from); path.addLine(to: hand) }
                .stroke(LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.16)],
                                       startPoint: unit(from, w, h), endPoint: unit(hand, w, h)),
                        style: StrokeStyle(lineWidth: g.fingers == 3 ? 46 : 34, lineCap: .round))
                .opacity(p.presence)

            // The palm: a soft glow under and behind the fingertips, moving with them.
            Ellipse()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: 62))
                .frame(width: 130, height: 104)
                .position(x: hand.x, y: hand.y + 30)
                .opacity(p.presence)

            if let r = p.down { ripple(r).position(from) }
            if let r = p.lift { ripple(r).position(end) }

            ForEach(Array(tips(g.fingers).enumerated()), id: \.offset) { _, o in
                Circle()
                    .fill(Theme.ink.opacity(0.88))
                    .overlay(Circle().strokeBorder(Theme.ink.opacity(0.35), lineWidth: 3).padding(-3))
                    .frame(width: 20, height: 20)
                    .position(x: hand.x + o.x, y: hand.y + o.y)
            }
            .opacity(p.presence)

            Kbd(keys: ConfigDocument.modifierCaps(g.mods))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .frame(width: w, height: h)
        .clipShape(shape)
    }

    /// Fingertips pressed together as one hand: two about 32pt apart, three in a slight arc.
    private func tips(_ n: Int) -> [CGPoint] {
        n == 3 ? [CGPoint(x: -28, y: 4), CGPoint(x: 0, y: -3), CGPoint(x: 28, y: 4)]
            : [CGPoint(x: -16, y: 0), CGPoint(x: 16, y: 0)]
    }

    private func ripple(_ r: Double) -> some View {
        Circle().strokeBorder(Theme.ink.opacity(0.5 * (1 - r)), lineWidth: 1.5)
            .frame(width: 30 + 70 * r, height: 30 + 70 * r)
    }

    private func unit(_ p: CGPoint, _ w: CGFloat, _ h: CGFloat) -> UnitPoint { UnitPoint(x: p.x / w, y: p.y / h) }

    /// ⌥ Kbd, "two fingers up", "Next workspace".
    private func caption(_ g: GestureBind) -> some View {
        HStack(spacing: 6) {
            if !g.mods.isEmpty { Kbd(keys: ConfigDocument.modifierCaps(g.mods)) }
            Text(g.phrase).foregroundStyle(Theme.inkMuted).oneLine()
            Text(g.title).oneLine()
        }
        .font(Theme.body(12.5))
        .fixedSize()
        .frame(height: 20)
    }
}
