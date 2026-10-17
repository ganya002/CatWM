import AppKit
import SwiftUI

enum ButtonVariant { case primary, secondary, ghost, danger, ghostDanger }
enum ButtonSize { case sm, regular, lg }

struct OButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        OButtonBody(configuration: configuration, style: self)
    }

    var height: CGFloat { size == .sm ? 26 : size == .lg ? 36 : Theme.controlHeight }
}

private struct OButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: OButtonStyle
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let s = style
        configuration.label
            .font(Theme.body(s.size == .sm ? 12.5 : s.size == .lg ? 14 : 13, .medium))
            .oneLine()
            .foregroundStyle(ink)
            .padding(.horizontal, s.iconOnly ? 0 : s.size == .sm ? 11 : s.size == .lg ? 18 : 14)
            .frame(width: s.iconOnly ? s.height : nil, height: s.height)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.spring, value: configuration.isPressed)
            .animation(Motion.fade, value: lit)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hover.on = $0 }
    }

    private var lit: Bool { hover.on && enabled }

    private var ink: Color {
        switch style.variant {
        case .primary: Theme.onAccent
        case .secondary: Theme.ink
        case .ghost: lit ? Theme.ink : Theme.inkMuted
        case .danger, .ghostDanger: Theme.danger
        }
    }

    private var fill: Color {
        switch style.variant {
        case .primary: lit ? Theme.accentHover : Theme.accent
        case .secondary: lit ? Theme.wellHover : Theme.well
        case .ghost: lit ? Theme.hover : .clear
        case .danger: Theme.dangerSoft
        case .ghostDanger: lit ? Theme.dangerSoft : .clear
        }
    }
}

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
