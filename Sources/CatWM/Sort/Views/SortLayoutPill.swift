import AppKit
import SwiftUI

struct SortLayoutPill: View {
    let layout: Layout
    let next: () -> Void
    let previous: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: next) {
            HStack(spacing: 6) {
                SortLayoutGlyph(layout: layout).frame(width: 16, height: 14)
                Text(layout == .bsp ? "BSP" : layout.title).textStyle(.caption).oneLine()
            }
            .foregroundStyle(hover.isOn ? Theme.ink : Theme.inkMuted)
            .padding(.leading, Theme.Space.small).padding(.trailing, Theme.Space.medium)
            .frame(height: Theme.controlHeight)
            .background(Capsule().fill(hover.isOn ? Theme.well : .clear))
            .overlay(Capsule().strokeBorder(Theme.borderControl, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(SortRightClick(action: previous))
        .onHover { hover.isOn = $0 }
        .animation(Motion.fade, value: hover.isOn)
        .accessibilityLabel("Layout: \(layout.title)")
        .accessibilityAction(named: "Previous layout", previous)
    }
}
