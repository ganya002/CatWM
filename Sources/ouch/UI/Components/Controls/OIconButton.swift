import AppKit
import SwiftUI

struct OIconButton: View {
    let symbol: String
    let label: String
    var size: ButtonSize = .sm
    var variant: ButtonVariant = .ghost
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.symbol(size == .sm ? Theme.Icon.md : Theme.Icon.lg))
        }
        .buttonStyle(OButtonStyle(variant: variant, size: size, iconOnly: true))
        .tooltip(label)
        .accessibilityLabel(label)
    }
}
