import AppKit
import SwiftUI

struct LayoutCell: View {
    let layout: Layout
    let on: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            LayoutThumbnail(layout: layout, selected: on)
                .squish(on: on, when: on)
                .scaleEffect(hover.on ? 1.06 : 1)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(on ? Theme.accentSoft : hover.on ? Theme.wellHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .animation(Motion.spring, value: hover.on)
        .accessibilityLabel("\(layout.title), \(on ? "in the cycle" : "not in the cycle")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
