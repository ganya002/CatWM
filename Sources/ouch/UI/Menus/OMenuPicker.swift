import AppKit
import SwiftUI

struct OMenuPicker<T: Hashable>: View {
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let options = options, binding = $selection, lit = hover.on && enabled
        OMenuButton(items: {
            options.enumerated().map { n, o in
                MenuItem(id: "\(n)", kind: .radio, label: o.label, checked: o.value == binding.wrappedValue,
                         action: { binding.wrappedValue = o.value })
            }
        }) {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.label ?? "").font(Theme.body(13)).oneLine()
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.xs, .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).frame(height: Theme.controlHeight)
            .background(Capsule().fill(lit ? Theme.wellHover : Theme.well))
            .contentShape(Capsule())
        }
        .fixedSize()
        .onHover { hover.on = $0 }
        .animation(Motion.fade, value: lit)
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var menuPickerExample: some View {
        OMenuPicker(title: "Curve", options: ["Ease", "Spring", "Off"].map { ($0, $0) }, selection: $m.segment)
    }
}
#endif
