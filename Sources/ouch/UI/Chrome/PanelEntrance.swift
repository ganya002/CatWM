import AppKit
import SwiftUI

struct PanelEntrance: ViewModifier {
    let shown: Bool
    let style: PanelMotion
    var radius: CGFloat = Theme.Radius.extraLarge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(shown ? 1 : 0).animation(.easeOut(duration: Theme.medium), value: shown)
        } else {
            switch style {
            case .tile:
                content.modifier(TileProgress(progress: shown ? 1 : 0, shown: shown, surface: true))
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
        case .pop: (0.82, 0.7)
        case .focus: (1.04, 1.04)
        case .tile, .draw: (1, 1)
        }
    }
}
