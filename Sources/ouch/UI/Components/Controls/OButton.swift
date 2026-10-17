import AppKit
import SwiftUI

struct OButton: View {
    let title: String
    var icon: String? = nil
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var shortcut: [String] = []
    let action: () -> Void

    init(_ title: String, icon: String? = nil, variant: ButtonVariant = .secondary, size: ButtonSize = .regular,
         shortcut: [String] = [], action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.variant = variant; self.size = size
        self.shortcut = shortcut; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(Theme.symbol(size == .sm ? Theme.Icon.sm : Theme.Icon.md)) }
                Text(title)
                if !shortcut.isEmpty {
                    Text(shortcut.joined()).font(Theme.keys(12, .medium)).opacity(0.8).padding(.trailing, -4)
                }
            }
        }
        .buttonStyle(OButtonStyle(variant: variant, size: size))
    }
}

#if DEBUG
extension GalleryExamples {
    static let buttons = GalleryExample(order: 3) { AnyView(GalleryContent(m: $0).buttons) }
}

extension GalleryContent {
    @ViewBuilder var buttons: some View {
        block("Buttons") {
            let variants: [(String, ButtonVariant)] = [("Primary", .primary), ("Secondary", .secondary), ("Ghost", .ghost),
                                                      ("Danger", .danger), ("Ghost danger", .ghostDanger)]
            ForEach([ButtonSize.lg, .regular, .sm], id: \.self) { size in
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.md) {
                        ForEach(variants, id: \.0) { name, variant in
                            OButton(name, variant: variant, size: size) {}
                        }
                    }
                    HStack(spacing: Theme.Space.md) {
                        OButton("With icon", icon: "arrow.triangle.2.circlepath", size: size) {}
                        OButton("Continue", variant: .primary, size: size, shortcut: ["↩"]) {}
                        OButton("Disabled", size: size) {}.disabled(true)
                    }
                }
                .fixedSize()
            }
            iconButtonExamples
        }
    }
}
#endif
