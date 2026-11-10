import AppKit
import CatWMKit
import SwiftUI

struct Kbd: View {
    let keys: [String]
    var size: KbdSize = .small
    var pressed = false
    var onAccent = false

    init(keys: [String], size: KbdSize = .small, pressed: Bool = false, onAccent: Bool = false) {
        self.keys = keys; self.size = size; self.pressed = pressed; self.onAccent = onAccent
    }

    var body: some View {
        HStack(spacing: size == .large ? 6 : size == .medium ? Theme.Space.extraSmall : Theme.Space.xxs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in cap(key) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.map { Self.spoken[$0] ?? $0 }.joined(separator: " "))
    }

    private static let spoken = ["⌘": "Command", "⌥": "Option", "⇧": "Shift", "⌃": "Control", "↩": "Return",
                                 "⇥": "Tab", "⎋": "Escape", "⌫": "Delete", "⇪": "Caps Lock", "␣": "Space"]

    @ViewBuilder private func cap(_ key: String) -> some View {
        if size == .small {
            Text(key)
                .font(Theme.keys(11.5, .medium)).oneLine()
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 5)
                .frame(minWidth: Theme.keycapSize, minHeight: Theme.keycapSize)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
                    .fill(Theme.well))
        } else {
            let large = size == .large, wide = key.count > 2
            Text(key)
                .font(Theme.keys(large ? (wide ? 14 : 17) : (wide ? 11.5 : 13), .medium)).oneLine().fixedSize()
                .foregroundStyle(pressed ? Theme.onAccent : onAccent ? Theme.accent : Theme.ink)
                .padding(.horizontal, large ? Theme.Space.medium : Theme.Space.small)
                .frame(minWidth: large ? 40 : 30, minHeight: large ? 40 : 30)
                .background {
                    let shape = RoundedRectangle(cornerRadius: large ? Theme.Radius.medium : Theme.Radius.small,
                                                 style: .continuous)
                    shape.fill(pressed ? Theme.accent : onAccent ? Theme.onAccent : Theme.surfaceRaised)
                }
                .offset(y: pressed ? 2 : 0)
                .animation(Motion.fade, value: pressed)
        }
    }
}

#if DEBUG
extension GalleryExamples {
    static let keys = GalleryExample(order: 7) { AnyView(GalleryContent(model: $0).keys) }
}

extension GalleryContent {
    @ViewBuilder var keys: some View {
        block("Keycaps and tooltips") {
            HStack(alignment: .center, spacing: Theme.Space.extraLarge) {
                Kbd(keys: ["⌘", "K"])
                Kbd(keys: ["⌥", "⇧", "H"])
                Kbd(keys: ["H", "J", "K", "L"], size: .medium)
                Kbd(keys: ["H"], size: .large)
                Kbd(keys: ["L"], size: .large, pressed: true)
                Kbd(keys: ["H"], size: .medium, onAccent: true)
                    .padding(Theme.Space.small)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .fill(Theme.accent))
            }
            tooltipExamples
        }
    }
}
#endif

enum KbdSize { case small, medium, large }
