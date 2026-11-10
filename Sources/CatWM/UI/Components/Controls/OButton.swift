import AppKit
import CatWMKit
import SwiftUI

struct OButton: View {
    let title: String
    var icon: String?
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
                if let icon {
                    Image(systemName: icon).font(Theme.symbol(size == .small ? Theme.Icon.small : Theme.Icon.medium))
                }
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
    static let buttons = GalleryExample(order: 3) { AnyView(GalleryContent(model: $0).buttons) }
}

extension GalleryContent {
    @ViewBuilder var buttons: some View {
        block("Buttons") {
            let variants: [(String, ButtonVariant)] = [
                ("Primary", .primary), ("Secondary", .secondary), ("Ghost", .ghost),
                ("Danger", .danger), ("Ghost danger", .ghostDanger)
            ]
            ForEach([ButtonSize.large, .regular, .small], id: \.self) { size in
                VStack(alignment: .leading, spacing: Theme.Space.small) {
                    HStack(spacing: Theme.Space.medium) {
                        ForEach(variants, id: \.0) { name, variant in
                            OButton(name, variant: variant, size: size) {}
                        }
                    }
                    HStack(spacing: Theme.Space.medium) {
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

enum ButtonSize { case small, regular, large }

enum ButtonVariant { case primary, secondary, ghost, danger, ghostDanger }

struct OButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        OButtonBody(configuration: configuration, style: self)
    }

    var height: CGFloat { size == .small ? 26 : size == .large ? 36 : Theme.controlHeight }
}

struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.spring, value: configuration.isPressed)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var pressScaleExample: some View {
        Button {} label: { Text("Press scale").padding(Theme.Space.medium).background(Capsule().fill(Theme.well)) }
            .buttonStyle(PressScale())
    }
}
#endif

struct OIconButton: View {
    let symbol: String
    let label: String
    var size: ButtonSize = .small
    var variant: ButtonVariant = .ghost
    var tip = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.symbol(size == .small ? Theme.Icon.medium : Theme.Icon.large))
        }
        .buttonStyle(OButtonStyle(variant: variant, size: size, iconOnly: true))
        .tooltip(tip ? label : "")
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
