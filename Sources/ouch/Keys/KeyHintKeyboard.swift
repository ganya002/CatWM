// Keys: the drawn Mac keyboard with binds written on its keys (used by Shortcut Map and Key Help).
import AppKit
import SwiftUI
import MacKeysCore
import MacKeysUI

// This Mac's keyboard, drawn by the MacKeys SDK (see `MacKeyboard`: model, finish, ANSI/ISO/JIS and the
// layout of the input source in use), with one layer of binds written on its keys, coloured by group.
// The Shortcut Map and the keyboard help overlay both use it.
//
//     KeyHintKeyboard(binds: [KeyHint], pressed: UInt16?, hot: Set<UInt16>, scale: 1)
//         .onKeyTap { key in … }                  optional; keys become buttons
//         .onKeyHover { key, inside in … }        optional
//
// - `binds`: one layer (one mode, one set of modifiers). `KeyHint(_:)` builds them from a
//   `ConfigDocument.KeyAction` or a running `KeyBinding`.
// - Each bound key shows its action on the cap, in the colour of its group.
// - `pressed`: a key filled with its group colour. `hot`: keys with a ring that never recede; pass
//   held modifiers here (modifier keys carry their key codes, e.g. 55 for ⌘).
// - `scale`: 1 draws the deck at the SDK's natural size, a 1u key 58pt. `size(scale:)` is the view's size,
//   `rect(of:scale:)` a key's frame inside it, for popovers and tooltips placed over a key, and
//   `keycap(_:hint:scale:)` one key on its own.

/// What a key does on the current layer.
struct KeyHint: Identifiable, Equatable {
    let code: UInt16
    let dispatcher: String
    let arg: String
    /// Full description, e.g. "Focus Right".
    let title: String
    var id: UInt16 { code }

    var group: KeyGroup { KeyGroup(dispatcher: dispatcher, arg: arg) }
    /// Short text for the keycap: an arrow, a workspace number or a word or two.
    var label: String { Self.label(dispatcher: dispatcher, arg: arg) }

    init(code: UInt16, dispatcher: String, arg: String, title: String) {
        self.code = code
        self.dispatcher = dispatcher
        self.arg = arg
        self.title = title
    }
    init(_ a: ConfigDocument.KeyAction) {
        self.init(code: a.code, dispatcher: a.row.dispatcher, arg: a.arg, title: a.title)
    }
    init(_ b: KeyBinding) {
        let match = Actions.match(BindRow(mods: "", key: "", dispatcher: b.dispatcher, args: b.arg))
        let title = b.dispatcher == "exec" ? (b.arg.isEmpty ? "Run Command" : "Run “\(b.arg)”")
            : match?.title ?? "\(b.dispatcher) \(b.arg)".trimmingCharacters(in: .whitespaces)
        self.init(code: b.keyCode, dispatcher: b.dispatcher, arg: b.arg, title: title)
    }

