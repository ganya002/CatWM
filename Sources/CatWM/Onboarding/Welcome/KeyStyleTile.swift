import AppKit
import CatWMKit
import SwiftUI

struct KeyStyleTile: View {
    let style: KeyStyle
    let selected: Bool
    let action: () -> Void
    @StateObject private var model = Model()

    final class Model: ObservableObject { @Published var hover = false }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                cluster.frame(maxWidth: .infinity).frame(height: 132)
                HStack(spacing: 6) {
                    Text(style.title).font(Theme.heading()).oneLine()
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(Theme.symbol(Theme.Icon.large))
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.top, 12)
                Text(style.caption).textStyle(.caption).oneLine()
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.85) : Theme.inkMuted)
                    .padding(.top, 1)
            }
            .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
            .padding(Theme.Space.medium)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(selected ? Theme.accent : model.hover ? Theme.wellHover : Theme.well))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.97))
        .onHover { model.hover = $0 }
        .animation(Motion.fadeMedium, value: selected)
        .accessibilityLabel("\(style.title): \(style.caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var cluster: some View {
        switch style {
        case .vim:
            HStack(spacing: Theme.Space.extraSmall) { ForEach(["H", "J", "K", "L"], id: \.self) { cap($0) } }
        case .wasd:
            VStack(spacing: Theme.Space.extraSmall) {
                cap("W")
                HStack(spacing: Theme.Space.extraSmall) { ForEach(["A", "S", "D"], id: \.self) { cap($0) } }
            }
        }
    }

    private func cap(_ key: String) -> some View {
        Kbd(keys: [key], size: .medium, onAccent: selected)
    }
}

enum KeyStyle: String, CaseIterable {
    case vim, wasd

    var configID: String { ConfigLibrary.builtInPrefix + (self == .vim ? "keyboard.default" : "keyboard.wasd") }
    var title: String { self == .vim ? "Vim" : "WASD" }
    var caption: String { self == .vim ? "Right hand on the home row" : "Left hand, like a game" }

    static var current: KeyStyle? {
        let id = SettingsWindow.shared.library.current(.keyboard).id
        return allCases.first { $0.configID == id }
    }
}
