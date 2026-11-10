import AppKit
import CatWMKit
import SwiftUI

struct OMenuPicker<T: Hashable>: View {
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let options = options, binding = $selection, lit = hover.isOn && enabled
        OMenuButton(items: {
            options.enumerated().map { index, option in
                MenuItem(id: "\(index)", kind: .radio, label: option.label,
                         checked: option.value == binding.wrappedValue,
                         action: { binding.wrappedValue = option.value })
            }
        }, label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.label ?? "").font(Theme.body(13.5, .medium)).oneLine()
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.extraSmall, .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 12).padding(.trailing, 8).frame(height: Theme.controlHeight)
            .background(Capsule().fill(lit ? Theme.well : .clear))
            .overlay(Capsule().strokeBorder(Theme.borderControl, lineWidth: 1))
            .contentShape(Capsule())
        })
        .fixedSize()
        .onHover { hover.isOn = $0 }
        .animation(Motion.fade, value: lit)
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var menuPickerExample: some View {
        OMenuPicker(title: "Curve", options: ["Ease", "Spring", "Off"].map { ($0, $0) }, selection: $model.segment)
    }
}
#endif
