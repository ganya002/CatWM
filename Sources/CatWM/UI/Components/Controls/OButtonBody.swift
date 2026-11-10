import AppKit
import CatWMKit
import SwiftUI

struct OButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: OButtonStyle
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Theme.body(style.size == .small ? 12 : 13.5, .medium))
            .oneLine()
            .foregroundStyle(ink)
            .padding(.horizontal, style.iconOnly ? 0 : style.size == .small ? 11 : style.size == .large ? 18 : 14)
            .frame(width: style.iconOnly ? style.height : nil, height: style.height)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(reduceMotion ? Motion.fade : Motion.spring, value: configuration.isPressed)
            .animation(Motion.fade, value: lit)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hover.isOn = $0 }
    }

    private var lit: Bool { hover.isOn && enabled }

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
