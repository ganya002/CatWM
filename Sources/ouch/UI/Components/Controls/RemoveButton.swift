import AppKit
import SwiftUI

struct RemoveButton: View {
    enum Variant { case row, close, restore, badge }
    let help: String
    var variant: Variant = .row
    let action: () -> Void
    @StateObject private var hover = Flag()

    init(help: String, variant: Variant = .row, action: @escaping () -> Void) {
        self.help = help; self.variant = variant; self.action = action
    }

    var body: some View {
        Button(action: action) {
            switch variant {
            case .row:
                Image(systemName: "minus").font(Theme.symbol(10, .bold))
                    .foregroundStyle(hover.on ? Theme.danger : Theme.inkMuted)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(hover.on ? Theme.dangerSoft : Theme.well))
                    .contentShape(Circle())
            case .close, .restore:
                let removes = variant == .close
                Image(systemName: removes ? "xmark" : "arrow.uturn.backward").font(Theme.symbol(10, .semibold))
                    .foregroundStyle(hover.on && removes ? Theme.danger : hover.on ? Theme.ink : Theme.inkMuted)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(hover.on ? (removes ? Theme.dangerSoft : Theme.hover) : .clear))
                    .contentShape(Rectangle())
            case .badge:
                Image(systemName: "xmark").font(Theme.symbol(7, .heavy)).foregroundStyle(Theme.surface)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(hover.on ? Theme.danger : Theme.inkMuted))
                    .contentShape(Circle())
            }
        }
        .buttonStyle(PressScale(scale: 0.88))
        .onHover { hover.on = $0 }
        .animation(Motion.fade, value: hover.on)
        .tooltip(help)
        .accessibilityLabel(help)
    }
}
