import AppKit
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
        HStack(spacing: size == .large ? 6 : size == .medium ? Theme.Space.xs : Theme.Space.xxs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in cap(k) }
        }
    }

    @ViewBuilder private func cap(_ k: String) -> some View {
        if size == .small {
            Text(k)
                .font(Theme.keys(11.5, .medium)).oneLine()
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 5)
                .frame(minWidth: 20, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).fill(Theme.well))
        } else {
            let large = size == .large, wide = k.count > 2
            Text(k)
                .font(Theme.keys(large ? (wide ? 14 : 17) : (wide ? 11.5 : 13), .medium)).oneLine().fixedSize()
                .foregroundStyle(pressed ? Theme.onAccent : onAccent ? Theme.accent : Theme.ink)
                .padding(.horizontal, large ? Theme.Space.md : Theme.Space.sm)
                .frame(minWidth: large ? 40 : 30, minHeight: large ? 40 : 30)
                .background {
                    let shape = RoundedRectangle(cornerRadius: large ? Theme.Radius.md : Theme.Radius.sm, style: .continuous)
                    if pressed {
                        shape.fill(Theme.accent)
                    } else {
                        shape.fill(onAccent ? Theme.onAccent : Theme.surface)
                            .overlay(alignment: .bottom) {
                                shape.fill(Theme.surfaceSunken).frame(height: large ? 3 : 2)
                                    .mask(shape)
                            }
                            .elevation(.sm, in: shape)
                    }
                }
                .offset(y: pressed ? 2 : 0)
                .animation(Motion.fade, value: pressed)
        }
    }
}
