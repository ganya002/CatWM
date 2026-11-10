import AppKit
import CatWMKit
import SwiftUI

struct PanelEntrance: ViewModifier {
    let shown: Bool
    let style: PanelMotion
    var radius: CGFloat = Theme.Radius.extraLarge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(shown ? 1 : 0).animation(Motion.fadeMedium, value: shown)
        } else {
            switch style {
            case .tile:
                content.modifier(TileProgress(progress: shown ? 1 : 0, shown: shown, surface: true))
                    .animation(Motion.panel(style, in: shown), value: shown)
            case .draw:
                content.modifier(DrawEntrance(shown: shown, radius: radius))
            default:
                content
                    .opacity(shown ? 1 : 0)
                    .blur(radius: style == .focus && !shown ? 14 : 0)
                    .scaleEffect(x: shown ? 1 : scale.x, y: shown ? 1 : scale.y, anchor: .bottom)
                    .offset(y: shown ? 0 : lift)
                    .animation(Motion.panel(style, in: shown), value: shown)
            }
        }
    }

    private var lift: CGFloat { style == .rise ? 22 : style == .pop ? 14 : 0 }

    private var scale: (x: CGFloat, y: CGFloat) {
        switch style {
        case .rise: (0.985, 0.985)
        case .pop: (0.82, 0.7)
        case .focus: (1.04, 1.04)
        case .tile, .draw: (1, 1)
        }
    }
}

extension View {
    func panelEntrance(_ shown: Bool, style: PanelMotion, radius: CGFloat = Theme.Radius.extraLarge) -> some View {
        modifier(PanelEntrance(shown: shown, style: style, radius: radius))
    }

    func tileItem(_ shown: Bool, style: PanelMotion, spread: CGSize) -> some View {
        modifier(TileItem(shown: shown, style: style, spread: spread))
    }
}

struct TileItem: ViewModifier {
    let shown: Bool
    let style: PanelMotion
    let spread: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if style == .tile && !reduceMotion {
            content.modifier(TileProgress(progress: shown ? 1 : 0, shown: shown, surface: false, spread: spread))
                .animation(Motion.panel(style, in: shown), value: shown)
        } else {
            content
        }
    }
}

struct TileProgress: ViewModifier, Animatable {
    var progress: Double
    let shown: Bool
    let surface: Bool
    var spread: CGSize = .zero

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let config = WindowManager.shared.config
        let eased = CGFloat(shown ? config.animationCurve.progress(progress, bounce: config.animationBounce) : progress)
        if surface {
            content
                .scaleEffect(x: 0.5 + 0.5 * eased, y: 0.35 + 0.65 * eased, anchor: .bottom)
                .opacity(min(1, progress * 4))
        } else {
            content.offset(x: spread.width * (1 - eased), y: spread.height * (1 - eased))
        }
    }
}

enum KeyTile: Equatable {
    case rise
    case tile(shown: Bool)

    var shown: Bool {
        switch self {
        case .rise: true
        case let .tile(shown): shown
        }
    }

    var style: PanelMotion { self == .rise ? .rise : .tile }
}

struct KeyTileKey: EnvironmentKey { static let defaultValue = KeyTile.rise }

extension EnvironmentValues {
    var keyTile: KeyTile {
        get { self[KeyTileKey.self] }
        set { self[KeyTileKey.self] = newValue }
    }
}
