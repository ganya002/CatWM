import AppKit
import SwiftUI

struct PresetTile: View {
    let preset: MotionPane.Preset
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(preset.name).font(Theme.body(12.5, selected ? .medium : .regular)).oneLine()
                    .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
                Spacer(minLength: 0)
                CurveGraph(curve: preset.animate ? preset.curve : .linear, bounce: preset.bounce, instant: !preset.animate,
                           lineWidth: 2, color: Theme.accent)
                    .frame(width: 56, height: 28)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(selected ? Theme.accentSoft : hover.on ? Theme.wellHover : Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5).opacity(selected ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.medium), value: selected)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
