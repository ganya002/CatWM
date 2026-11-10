import AppKit
import CatWMKit
import SwiftUI

struct RemoveButton: View {
    enum Variant { case row, close, restore, badge }
    let help: String
    var variant: Variant = .row
    var tooltip = false
    let action: () -> Void
    @StateObject private var hover = Flag()

    init(help: String, variant: Variant = .row, tooltip: Bool = false, action: @escaping () -> Void) {
        self.help = help; self.variant = variant; self.tooltip = tooltip; self.action = action
    }

    var body: some View {
        Button(action: action) {
            switch variant {
            case .row:
                Image(systemName: "minus").font(Theme.symbol(10, .bold))
                    .foregroundStyle(hover.isOn ? Theme.danger : Theme.inkMuted)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(hover.isOn ? Theme.dangerSoft : Theme.well))
                    .contentShape(Circle())
            case .close, .restore:
                let removes = variant == .close
                Image(systemName: removes ? "xmark" : "arrow.uturn.backward").font(Theme.symbol(10, .semibold))
                    .foregroundStyle(hover.isOn && removes ? Theme.danger : hover.isOn ? Theme.ink : Theme.inkMuted)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(hover.isOn ? (removes ? Theme.dangerSoft : Theme.hover) : .clear))
                    .contentShape(Rectangle())
            case .badge:
                Image(systemName: "xmark").font(Theme.symbol(7, .heavy)).foregroundStyle(Theme.surface)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(hover.isOn ? Theme.danger : Theme.inkMuted))
                    .contentShape(Circle())
            }
        }
        .buttonStyle(PressScale(scale: 0.88))
        .onHover { hover.isOn = $0 }
        .animation(Motion.fade, value: hover.isOn)
        .tooltip(tooltip ? help : "")
        .accessibilityLabel(help)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var removeExamples: some View {
        RemoveButton(help: "Remove row", variant: .row) {}
        RemoveButton(help: "Close", variant: .close) {}
        RemoveButton(help: "Restore", variant: .restore) {}
        RemoveButton(help: "Remove badge", variant: .badge) {}
    }
}
#endif
