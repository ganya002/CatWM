import AppKit
import CatWMKit
import SwiftUI

struct EssentialTile: View {
    let title: String
    let label: String
    let symbol: String
    var offSymbol: String?
    var isOn = false
    var toggles = true
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
        let lit = model.hover && enabled
        Button {
            model.count += 1
            action()
        } label: {
            let image = Image(systemName: toggles && !isOn ? offSymbol ?? symbol : symbol)
                .font(Theme.symbol(Theme.Icon.large))
                .contentTransition(.symbolEffect(.replace, options: .speed(2.2)))
            VStack(spacing: 4) {
                Group {
                    if rotates { image.rotateEffect(value: model.count) } else { image }
                }
                .frame(height: 18)
                Text(title).font(Theme.body(11.5, isOn ? .medium : .regular)).oneLine().minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? Theme.onAccent : lit ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(isOn ? Theme.accent : lit ? Theme.wellHover : Theme.well))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { model.hover = $0 }
        .animation(Motion.fadeMedium, value: isOn)
        .accessibilityLabel(label)
        .accessibilityAddTraits(!toggles ? [] : isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var essentialExamples: some View {
        HStack(alignment: .top, spacing: Theme.Space.extraSmall) {
            EssentialTile(title: "Tiling", label: "Tiling", symbol: "rectangle.split.3x1",
                          offSymbol: "rectangle.on.rectangle", isOn: model.essentialOn, shortcut: ["⌥", "T"]) {
                model.essentialOn.toggle()
            }
            EssentialTile(title: "Float", label: "Float window", symbol: "macwindow.on.rectangle",
                          offSymbol: "macwindow", isOn: false, shortcut: ["⌥", "F"]) {}
            EssentialTile(title: "Retile", label: "Retile windows", symbol: "arrow.triangle.2.circlepath",
                          toggles: false, shortcut: ["⌥", "Z"], rotates: true) {}
        }
        .frame(width: Theme.menuWidth)
    }
}
#endif
