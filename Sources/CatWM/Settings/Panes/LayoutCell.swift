import AppKit
import CatWMKit
import SwiftUI

struct LayoutCell: View {
    let layout: Layout
    let active: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            LayoutThumbnail(layout: layout, selected: active)
                .squish(on: active, when: active)
                .scaleEffect(hover.isOn ? 1.06 : 1)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(active ? Theme.accentSoft : hover.isOn ? Theme.wellHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .animation(Motion.spring, value: hover.isOn)
        .accessibilityLabel("\(layout.title), \(active ? "in the cycle" : "not in the cycle")")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct ScreenThumbnail: View {
    let layout: Layout

    var body: some View {
        VStack(spacing: 2) {
            LayoutThumbnail(layout: layout, selected: true)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
                    .fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
                    .strokeBorder(Theme.borderControl, lineWidth: 1.5))
            Capsule().fill(Theme.borderControl).frame(width: 14, height: 2.5)
        }
    }
}
