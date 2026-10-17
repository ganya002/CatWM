import AppKit
import SwiftUI

struct OButtonBody: View {
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
