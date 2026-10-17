import AppKit
import SwiftUI
import MacKeysCore
import MacKeysUI

struct HintKeyCap: View {
    let key: KeyHintKeyboard.Key
    let device: MacDevice
    let scale: CGFloat
    let hint: KeyHint?
    let pressed: Bool
    let hot: Bool
    let tap: ((KeyHintKeyboard.Key) -> Void)?
    let hover: ((KeyHintKeyboard.Key, Bool) -> Void)?
    var fades = true
    @StateObject private var hovering = Flag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var interactive: Bool { tap != nil && key.code != nil }
    private var light: Bool { device.keyboard.lightKeys }
    private var w: CGFloat { key.frame.width * scale }
    private var h: CGFloat { key.frame.height * scale }
    private var radius: CGFloat { CGFloat(key.cap.radius) * scale }

    private var groupColor: Color { hint?.group.color(onDarkKeys: !light) ?? legendColor }
    private var legendColor: Color { Color(mk: device.theme.legend) }
    private var pressedInk: Color { light ? .white : Theme.rgb(0x0B0B0D) }
    private var filled: Bool { pressed && hint != nil }
    private var labelled: Bool { hint != nil }

    var body: some View {
        let lit = hint != nil || hot || pressed
        let face = ZStack(alignment: .topLeading) {
            cap
            if let hint, labelled {
                label(hint).frame(width: w, height: h)
            }
            if let ring = ringColor { outline(ring) }
        }
        .frame(width: w, height: h)
        .opacity(lit || !fades ? 1 : 0.45)
        .offset(y: filled ? scale : 0)
        .scaleEffect(hot && !key.modifier.isEmpty && !reduceMotion ? 0.96 : 1)
        .contentShape(KeyOutline(cap: key.cap))
        .animation(.easeOut(duration: Theme.fast), value: pressed)
        .animation(.easeOut(duration: 0.15), value: hint?.label)
        .animation(.easeOut(duration: Theme.fast), value: hot)

        Group {
            if interactive || (tap != nil && !key.modifier.isEmpty) {
                Button { tap?(key) } label: { face }.buttonStyle(.plain)
            } else {
                face
            }
        }
        .onHover { on in
            hovering.on = on
            hover?(key, on)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHidden(!lit && tap == nil)
    }

    private var accessibilityText: String {
        let name = KeyHintKeyboard.legend(key)
        if !key.modifier.isEmpty { return "\(name) modifier" }
        guard let hint else { return "\(name), no shortcut" }
        return "\(name): \(hint.title)"
    }

    private var ringColor: Color? {
        if filled { return nil }
        if hot { return light ? legendColor.opacity(0.85) : Theme.rgb(0xF5F5F7, 0.85) }
        return hint != nil ? groupColor : nil
    }

    @ViewBuilder private func outline(_ color: Color) -> some View {
        if key.isL {
            KeyOutline(cap: key.cap).stroke(color, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .circular).inset(by: -1.5 * scale).strokeBorder(color, lineWidth: 1)
        }
    }

    @ViewBuilder private var cap: some View {
        if filled {
            KeyOutline(cap: key.cap).fill(groupColor)
        } else {
            ZStack {
                MacKeyCap(key: key.cap, theme: device.theme, scale: scale, legends: !labelled)
                if hovering.on && interactive {
                    KeyOutline(cap: key.cap).fill(light ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                        .frame(width: w, height: h)
                }
            }
            .frame(width: w, height: h)
        }
    }

    private func label(_ hint: KeyHint) -> some View {
        let k = scale
        let label = hint.label
        let full = key.frame.height >= 50
        let glyph = label.count <= 2
        let numeric = Int(label) != nil
        let ink = filled ? pressedInk : groupColor
        let box = key.isL ? CGSize(width: w, height: CGFloat(device.keyboard.capHeight) * k) : CGSize(width: w, height: h)
        return ZStack(alignment: .topLeading) {
            if full {
                cornerLegend
            }
            Group {
                if glyph {
                    Text(label).font(numeric ? Theme.body((full ? 20 : 13) * k) : Theme.keys((full ? 18 : 12) * k))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: full ? k : 0)
                } else if full {
                    Text(label).font(Theme.body(12 * k, .medium))
                        .padding(.horizontal, 3 * k).padding(.bottom, 8 * k)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else {
                    Text(label).font(Theme.body(9.5 * k, .medium))
                        .padding(.horizontal, 3 * k)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .oneLine().minimumScaleFactor(0.7)
            .foregroundStyle(ink)
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .frame(width: w, height: h, alignment: .topTrailing)
    }

    @ViewBuilder private var cornerLegend: some View {
        let text = cornerText
        if !text.isEmpty {
            Text(text).font(.system(size: 10.5 * scale)).oneLine().fixedSize()
                .foregroundStyle(filled ? pressedInk : legendColor.opacity(0.55))
                .padding(.leading, 7 * scale).padding(.top, (7 - 1) * scale)
        }
    }

    private var cornerText: String {
        switch key.cap.kind {
        case .arrow, .space, .touchid: ""
        default: KeyHintKeyboard.legend(key)
        }
    }
}