    /// Hyprland's aliases folded into the dispatchers below.
    fileprivate static func normalized(_ dispatcher: String, _ arg: String) -> (d: String, a: String) {
        var d = dispatcher.lowercased(), a = arg.trimmingCharacters(in: .whitespaces).lowercased()
        if d == "swapwindow" { d = "movewindow" }
        if d == "movewindowtomonitor" { d = "movewindow"; a = "mon:" + a }
        if d == "setlayout" { d = "layout" }
        if d == "layoutmsg" {
            switch a {
            case "cyclenext": d = "cyclenext"; a = ""
            case "cycleprev": d = "cyclenext"; a = "prev"
            case "swapnext": d = "swapnext"; a = ""
            case "swapprev": d = "swapnext"; a = "prev"
            case "orientationnext": d = "cyclelayout"; a = "next"
            case "orientationprev": d = "cyclelayout"; a = "prev"
            default: if a.hasPrefix("mfact") { d = "splitratio"; a = String(a.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            }
        }
        return (d, a)
    }

    static func label(dispatcher: String, arg: String) -> String {
        let (d, a) = normalized(dispatcher, arg)
        let arrows = ["l": "←", "r": "→", "u": "↑", "d": "↓", "left": "←", "right": "→", "up": "↑", "down": "↓"]
        let back = a.hasPrefix("prev") || a.hasPrefix("-") || a.hasPrefix("e-")
        func screen(_ s: String) -> String {
            if let arrow = arrows[s] { return "Screen \(arrow)" }
            return s.hasPrefix("-") ? "‹ Screen" : "Screen ›"
        }
        switch d {
        case "movefocus": return arrows[a] ?? "Focus"
        case "movewindow": return a.hasPrefix("mon:") ? screen(String(a.dropFirst(4))) : arrows[a] ?? "Move"
        case "focusmonitor": return screen(a)
        case "cyclenext": return back ? "‹ Cycle" : "Cycle"
        case "swapnext": return back ? "‹ Swap" : "Swap ›"
        case "workspace", "movetoworkspace", "movetoworkspacesilent":
            if let n = Int(a) { return "\(n)" }
            if a == "previous" { return "Back" }
            return back ? "‹ Prev" : "Next ›"
        case "cyclelayout": return back ? "‹ Layout" : "Layout ›"
        case "layout": return Layout(rawValue: a)?.title ?? a.capitalized
        case "splitratio": return a.hasPrefix("-") ? "Main −" : "Main +"
        case "layoutmsg":
            switch a {
            case "swapwithmaster": return "Swap"
            case "focusmaster": return "Main"
            case "addmaster": return "Mains +"
            case "removemaster": return "Mains −"
            default: return "Layout"
            }
        case "fullscreen": return "Full"
        case "nativefullscreen": return "Max"
        case "togglefloating": return "Float"
        case "retile", "reevaluate": return "Retile"
        case "toggletiling": return "Tiling"
        case "toggledim": return "Dim"
        case "toggleblur": return "Blur"
        case "reload": return "Reload"
        case "killactive": return "Close"
        case "exec": return "Run"
        case "exit": return "Quit"
        case "sethomespace": return "Home"
        case "submap": return a == "reset" ? "Exit" : a.capitalized
        default:
            // Something we don't know: the dispatcher without its verb prefix, cut short.
            var name = Substring(d)
            for prefix in ["toggle", "move", "focus", "set"] where name.hasPrefix(prefix) && name.count > prefix.count {
                name = name.dropFirst(prefix.count)
                break
            }
            return String(name.prefix(7)).capitalized
        }
    }
}

/// The colour groups on the keyboard, in legend order.
enum KeyGroup: CaseIterable, Identifiable {
    case navigation, spaces, layout, window, leave
    var id: Self { self }

    init(dispatcher: String, arg: String) {
        let (d, a) = KeyHint.normalized(dispatcher, arg)
        switch d {
        case "movewindow": self = a.hasPrefix("mon:") ? .spaces : .navigation
        case "movefocus", "cyclenext", "swapnext": self = .navigation
        case "workspace", "movetoworkspace", "movetoworkspacesilent", "focusmonitor", "sethomespace": self = .spaces
        case "cyclelayout", "splitratio", "layoutmsg", "layout": self = .layout
        case "submap" where a == "reset": self = .leave
        default: self = .window
        }
    }

    var title: String {
        switch self {
        case .navigation: "Navigation"
        case .spaces: "Workspaces & displays"
        case .layout: "Layout"
        case .window: "Window"
        case .leave: "Leave mode"
        }
    }

    var color: Color {
        switch self {
        case .navigation: Theme.accent
        case .spaces: Theme.accentInk
        case .layout: Theme.inkMuted
        case .window: Theme.ink
        case .leave: Theme.inkFaint
        }
    }

    /// The colour on the keycaps, which keep their own light or dark whatever the appearance.
    func color(onDarkKeys dark: Bool) -> Color {
        switch self {
        case .navigation: Theme.fixed(\.accent, dark: dark)
        case .spaces: Theme.fixed(\.accentInk, dark: dark)
        case .layout: Theme.fixed(\.inkMuted, dark: dark)
        case .window: Theme.fixed(\.ink, dark: dark)
        case .leave: Theme.fixed(\.inkFaint, dark: dark)
        }
    }
}

// MARK: - Keyboard

struct KeyHintKeyboard: View {
    let binds: [KeyHint]
    var pressed: UInt16?
    var hot: Set<UInt16>
    var scale: CGFloat
    private var tap: ((Key) -> Void)?
    private var hover: ((Key, Bool) -> Void)?
    @ObservedObject private var mac = MacKeyboard.shared
    @Environment(\.keyTile) private var tile

    init(binds: [KeyHint], pressed: UInt16? = nil, hot: Set<UInt16> = [], scale: CGFloat = 1) {
        self.binds = binds
        self.pressed = pressed
        self.hot = hot
        self.scale = scale
    }

    /// Makes the keys buttons.
    func onKeyTap(_ action: @escaping (Key) -> Void) -> Self { var c = self; c.tap = action; return c }
    /// Called with `true` as the pointer enters a key and `false` as it leaves.
    func onKeyHover(_ action: @escaping (Key, Bool) -> Void) -> Self { var c = self; c.hover = action; return c }

    var body: some View {
        let bound = Dictionary(binds.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let size = Self.size(scale: scale)
        let deck = mac.deckLayout.deck
        ZStack(alignment: .topLeading) {
            // The SDK draws the deck with room around it for shadows; the view's size is the deck's.
            MacKeyboardDeckView(device: mac.device, scale: scale)
                .offset(x: -deck.minX * scale, y: -deck.minY * scale)
            ForEach(mac.keys) { k in
                let r = Self.rect(of: k, scale: scale)
                HintKeyCap(key: k, device: mac.device, scale: scale,
                           hint: k.code.flatMap { bound[$0] }, pressed: k.code != nil && k.code == pressed,
                           hot: k.code.map(hot.contains) ?? false, tap: tap, hover: hover)
                    .frame(width: r.width, height: r.height)
                    .tileItem(tile ?? true, style: tile == nil ? .rise : .tile,
                              spread: CGSize(width: (size.width / 2 - r.midX) * 0.35, height: (size.height / 2 - r.midY) * 0.35))
                    .offset(x: r.minX, y: r.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// One key on its own, as it looks on the keyboard: for the head of a popover about that key.
    static func keycap(_ k: Key, hint: KeyHint?, scale: CGFloat) -> some View {
        HintKeyCap(key: k, device: MacKeyboard.shared.device, scale: scale, hint: hint,
                   pressed: false, hot: false, tap: nil, hover: nil, fades: false)
            .frame(width: k.frame.width * scale, height: k.frame.height * scale)
    }

    // MARK: Geometry

    /// The deck's size in points at `scale`.
    static func size(scale: CGFloat) -> CGSize {
        let deck = MacKeyboard.shared.deckLayout.deck
        return CGSize(width: deck.width * scale, height: deck.height * scale)
    }

    /// A key's cap inside the view. The ISO return key's is the box around its L.
    static func rect(of k: Key, scale: CGFloat) -> CGRect {
        CGRect(x: k.frame.minX * scale, y: k.frame.minY * scale, width: k.frame.width * scale, height: k.frame.height * scale)
    }

    /// The corner radius of a full-size key.
    static func cornerRadius(scale: CGFloat) -> CGFloat { 5 * scale }

    /// One key: its MacKeys cap, and where it sits in points at scale 1 from the deck's top-left.
    struct Key: Identifiable {
        let cap: KeyCap
        /// The macOS key code, nil for fn and Touch ID.
        let code: UInt16?
        let frame: CGRect
        /// Set on ⌃ ⌥ ⇧ ⌘.
        let modifier: NSEvent.ModifierFlags
        var id: String { cap.id }
        /// The ISO and JIS return key: wide on top, narrower below.
        var isL: Bool { cap.iso != nil }

        init(_ cap: KeyCap, layout: MacDeckLayout) {
            self.cap = cap
            code = Self.codes[cap.id]
            frame = layout.frame(of: cap).offsetBy(dx: -layout.deck.minX, dy: -layout.deck.minY)
            switch cap.id {
            case "ShiftLeft", "ShiftRight": modifier = .shift
            case "ControlLeft", "ControlRight": modifier = .control
            case "AltLeft", "AltRight": modifier = .option
            case "MetaLeft", "MetaRight": modifier = .command
            default: modifier = []
            }
        }

        /// macOS key codes by MacKeys key id.
        private static let codes: [String: UInt16] = {
            var out: [String: UInt16] = [:]
            for (code, id) in MacKeyCodes.table where id != "Fn" { out[id] = code }
            return out
        }()
    }

    static var keys: [Key] { MacKeyboard.shared.keys }

    /// The key with this code; for modifiers, the left one.
    static func key(for code: UInt16) -> Key? { keys.first { $0.code == code } }

    // MARK: Legends

    /// A key's name as printed in hints and tooltips, e.g. "Å", "F5", "⇥", "⌘".
    static func legend(_ k: Key) -> String {
        switch k.cap.kind {
        case .char, .dual, .quad, .jis, .kana:
            let slots = k.cap.legends
            return (slots.first { $0.slot == .b } ?? slots.first)?.text ?? k.cap.label
        case .space: return "Space"
        case .touchid: return "Touch ID"
        case .fn: return "fn"
        case .fkey: return k.cap.label
        case .mod:
            if k.modifier.contains(.shift) { return "⇧" }
            if k.modifier.contains(.control) { return "⌃" }
            if k.modifier.contains(.option) { return "⌥" }
            return "⌘"
        case .word, .icon, .arrow:
            let named = k.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel)
            return named ?? k.cap.legends.first?.text ?? k.cap.label
        }
    }
}

// MARK: - Keycap

/// A key's outline scaled to its frame: the L of an ISO or JIS return key, a rounded rectangle otherwise.
private struct KeyOutline: Shape {
    let cap: KeyCap

    func path(in rect: CGRect) -> Path {
        let s = rect.width / CGFloat(cap.w)
        return MacKeyCap.outline(of: cap).applying(CGAffineTransform(scaleX: s, y: s)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// One key as the SDK draws it, with the hint layer on top: on the layer's binds the action in its
/// group's colour with the key's own legend small in the corner and a thin ring; without a bind it
/// recedes so the binds stand out.
private struct HintKeyCap: View {
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

    /// The action's group colour, readable on these keycaps.
    private var groupColor: Color { hint?.group.color(onDarkKeys: !light) ?? legendColor }
    /// What the keycaps are printed in.
    private var legendColor: Color { Color(mk: device.theme.legend) }
    private var pressedInk: Color { light ? .white : Theme.rgb(0x0B0B0D) }
    private var filled: Bool { pressed && hint != nil }
    /// A bound key shows its action instead of its own legends.
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

    /// A thin ring: the group's colour on a bind, the legend colour on a held modifier.
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

    /// The SDK's cap, or its outline filled with the group colour while the key is pressed. The SDK view
    /// reaches `MacKeyCap.padding` past the key on every side for its shadows.
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

    /// The action centred, in its group colour, with the key's own legend small in the corner.
    private func label(_ hint: KeyHint) -> some View {
        let k = scale
        let label = hint.label
        let full = key.frame.height >= 50
        let glyph = label.count <= 2
        let numeric = Int(label) != nil
        let ink = filled ? pressedInk : groupColor
        // On the ISO return key, the label sits in the wide top part.
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

    /// The legend that moves to the corner when a label takes the middle.
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
