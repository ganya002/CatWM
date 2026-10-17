import AppKit
import SwiftUI

struct EssentialTile: View {
    let title: String
    let label: String
    let symbol: String
    var offSymbol: String? = nil
    var isOn: Bool? = nil
    var shortcut: [String] = []
    var rotates = false
    let action: () -> Void
    @StateObject private var model = Model()
    @Environment(\.isEnabled) private var enabled

    final class Model: ObservableObject {
        @Published var hover = false
        @Published var count = 0
    }

    var body: some View {
        let on = isOn == true, lit = model.hover && enabled
        Button {
            model.count += 1
            action()
        } label: {
            let image = Image(systemName: isOn == false ? offSymbol ?? symbol : symbol)
                .font(Theme.symbol(Theme.Icon.lg))
                .contentTransition(.symbolEffect(.replace, options: .speed(2.2)))
            VStack(spacing: 4) {
                Group {
                    if rotates { image.rotateEffect(value: model.count) } else { image }
                }
                .frame(height: 18)
                Text(title).font(Theme.body(11.5, on ? .medium : .regular)).oneLine().minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? Theme.onAccent : lit ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(on ? Theme.accent : lit ? Theme.wellHover : Theme.well))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { model.hover = $0 }
        .animation(Motion.fadeMedium, value: on)
        .tooltip(label, keys: shortcut)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn == nil ? [] : on ? [.isToggle, .isSelected] : .isToggle)
    }
}
