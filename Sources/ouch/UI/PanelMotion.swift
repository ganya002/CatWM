// UI: entrance and exit animations for the Sort panel and Keyboard Help.
import AppKit
import SwiftUI

/// How the Sort panel and Keyboard Help come and go: `panel-animation` in the config, in Settings under
/// Motion › Advanced. `ouch panelfx <style>` previews one, `ouch panelfx all` plays them in turn.
/// Under Reduce Motion every style is a plain fade.
enum PanelMotion: String, CaseIterable {
    /// Rises a little from where it sits and settles.
    case rise
    /// Springs up from its bottom edge with a slight squish, like the icon's tiles.
    case pop
    /// Comes into focus: blurred and a touch large, then sharp.
    case focus
    /// Snaps into place like a window being tiled, on the config's own curve, duration and bounce;
    /// Sort's lanes start stacked and spread out like a retile, the keys spread from the middle.
    case tile
    /// Like window mode's `draw` effect: an accent line with a bright head traces the outline from top
    /// centre both ways, the glass fills in behind it, then the line fades.
    case draw

    /// The configured style, or the one a preview is playing.
    static var current: PanelMotion { preview ?? WindowManager.shared.config.panelAnimation }
    static var preview: PanelMotion?

    var title: String {
        switch self {
        case .rise: "Rise"
        case .pop: "Pop"
        case .focus: "Focus"
        case .tile: "Tile"
        case .draw: "Draw"
        }
    }

    /// How long to keep the window up after hiding, so the way out can play.
    var outDuration: Double { self == .focus ? 0.22 : self == .pop ? 0.2 : 0.18 }

    func animation(in shown: Bool) -> Animation {
        guard shown else {
            return self == .focus ? .easeIn(duration: outDuration) : .timingCurve(0.4, 0, 1, 1, duration: outDuration)
        }
        switch self {
        case .rise: return .spring(response: 0.38, dampingFraction: 0.86)
        case .pop: return .spring(response: 0.42, dampingFraction: 0.58)
        case .focus: return .timingCurve(0.16, 1, 0.3, 1, duration: 0.42)
        case .tile: return .linear(duration: Self.tileDuration) // the curve itself is applied in TileProgress
        case .draw: return .linear(duration: 0.45)
        }
    }

    /// Windows move in `animation-duration` (0.18s by default); a panel is bigger, so a bit longer.
    static var tileDuration: Double { max(0.3, WindowManager.shared.config.animationDuration * 1.7) }
}

/// The panel surface coming and going. Anchored at the bottom: both panels sit low on the screen.
struct PanelEntrance: ViewModifier {
    let shown: Bool
    let style: PanelMotion
    /// The surface's corner radius, for `.draw`'s outline.
    var radius: CGFloat = Theme.Radius.xl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(shown ? 1 : 0).animation(.easeOut(duration: Theme.medium), value: shown)
        } else {
            switch style {
            case .tile:
                content.modifier(TileProgress(t: shown ? 1 : 0, shown: shown, surface: true))
                    .animation(style.animation(in: shown), value: shown)
            case .draw:
                content.modifier(DrawEntrance(shown: shown, radius: radius))
            default:
                content
                    .opacity(shown ? 1 : 0)
                    .blur(radius: style == .focus && !shown ? 14 : 0)
                    .scaleEffect(x: shown ? 1 : scale.x, y: shown ? 1 : scale.y, anchor: .bottom)
                    .offset(y: shown ? 0 : lift)
                    .animation(style.animation(in: shown), value: shown)
            }
        }
    }

    private var lift: CGFloat { style == .rise ? 22 : style == .pop ? 14 : 0 }

    private var scale: (x: CGFloat, y: CGFloat) {
        switch style {
        case .rise: (0.985, 0.985)
        // Pop squishes: shorter than it is narrow, so the spring stretches it up past full height.
        case .pop: (0.82, 0.7)
        case .focus: (1.04, 1.04)
        case .tile, .draw: (1, 1)
        }
    }
}

/// A piece of content that travels in `.tile`: a Sort lane, a key. `spread` is where it starts,
/// relative to where it ends.
struct TileItem: ViewModifier {
    let shown: Bool
    let style: PanelMotion
    let spread: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if style == .tile && !reduceMotion {
            content.modifier(TileProgress(t: shown ? 1 : 0, shown: shown, surface: false, spread: spread))
                .animation(style.animation(in: shown), value: shown)
        } else {
            content
        }
    }
}

extension View {
    func panelEntrance(_ shown: Bool, style: PanelMotion, radius: CGFloat = Theme.Radius.xl) -> some View {
        modifier(PanelEntrance(shown: shown, style: style, radius: radius))
    }

    func tileItem(_ shown: Bool, style: PanelMotion, spread: CGSize) -> some View {
        modifier(TileItem(shown: shown, style: style, spread: spread))
    }
}

