import AppKit
import SwiftUI

struct TileItem: ViewModifier {
    let shown: Bool
    let style: PanelMotion
    let spread: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if style == .tile && !reduceMotion {
            content.modifier(TileProgress(progress: shown ? 1 : 0, shown: shown, surface: false, spread: spread))
                .animation(style.animation(in: shown), value: shown)
        } else {
            content
        }
    }
}
