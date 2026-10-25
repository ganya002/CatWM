import AppKit
import SwiftUI

struct OIconButton: View {
    let symbol: String
    let label: String
    var size: ButtonSize = .small
    var variant: ButtonVariant = .ghost
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.symbol(size == .small ? Theme.Icon.medium : Theme.Icon.large))
        }
        .buttonStyle(OButtonStyle(variant: variant, size: size, iconOnly: true))
        .tooltip(label)
        .accessibilityLabel(label)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var iconButtonExamples: some View {
        HStack(spacing: Theme.Space.medium) {
            OIconButton(symbol: "gearshape", label: "Settings") {}
            OIconButton(symbol: "arrow.triangle.2.circlepath", label: "Retile", size: .regular, variant: .secondary) {}
            OIconButton(symbol: "trash", label: "Remove", variant: .ghostDanger) {}
        }
    }
}
#endif
