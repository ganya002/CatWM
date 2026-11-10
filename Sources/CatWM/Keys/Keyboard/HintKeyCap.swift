import AppKit
import CatWMKit
import MacKeysCore
import MacKeysUI
import SwiftUI

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
    private var width: CGFloat { key.frame.width * scale }
    private var height: CGFloat { key.frame.height * scale }
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
                label(hint).frame(width: width, height: height)
            }
            if let ring = ringColor { outline(ring) }
        }
        .frame(width: width, height: height)
        .opacity(lit || !fades ? 1 : 0.45)
        .offset(y: filled ? scale : 0)
        .scaleEffect(hot && !key.modifier.isEmpty && !reduceMotion ? 0.96 : 1)
        .contentShape(KeyOutline(cap: key.cap))
        .animation(Motion.fade, value: pressed)
        .animation(Motion.fade, value: hint?.label)
        .animation(Motion.fade, value: hot)

        Group {
            if interactive || (tap != nil && !key.modifier.isEmpty) {
                Button { tap?(key) } label: { face }.buttonStyle(.plain)
            } else {
                face
            }
        }
        .onHover { inside in
            hovering.isOn = inside
            hover?(key, inside)
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
            RoundedRectangle(cornerRadius: radius, style: .circular).inset(by: -1.5 * scale)
                .strokeBorder(color, lineWidth: 1)
        }
    }

    @ViewBuilder private var cap: some View {
        if filled {
            KeyOutline(cap: key.cap).fill(groupColor)
        } else {
            ZStack {
                MacKeyCap(key: key.cap, theme: device.theme, scale: scale, legends: !labelled)
                if hovering.isOn && interactive {
                    KeyOutline(cap: key.cap).fill(light ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                        .frame(width: width, height: height)
                }
            }
            .frame(width: width, height: height)
        }
    }

    private func label(_ hint: KeyHint) -> some View {
        let label = hint.label
        let full = key.frame.height >= 50
        let glyph = label.count <= 2
        let numeric = Int(label) != nil
        let ink = filled ? pressedInk : groupColor
        let box = key.isL ? CGSize(width: width, height: CGFloat(device.keyboard.capHeight) * scale)
            : CGSize(width: width, height: height)
        return ZStack(alignment: .topLeading) {
            if full {
                cornerLegend
            }
            Group {
                if glyph {
                    Text(label)
                        .font(numeric ? Theme.body((full ? 20 : 13) * scale) : Theme.keys((full ? 18 : 12) * scale))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: full ? scale : 0)
                } else if full {
                    Text(label).font(Theme.body(12 * scale, .medium))
                        .padding(.horizontal, 3 * scale).padding(.bottom, 8 * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else {
                    Text(label).font(Theme.body(9.5 * scale, .medium))
                        .padding(.horizontal, 3 * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .oneLine().minimumScaleFactor(0.7)
            .foregroundStyle(ink)
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .frame(width: width, height: height, alignment: .topTrailing)
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

struct KeyOutline: Shape {
    let cap: KeyCap

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / CGFloat(cap.w)
        return MacKeyCap.outline(of: cap).applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
