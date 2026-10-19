import AppKit
import SwiftUI

struct SortLayoutPill: View {
    let layout: Layout
    let next: () -> Void
    let previous: () -> Void
    @StateObject private var hover = Flag()
    private let help = "Click for next layout, right-click for previous"

    var body: some View {
        Button(action: next) {
            HStack(spacing: 6) {
                SortLayoutGlyph(layout: layout).frame(width: 16, height: 14)
                Text(layout == .bsp ? "BSP" : layout.title).textStyle(.caption).oneLine()
            }
            .foregroundStyle(hover.isOn ? Theme.ink : Theme.inkMuted)
            .padding(.leading, 7).padding(.trailing, 10).frame(height: 24)
            .background(Capsule().fill(hover.isOn ? Theme.wellHover : Theme.well))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(SortRightClick(action: previous))
        .onHover { hover.isOn = $0 }
        .animation(Motion.fade, value: hover.isOn)
        .tooltip(help)
        .accessibilityLabel("Layout: \(layout.title)")
        .accessibilityAction(named: "Previous layout", previous)
    }
}
