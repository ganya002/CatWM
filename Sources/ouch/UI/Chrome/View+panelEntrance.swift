import AppKit
import SwiftUI

extension View {
    func panelEntrance(_ shown: Bool, style: PanelMotion, radius: CGFloat = Theme.Radius.xl) -> some View {
        modifier(PanelEntrance(shown: shown, style: style, radius: radius))
    }

    func tileItem(_ shown: Bool, style: PanelMotion, spread: CGSize) -> some View {
        modifier(TileItem(shown: shown, style: style, spread: spread))
    }
}