/// `.tile`: time runs linearly and the window animation curve maps it to distance, so the panel moves
/// exactly like a window with the config's curve and bounce (overshoot and springs included).
private struct TileProgress: ViewModifier, Animatable {
    var t: Double
    let shown: Bool
    /// The surface grows from a small slot; content items travel by `spread`.
    let surface: Bool
    var spread: CGSize = .zero

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let c = WindowManager.shared.config
        // On the way out it simply shrinks back, no bounce.
        let e = CGFloat(shown ? c.animationCurve.progress(t, bounce: c.animationBounce) : t)
        if surface {
            content
                .scaleEffect(x: 0.5 + 0.5 * e, y: 0.35 + 0.65 * e, anchor: .bottom)
                .opacity(min(1, t * 4))
        } else {
            content.offset(x: spread.width * (1 - e), y: spread.height * (1 - e))
        }
    }
}

/// `.draw`: window mode's border effect, around the panel.
private struct DrawEntrance: ViewModifier {
    let shown: Bool
    let radius: CGFloat

    private struct State { var draw = 0.0, glass = 0.0, line = 0.0 }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: State(), trigger: shown) { view, v in
            view
                .opacity(v.glass)
                .scaleEffect(0.985 + 0.015 * v.glass, anchor: .bottom)
                .overlay {
                    ZStack {
                        ForEach([false, true], id: \.self) { mirrored in
                            let half = OutlineHalf(radius: radius)
                            ZStack {
                                half.trim(from: 0, to: v.draw)
                                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                half.trim(from: max(0, v.draw - 0.08), to: v.draw)
                                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round)).blur(radius: 7)
                                    .opacity(v.draw >= 1 ? 0 : 1)
                            }
                            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        }
                    }
                    .opacity(v.line)
                    .allowsHitTesting(false)
                }
        } keyframes: { _ in
            KeyframeTrack(\.draw) {
                LinearKeyframe(shown ? 0 : 1, duration: 0.001)
                CubicKeyframe(1, duration: shown ? 0.45 : 0.01)
            }
            KeyframeTrack(\.glass) {
                LinearKeyframe(shown ? 0 : 1, duration: shown ? 0.1 : 0.001)
                CubicKeyframe(shown ? 1 : 0, duration: shown ? 0.38 : 0.16)
            }
            KeyframeTrack(\.line) {
                LinearKeyframe(shown ? 1 : 0, duration: shown ? 0.55 : 0.001)
                CubicKeyframe(0, duration: shown ? 0.5 : 0.01)
            }
        }
    }
}

/// The right half of a rounded rectangle, from top centre round to bottom centre; mirrored for the left.
private struct OutlineHalf: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1), rad = max(0, radius - 1)
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

/// In `.tile` the keys of a KeyHintKeyboard spread from the middle; this carries whether they have arrived.
private struct KeyTileKey: EnvironmentKey { static let defaultValue: Bool? = nil }

extension EnvironmentValues {
    var keyTile: Bool? {
        get { self[KeyTileKey.self] }
        set { self[KeyTileKey.self] = newValue }
    }
}

/// `ouch panelfx <style>` or `ouch panelfx all`: plays the Sort panel then Keyboard Help in each style.
/// Settings' preview plays just Keyboard Help (`keyboardOnly`), which doesn't take the keyboard.
enum PanelMotionDemo {
    private static var work: [DispatchWorkItem] = []

    static func command(_ args: [String]) {
        switch args.first?.lowercased() {
        case "all": play(PanelMotion.allCases)
        case let name? where PanelMotion(rawValue: name) != nil: play([PanelMotion(rawValue: name)!])
        default: Log.info("panelfx: styles are \(PanelMotion.allCases.map(\.rawValue).joined(separator: ", ")), or all")
        }
    }

    static func play(_ styles: [PanelMotion], keyboardOnly: Bool = false) {
        work.forEach { $0.cancel() }
        work = []
        KeyHelp.shared.hide()
        let mode = ShortcutIndex().modeName
        var t = 0.0
        for s in styles {
            if keyboardOnly {
                at(t + 0.3) { PanelMotion.preview = s; KeyHelp.shared.showFromMenu(preferredMode: mode) }
                at(t + 2.2) { KeyHelp.shared.hide() }
                t += 2.6
            } else {
                at(t) { PanelMotion.preview = s; HUD.shared.show(s.title, on: NSScreen.main) }
                at(t + 1.0) { SortPanel.shared.open() }
                at(t + 2.9) { SortPanel.shared.finish() }
                at(t + 3.6) { KeyHelp.shared.showFromMenu(preferredMode: mode) }
                at(t + 5.6) { KeyHelp.shared.hide() }
                t += 6.4
            }
        }
        at(t) { PanelMotion.preview = nil }
    }

    private static func at(_ delay: Double, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        work.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }
}
