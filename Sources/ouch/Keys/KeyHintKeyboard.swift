// Keys: the drawn Mac keyboard with binds written on its keys (used by Shortcut Map and Key Help).
import AppKit
import Carbon
import SwiftUI

// This Mac's keyboard, drawn like the real thing (see `MacKeyboard`: model, finish, ANSI/ISO/JIS and the
// legends of the input source in use), with one layer of binds written on its keys, coloured by group.
// The Shortcut Map and the keyboard help overlay both use it.
//
//     KeyHintKeyboard(binds: [KeyHint], style: .labels, pressed: UInt16?, hot: Set<UInt16>, scale: 1)
//         .onKeyTap { key in … }                  optional; keys become buttons
//         .onKeyHover { key, inside in … }        optional
//
// - `binds`: one layer (one mode, one set of modifiers). `KeyHint(_:)` builds them from a
//   `ConfigDocument.KeyAction` or a running `KeyBinding`.
// - `style`: `.labels` writes the action on the cap, `.lit` only colours bound keys, `.constellation`
//   hides unbound keys and the deck.
// - `pressed`: a key filled with its group colour. `hot`: keys with a ring that never recede; pass
//   held modifiers here (modifier keys carry their key codes, e.g. 55 for ⌘).
// - `scale`: 1 draws the key well 940pt wide, a 1u key 58pt. `size(scale:)` is the view's size,
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
    enum Style { case labels, lit, constellation }

    let binds: [KeyHint]
    var style: Style
    var pressed: UInt16?
    var hot: Set<UInt16>
    var scale: CGFloat
    private var tap: ((Key) -> Void)?
    private var hover: ((Key, Bool) -> Void)?
    @ObservedObject private var mac = MacKeyboard.shared
    @Environment(\.keyTile) private var tile

    init(binds: [KeyHint], style: Style = .labels, pressed: UInt16? = nil, hot: Set<UInt16> = [], scale: CGFloat = 1) {
        self.binds = binds
        self.style = style
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
        ZStack(alignment: .topLeading) {
            if style != .constellation { KeyWell(finish: mac.finish, scale: scale) }
            ForEach(mac.keys) { k in
                let r = Self.rect(of: k, scale: scale)
                HintKeyCap(key: k, finish: mac.finish, scale: scale, style: style,
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
        HintKeyCap(key: k, finish: MacKeyboard.shared.finish, scale: scale, style: .labels, hint: hint,
                   pressed: false, hot: false, tap: nil, hover: nil, fades: false)
            .frame(width: k.frame.width * scale, height: k.frame.height * scale)
    }

    // MARK: Geometry

    /// The well's padding around the keys, and the well itself, in points at scale 1.
    private static let inset = CGPoint(x: 9, y: 10)
    private static let well = CGSize(width: MacKeyboard.area.width + 18, height: MacKeyboard.area.height + 13)

    static func size(scale: CGFloat) -> CGSize {
        CGSize(width: well.width * scale, height: well.height * scale)
    }

    /// A key's cap inside the view. The ISO return key's is the box around its L.
    static func rect(of k: Key, scale: CGFloat) -> CGRect {
        CGRect(x: (inset.x + k.frame.minX) * scale, y: (inset.y + k.frame.minY) * scale,
               width: k.frame.width * scale, height: k.frame.height * scale)
    }

    /// The corner radius of a full-size key.
    static func cornerRadius(scale: CGFloat) -> CGFloat { 6 * scale }

    /// Legends of a typing key: a letter (`t`), a shifted symbol over its base (`t` over `b`), or four
    /// corners (`t` `d` over `b` `c`) where two scripts share the key.
    struct Legend: Equatable {
        enum Kind { case char, charOption, dual, quad, quadLarge }
        var t = "", b = "", c = "", d = ""
        var kind: Kind = .char
    }

    /// One key; frames are in points at scale 1, from the top-left of the key area.
    struct Key: Identifiable {
        enum Direction { case left, up, down, right }
        enum FnStyle { case standard, neo, jis }
        enum Kind {
            case typing(Legend)
            /// esc, tab, return…: a word, or a symbol where the keyboard prints one.
            case word(String, symbol: Bool, trailing: Bool, caps: Bool)
            /// ⌃ ⌥ ⌘ with their name on US keyboards.
            case modifier(String, word: String?, symbolTrailing: Bool)
            case function(Int)
            case fn(FnStyle)
            case arrow(Direction)
            case space, touchID
            /// JIS: a symbol over a digit or symbol with kana, and a letter with kana.
            case jis(Legend), jisLetter(Legend)
            case jisCenter(String)
            case jisCaps
        }
        /// The ISO and JIS return key: wide on top, narrower below `joint`.
        struct LShape { let top: CGFloat, bottom: CGFloat, joint: CGFloat }

        let code: UInt16?
        let frame: CGRect
        let kind: Kind
        /// Set on ⌃ ⌥ ⇧ ⌘.
        var modifier: NSEvent.ModifierFlags = []
        /// F and J.
        var home = false
        var lShape: LShape?
        var id: String { "\(frame.minX),\(frame.minY)" }
    }

    static var keys: [Key] { MacKeyboard.shared.keys }

    /// The key with this code; for modifiers, the left one.
    static func key(for code: UInt16) -> Key? { keys.first { $0.code == code } }

    // MARK: Legends

    /// A key's name as printed in hints and tooltips, e.g. "Å", "F5", "⇥", "⌘".
    static func legend(_ k: Key) -> String {
        let named = k.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel)
        switch k.kind {
        case .typing(let l): return l.kind == .dual ? l.b : l.t.isEmpty ? l.b : l.t
        case .word(let w, _, _, _): return named ?? w
        case .modifier(let symbol, _, _): return symbol
        case .function(let n): return "F\(n)"
        case .fn: return "fn"
        case .arrow: return named ?? ""
        case .space: return "Space"
        case .touchID: return "Touch ID"
        case .jis(let l): return l.b.isEmpty ? l.t : l.b
        case .jisLetter(let l): return l.t
        case .jisCenter(let s): return s
        case .jisCaps: return "⇪"
        }
    }
}

// MARK: - Well

/// The recess the keys sit in: near-black on a MacBook Pro, the deck itself elsewhere.
private struct KeyWell: View {
    let finish: MacKeyboard.Finish
    let scale: CGFloat

    var body: some View {
        let s = scale, f = finish
        let edge = Theme.rgb(f.edge, f.edgeAlpha)
        let deck = LinearGradient(colors: [Theme.rgb(f.deck.0), Theme.rgb(f.deck.1)], startPoint: .top, endPoint: .bottom)
        switch f.family {
        case .pro:
            let shape = RoundedRectangle(cornerRadius: 13 * s, style: .circular)
            shape.fill(Theme.rgb(0x141416))
                .overlay(InnerShadow(shape: shape, color: .black.opacity(0.8), blur: 3 * s, y: s))
                .overlay(shape.strokeBorder(Color.black, lineWidth: s))
                .background(shape.inset(by: -s / 2).stroke(edge, lineWidth: s))
        case .air, .neo:
            let shape = RoundedRectangle(cornerRadius: 13 * s, style: .circular)
            shape.fill(deck)
                .overlay(InnerShadow(shape: shape, color: .black.opacity(f.dark ? 0.45 : 0.16), blur: 2.5 * s, y: 1.5 * s))
                .overlay(shape.strokeBorder(Color.black.opacity(f.dark ? 0.28 : 0.07), lineWidth: s))
                .overlay(InsetBand(radius: 13 * s, dy: -s).fill(edge, style: FillStyle(eoFill: true)).clipShape(shape))
                .background(shape.fill(edge).offset(y: s))
                .background(shape.fill(Color.black.opacity(f.dark ? 0.18 : 0.05)).offset(y: -s))
        case .mk:
            // A Magic Keyboard is all deck: draw its aluminium 6pt past the keys.
            let shape = RoundedRectangle(cornerRadius: 18 * s, style: .circular)
            shape.fill(deck)
                .overlay(shape.strokeBorder(edge, lineWidth: s))
                .overlay(InnerShadow(shape: shape, color: .black.opacity(0.06), blur: s, y: -s))
                .shadow(color: .black.opacity(0.12), radius: 6 * s, y: 3 * s)
                .padding(-6 * s)
        }
    }
}

/// An inset shadow: the outline, blurred and offset, seen from inside the shape.
private struct InnerShadow<S: Shape>: View {
    let shape: S
    let color: Color
    let blur: CGFloat
    let y: CGFloat

    var body: some View {
        shape.stroke(color, lineWidth: blur + abs(y) * 2 + 1)
            .offset(y: y)
            .blur(radius: blur / 2)
            .clipShape(shape)
            .allowsHitTesting(false)
    }
}

/// A hard inset edge, like CSS `inset 0 dy 0`: the rounded rect minus itself moved by `dy`. Fill it
/// with `eoFill` and clip it to the rect.
private struct InsetBand: Shape {
    let radius: CGFloat
    let dy: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: radius, style: .circular)
        p.addPath(Path(roundedRect: rect.offsetBy(dx: 0, dy: dy), cornerRadius: radius, style: .circular))
        return p
    }
}

/// The ISO return key's outline, `inset` in from its box.
private struct LKeyShape: Shape {
    let l: KeyHintKeyboard.Key.LShape
    let scale: CGFloat
    var inset: CGFloat = 0.6

    func path(in rect: CGRect) -> Path {
        let s = scale, e = inset * s, r = 5.4 * s, inner = 6 * s
        let w = rect.width, h = rect.height, j = l.joint * s
        let xT = w - l.top * s + e, xB = w - l.bottom * s + e, rt = w - e, tp = e, bt = h - e
        let narrowBottom = xB > xT
        let corners = [CGPoint(x: xT, y: tp), CGPoint(x: rt, y: tp), CGPoint(x: rt, y: bt), CGPoint(x: xB, y: bt),
                       CGPoint(x: xB, y: j), CGPoint(x: xT, y: j)]
        let radii = [r, r, r, r, narrowBottom ? inner : r, narrowBottom ? r : inner]
        var p = Path()
        let last = corners[corners.count - 1]
        p.move(to: CGPoint(x: (last.x + corners[0].x) / 2, y: (last.y + corners[0].y) / 2))
        for i in corners.indices {
            p.addArc(tangent1End: corners[i], tangent2End: corners[(i + 1) % corners.count], radius: radii[i])
        }
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }

    /// The highlight along the top and the lip along the bottom.
    static func edges(_ l: KeyHintKeyboard.Key.LShape, scale s: CGFloat, size: CGSize) -> (top: Path, bottom: Path) {
        let w = size.width, h = size.height
        let xT = w - l.top * s + 0.6 * s, xB = w - l.bottom * s + 0.6 * s, rt = w - 0.6 * s
        var top = Path(), bottom = Path()
        top.move(to: CGPoint(x: xT + 3 * s, y: 1.9 * s)); top.addLine(to: CGPoint(x: rt - 3 * s, y: 1.9 * s))
        bottom.move(to: CGPoint(x: xB + 3 * s, y: h - 1.9 * s)); bottom.addLine(to: CGPoint(x: rt - 3 * s, y: h - 1.9 * s))
        return (top, bottom)
    }
}

// MARK: - Keycap

/// One key as Apple makes it, with the hint layer on top: on the layer's binds the action in its
/// group's colour with the key's own legend small in the corner and a thin ring; without a bind it
/// recedes so the binds stand out.
private struct HintKeyCap: View {
    let key: KeyHintKeyboard.Key
    let finish: MacKeyboard.Finish
    let scale: CGFloat
    let style: KeyHintKeyboard.Style
    let hint: KeyHint?
    let pressed: Bool
    let hot: Bool
    let tap: ((KeyHintKeyboard.Key) -> Void)?
    let hover: ((KeyHintKeyboard.Key, Bool) -> Void)?
    var fades = true
    @StateObject private var hovering = Flag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var interactive: Bool { tap != nil && key.code != nil }
    private var light: Bool { finish.lightKeys }
    private var w: CGFloat { key.frame.width * scale }
    private var h: CGFloat { key.frame.height * scale }
    private var isArrow: Bool { if case .arrow = key.kind { true } else { false } }
    private var radius: CGFloat { (isArrow ? 5 : 6) * scale }

    /// The action's group colour, readable on these keycaps.
    private var groupColor: Color { hint?.group.color(onDarkKeys: !light) ?? legendColor }
    /// What the keycaps are printed in.
    private var legendColor: Color { light ? Theme.rgb(finish.keyLegend ?? 0x4A4A4C) : Theme.rgb(0xD6D6DB, 0.9) }
    private var pressedInk: Color { light ? .white : Theme.rgb(0x0B0B0D) }
    private var filled: Bool { pressed && hint != nil }

    var body: some View {
        let lit = hint != nil || hot || pressed
        let face = ZStack(alignment: .topLeading) {
            cap
            Group {
                if let hint, style != .lit {
                    labelled(hint)
                } else {
                    plain.foregroundStyle(filled ? pressedInk : hint != nil && !light ? groupColor : legendColor)
                }
            }
            .frame(width: w, height: h)
            if let ring = ringColor { outline(ring) }
        }
        .frame(width: w, height: h)
        .opacity(lit || !fades ? 1 : style == .constellation ? 0 : 0.45)
        .offset(y: filled ? scale : 0)
        .scaleEffect(hot && !key.modifier.isEmpty && !reduceMotion ? 0.96 : 1)
        .contentShape(hitShape)
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

    private var hitShape: AnyShape {
        if let l = key.lShape { AnyShape(LKeyShape(l: l, scale: scale, inset: 0)) } else { AnyShape(RoundedRectangle(cornerRadius: radius)) }
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
        return hint != nil && style != .constellation ? groupColor : nil
    }

    @ViewBuilder private func outline(_ color: Color) -> some View {
        if let l = key.lShape {
            LKeyShape(l: l, scale: scale, inset: -1).stroke(color, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .circular).inset(by: -1.5 * scale).strokeBorder(color, lineWidth: 1)
        }
    }

    // MARK: The cap

    @ViewBuilder private var cap: some View {
        if let l = key.lShape { isoCap(l) } else { roundCap }
    }

    private var roundCap: some View {
        let s = scale
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        let eo = FillStyle(eoFill: true)
        return ZStack {
            if filled {
                shape.fill(groupColor)
            } else {
                faceFill(ellipse: CGSize(width: 1.3, height: 0.95), center: CGPoint(x: 0.5, y: 1.05)).clipShape(shape)
                InsetBand(radius: radius, dy: (light ? -2 : -2.25) * s)
                    .fill(light ? Color.black.opacity(0.05) : Theme.rgb(0x3B3C3E), style: eo).clipShape(shape)
                InsetBand(radius: radius, dy: (light ? 2 : 2.25) * s)
                    .fill(light ? Color.white.opacity(0.4) : Theme.rgb(0x29292B), style: eo).clipShape(shape)
                shape.strokeBorder(light ? Color.black.opacity(0.82) : Theme.rgb(0x070708), lineWidth: 1.25 * s)
                if hovering.on && interactive { shape.fill(light ? Color.black.opacity(0.05) : Color.white.opacity(0.06)) }
            }
        }
        .background(shape.fill(Color.black).shadow(color: .black.opacity(light ? 0.16 : 0.5), radius: 0.75 * s, y: s))
        .frame(width: w, height: h)
    }

    private func isoCap(_ l: KeyHintKeyboard.Key.LShape) -> some View {
        let s = scale
        let shape = LKeyShape(l: l, scale: s)
        let edges = LKeyShape.edges(l, scale: s, size: CGSize(width: w, height: h))
        return ZStack {
            if filled {
                shape.fill(groupColor)
            } else {
                faceFill(ellipse: CGSize(width: 0.85, height: 0.85), center: CGPoint(x: 0.5, y: 1)).clipShape(shape)
                edges.top.stroke(light ? Color.white.opacity(0.4) : Theme.rgb(0x2B2B2D), lineWidth: s)
                edges.bottom.stroke(light ? Color.black.opacity(0.05) : Theme.rgb(0x3B3C3E), lineWidth: 1.6 * s)
                shape.stroke(light ? Color.black.opacity(0.82) : Theme.rgb(0x070708), lineWidth: 1.25 * s)
                if hovering.on && interactive { shape.fill(light ? Color.black.opacity(0.05) : Color.white.opacity(0.06)) }
            }
        }
        .background(shape.fill(Color.black).shadow(color: .black.opacity(light ? 0.14 : 0.45), radius: 0.5 * s, y: s))
        .frame(width: w, height: h)
    }

    /// The key face: flat on light keycaps, a soft radial glow from below on dark ones. `ellipse` is the
    /// gradient's radii and `center` its centre, as fractions of the key.
    @ViewBuilder private func faceFill(ellipse: CGSize, center: CGPoint) -> some View {
        if light {
            Theme.rgb(finish.keyFace ?? 0xF6F7F9)
        } else {
            let stops: [Gradient.Stop] = [.init(color: Theme.rgb(0x333436), location: 0), .init(color: Theme.rgb(0x28282A), location: 0.45),
                                          .init(color: Theme.rgb(0x1F1F21), location: 0.75), .init(color: Theme.rgb(0x1B1B1D), location: 1)]
            // Past the ellipse the gradient keeps its last colour, as CSS and SVG gradients do.
            Theme.rgb(0x1B1B1D).overlay(alignment: .topLeading) {
                EllipticalGradient(stops: stops, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: w * ellipse.width * 2, height: h * ellipse.height * 2)
                    .offset(x: w * (center.x - ellipse.width), y: h * (center.y - ellipse.height))
            }
        }
    }

    // MARK: Legends

    private enum HPos { case left(CGFloat), right(CGFloat), center }
    private enum VPos { case top(CGFloat), bottom(CGFloat), middle(CGFloat) }

    /// Text placed as the artifact's CSS places it: `left`/`right`/`top`/`bottom` in points from the
    /// cap's edges, `middle` as the offset of the text's top from the cap's vertical centre.
    private func text(_ s: String, _ size: CGFloat, _ x: HPos, _ y: VPos, tracking: CGFloat = 0, font: Font? = nil) -> some View {
        // SF's line box is about 1.19 em; CSS here uses 1 em, so edges sit about 0.1 em further in.
        let k = scale, lead = 0.0965 * size
        return Text(s).font(font ?? .system(size: size * k)).tracking(tracking * size * k).oneLine().fixedSize()
            .padding(.leading, { if case .left(let v) = x { v * k } else { 0 } }())
            .padding(.trailing, { if case .right(let v) = x { v * k } else { 0 } }())
            .padding(.top, { if case .top(let v) = y { (v - lead) * k } else { 0 } }())
            .padding(.bottom, { if case .bottom(let v) = y { (v - lead) * k } else { 0 } }())
            .frame(width: w, height: h, alignment: alignment(x, y))
            .offset(y: { if case .middle(let m) = y { (m + size / 2) * k } else { 0 } }())
    }

    private func icon(_ d: String, filled: Bool, _ size: CGFloat, _ x: HPos, _ y: VPos) -> some View {
        let k = scale
        return Group {
            if filled {
                IconPath(d: d).fill(style: FillStyle())
            } else {
                IconPath(d: d).stroke(style: StrokeStyle(lineWidth: 1.7 * size / 24 * k, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size * k, height: size * k)
        .padding(.leading, { if case .left(let v) = x { v * k } else { 0 } }())
        .padding(.trailing, { if case .right(let v) = x { v * k } else { 0 } }())
        .padding(.top, { if case .top(let v) = y { v * k } else { 0 } }())
        .padding(.bottom, { if case .bottom(let v) = y { v * k } else { 0 } }())
        .frame(width: w, height: h, alignment: alignment(x, y))
    }

    private func alignment(_ x: HPos, _ y: VPos) -> Alignment {
        let hz: HorizontalAlignment = { switch x { case .left: .leading; case .right: .trailing; case .center: .center } }()
        let vt: VerticalAlignment = { switch y { case .top: .top; case .bottom: .bottom; case .middle: .center } }()
        return Alignment(horizontal: hz, vertical: vt)
    }

    /// Small marks in the plastic: home bumps, the caps lock light.
    private func mark(_ width: CGFloat, _ height: CGFloat, color: Color, x: CGFloat?, y: CGFloat?, bottom: CGFloat? = nil) -> some View {
        let k = scale
        return RoundedRectangle(cornerRadius: min(width, height) / 2 * k)
            .fill(color)
            .frame(width: width * k, height: height * k)
            .position(x: x.map { $0 * k + width * k / 2 } ?? w / 2,
                      y: y.map { $0 * k + height * k / 2 } ?? (bottom.map { h - $0 * k - height * k / 2 } ?? h / 2))
    }

    private var homeColor: Color { light ? legendColor.opacity(0.5) : Theme.rgb(0xE0E0E4, 0.55) }
    private var capsDotColor: Color { light ? Color.black.opacity(0.35) : Theme.rgb(0x58585B) }

    /// The key as Apple prints it.
    @ViewBuilder private var plain: some View {
        switch key.kind {
        case .typing(let l):
            switch l.kind {
            case .char:
                text(l.t, 16.5, .center, .middle(-8))
            case .charOption:
                text(l.t, 16.5, .center, .middle(-8))
                text(l.c, 10.5, .right(9), .bottom(8))
            case .dual:
                text(l.t, 10.5, .center, .top(10))
                text(l.b, 16.5, .center, .bottom(10))
            case .quad, .quadLarge:
                let big = l.kind == .quadLarge
                text(l.t, big ? 15 : 12, .left(9), .top(8))
                text(l.b, big ? 15 : 13.5, .left(9), .bottom(8))
                text(l.d, big ? 15 : 12, .right(9), .top(8))
                text(l.c, big ? 15 : 13.5, .right(9), .bottom(8))
            }
            if key.home {
                if l.kind == .char || l.kind == .charOption || l.kind == .dual {
                    mark(9, 1.5, color: homeColor, x: nil, y: nil, bottom: 9)
                } else {
                    mark(9, 1.5, color: homeColor, x: nil, y: key.frame.height / 2 - 1)
                }
            }
        case .word(let word, let symbol, let trailing, let caps):
            text(word, symbol ? 13.5 : 10.5, trailing ? .right(9) : .left(9), .bottom(9), tracking: 0.01)
            if caps { mark(3, 3, color: capsDotColor, x: 10, y: 11) }
        case .modifier(let symbol, let word, let symbolTrailing):
            text(symbol, 12.5, symbolTrailing ? .right(9) : .left(9), .top(8))
            if let word { text(word, 10.5, .left(9), .bottom(9), tracking: 0.01) }
        case .function(let n):
            icon(Icons.function[n - 1] + (light && n == 10 ? Icons.muteCross : ""), filled: false, 12, .center, .top(13))
            text("F\(n)", 8, .center, .bottom(9), tracking: 0.02)
        case .fn(let fnStyle):
            switch fnStyle {
            case .standard:
                text("fn", 10.5, .right(9), .top(8))
                icon(Icons.globe, filled: false, 12, .left(9), .bottom(8))
            case .neo:
                text("fn", 10.5, .right(9), .bottom(9))
                icon(Icons.globe, filled: false, 12, .left(9), .bottom(8))
            case .jis:
                text("fn", 10.5, .right(9), .bottom(9))
                icon(Icons.globe, filled: false, 12, .left(9), .top(8))
            }
        case .arrow(let dir):
            icon(Icons.arrow(dir), filled: true, 8, .center, .middle(0))
        case .space:
            EmptyView()
        case .touchID:
            touchID
        case .jis(let l):
            text(l.t, 10.5, .center, .top(7))
            text(l.b, 16, .left(10), .middle(-8))
            text(l.c, 10.5, .center, .bottom(7))
            text(l.d, 9.5, .right(9), .middle(-5))
        case .jisLetter(let l):
            text(l.t, 16, .left(10), .middle(-10))
            text(l.c, 10.5, .center, .bottom(7))
            text(l.d, 9.5, .right(9), .middle(-5))
            if key.home { mark(6, 1.5, color: homeColor, x: key.frame.width * 0.55 - 3, y: key.frame.height / 2 - 1) }
        case .jisCenter(let s):
            text(s, 12.5, .center, .middle(-6.5))
        case .jisCaps:
            mark(3, 3, color: capsDotColor, x: 10, y: key.frame.height / 2 - 1.5)
            text("⇪", 13.5, .left(20), .middle(-7))
        }
    }

    /// The sensor: a dark glass disc with a hairline ring, or a ring in the key's colour on light keys.
    private var touchID: some View {
        let k = scale
        return ZStack {
            if light {
                Circle().fill(Color.black.opacity(0.28)).frame(width: 34 * k, height: 34 * k)
                Circle().fill(Theme.rgb(finish.keyFace ?? 0xF6F7F9)).frame(width: 32 * k, height: 32 * k)
            } else {
                Circle().fill(Color.black.opacity(0.6)).frame(width: 36 * k, height: 36 * k)
                Circle().fill(Color.white.opacity(0.14)).frame(width: 34 * k, height: 34 * k)
                Circle().fill(RadialGradient(stops: [.init(color: Theme.rgb(0x2E2E31), location: 0), .init(color: Theme.rgb(0x161618), location: 0.55),
                                                     .init(color: Theme.rgb(0x0D0D0F), location: 1)],
                                             center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: 30 * k))
                    .frame(width: 32 * k, height: 32 * k)
            }
        }
        .frame(width: w, height: h)
    }

    /// The action centred, in its group colour, with the key's own legend small in the corner.
    private func labelled(_ hint: KeyHint) -> some View {
        let k = scale
        let label = hint.label
        let full = key.frame.height >= 50
        let glyph = label.count <= 2
        let numeric = Int(label) != nil
        let ink = filled ? pressedInk : groupColor
        // On the ISO return key, the label sits in the wide top part.
        let box = key.lShape.map { CGSize(width: $0.top * k, height: $0.joint * k) } ?? CGSize(width: w, height: h)
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
        let color = filled ? pressedInk : legendColor.opacity(0.55)
        switch key.kind {
        case .typing(let l) where l.kind == .charOption:
            Text(l.t).font(.system(size: 10.5 * scale)).oneLine().fixedSize()
                .foregroundStyle(color)
                .padding(.leading, 7 * scale).padding(.top, (7 - 1) * scale)
            Text(l.c).font(.system(size: 9.5 * scale)).oneLine().fixedSize()
                .foregroundStyle(color)
                .padding(.trailing, 7 * scale).padding(.bottom, 6 * scale)
                .frame(width: w, height: h, alignment: .bottomTrailing)
        default:
            let text = cornerText
            if !text.isEmpty {
                Text(text).font(.system(size: 10.5 * scale)).oneLine().fixedSize()
                    .foregroundStyle(color)
                    .padding(.leading, 7 * scale).padding(.top, (7 - 1) * scale)
            }
        }
    }

    private var cornerText: String {
        switch key.kind {
        case .typing(let l): l.kind == .dual ? l.b : l.t
        case .word(let w, _, _, _): w
        case .modifier(let symbol, _, _): symbol
        case .function(let n): "F\(n)"
        case .fn: "fn"
        case .jis(let l): l.b.isEmpty ? l.t : l.b
        case .jisLetter(let l): l.t
        case .jisCenter(let s): s
        case .jisCaps: "⇪"
        case .arrow, .space, .touchID: ""
        }
    }
}

// MARK: - Icons

/// The F-row, globe and arrow icons, as 24pt SVG paths: function keys and the globe stroked, arrows filled.
private enum Icons {
    static let function = [
        "M9.5 12a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0 -5 0M12 5.5v1M12 17.5v1M5.5 12h1M17.5 12h1M7.4 7.4l.7.7M15.9 15.9l.7.7M7.4 16.6l.7-.7M15.9 8.1l.7-.7",
        "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8",
        "M3 5.5h8v5H3zM3 13.5h8v5H3zM14 5.5h7v13h-7z",
        "M4 10.5a6.5 6.5 0 1 0 13 0a6.5 6.5 0 1 0 -13 0M15.5 15.5l5 5",
        "M9 6a3 3 0 0 1 6 0v5.5a3 3 0 0 1-6 0zM5.5 11a6.5 6.5 0 0 0 13 0M12 17.5v3.5",
        "M19.5 14.6A7.6 7.6 0 0 1 9.4 4.5a7.6 7.6 0 1 0 10.1 10.1z",
        "M11 7v10l-7-5zM20 7v10l-7-5z",
        "M3 7v10l7-5zM15 7v10M19 7v10",
        "M4 7v10l7-5zM13 7v10l7-5z",
        "M3.5 9.5h3l4.5-4v13l-4.5-4h-3z",
        "M3 9.5h3l4.5-4v13L6 14.5H3zM14.5 9.5a3.5 3.5 0 0 1 0 5",
        "M1.5 9.5h3l4.5-4v13l-4.5-4h-3zM12.5 9.5a3.5 3.5 0 0 1 0 5M15.5 7a7 7 0 0 1 0 10M18.5 4.5a10.5 10.5 0 0 1 0 15",
    ]
    /// Light keycaps cross out the mute speaker.
    static let muteCross = "M15 9.5l5 5M20 9.5l-5 5"
    static let globe = "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0M3 12h18M12 3c2.6 2.5 3.8 5.6 3.8 9s-1.2 6.5-3.8 9c-2.6-2.5-3.8-5.6-3.8-9s1.2-6.5 3.8-9z"

    static func arrow(_ d: KeyHintKeyboard.Key.Direction) -> String {
        switch d {
        case .left: "M6 12l11-7v14z"
        case .up: "M12 5.5l7.5 12h-15z"
        case .down: "M12 18.5L4.5 6.5h15z"
        case .right: "M18 12L7 19V5z"
        }
    }
}

/// An SVG path on a 24pt grid, scaled to the frame. Understands the commands the icons use: M L H V C S
/// A Z, absolute and relative.
private struct IconPath: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        Self.parsed(d).applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 24, y: rect.height / 24))
    }

    private static var cache: [String: Path] = [:]

    private static func parsed(_ d: String) -> Path {
        if let p = cache[d] { return p }
        let p = parse(d)
        cache[d] = p
        return p
    }

    private static func parse(_ d: String) -> Path {
        let s = Array(d.utf8)
        var i = 0
        func skip() { while i < s.count, s[i] == 0x20 || s[i] == 0x2C || s[i] == 0x0A { i += 1 } }
        func number() -> CGFloat? {
            skip()
            let start = i
            if i < s.count, s[i] == 0x2D || s[i] == 0x2B { i += 1 }
            var dot = false
            while i < s.count {
                if (0x30...0x39).contains(s[i]) { i += 1 } else if s[i] == 0x2E && !dot { dot = true; i += 1 } else { break }
            }
            guard i > start, let v = Double(String(decoding: s[start..<i], as: UTF8.self)) else { i = start; return nil }
            return CGFloat(v)
        }
        func flag() -> Bool? {
            skip()
            guard i < s.count, s[i] == 0x30 || s[i] == 0x31 else { return nil }
            defer { i += 1 }
            return s[i] == 0x31
        }

        var p = Path()
        var cmd: UInt8 = 0, previous: UInt8 = 0
        var cur = CGPoint.zero, start = CGPoint.zero, control = CGPoint.zero
        while true {
            skip()
            guard i < s.count else { break }
            let c = s[i]
            if (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c) {
                cmd = c
                i += 1
                if c == 0x5A || c == 0x7A { // Z
                    p.closeSubpath()
                    cur = start
                    previous = c
                    continue
                }
            }
            let rel = cmd >= 0x61
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
            let before = i
            switch cmd | 0x20 { // lowercased
            case 0x6D: // m
                guard let x = number(), let y = number() else { break }
                cur = pt(x, y); start = cur
                p.move(to: cur)
                cmd = rel ? 0x6C : 0x4C // further pairs are lines
            case 0x6C: // l
                guard let x = number(), let y = number() else { break }
                cur = pt(x, y)
                p.addLine(to: cur)
            case 0x68: // h
                guard let x = number() else { break }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                p.addLine(to: cur)
            case 0x76: // v
                guard let y = number() else { break }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                p.addLine(to: cur)
            case 0x63: // c
                guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(), let y = number() else { break }
                let c1 = pt(x1, y1), c2 = pt(x2, y2), end = pt(x, y)
                p.addCurve(to: end, control1: c1, control2: c2)
                control = c2; cur = end
            case 0x73: // s
                guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { break }
                let smooth = [0x63, 0x73].contains(previous | 0x20)
                let c1 = smooth ? CGPoint(x: 2 * cur.x - control.x, y: 2 * cur.y - control.y) : cur
                let c2 = pt(x2, y2), end = pt(x, y)
                p.addCurve(to: end, control1: c1, control2: c2)
                control = c2; cur = end
            case 0x61: // a
                guard let r = number(), number() != nil, number() != nil, let large = flag(), let sweep = flag(),
                      let x = number(), let y = number() else { break }
                let end = pt(x, y)
                addArc(&p, from: cur, to: end, radius: r, large: large, sweep: sweep)
                cur = end
            default:
                break
            }
            previous = cmd
            if i == before { i += 1 } // nothing parsed: skip the character rather than loop
        }
        return p
    }

    /// A circular SVG arc as Béziers, from the endpoint form.
    private static func addArc(_ p: inout Path, from a: CGPoint, to b: CGPoint, radius: CGFloat, large: Bool, sweep: Bool) {
        guard radius > 0, a != b else { p.addLine(to: b); return }
        let hx = (a.x - b.x) / 2, hy = (a.y - b.y) / 2
        let d2 = hx * hx + hy * hy
        let r = max(radius, sqrt(d2))
        let coef = (large == sweep ? -1 : 1) * sqrt(max(0, (r * r - d2) / d2))
        let cx = coef * hy + (a.x + b.x) / 2, cy = -coef * hx + (a.y + b.y) / 2
        let t1 = atan2(a.y - cy, a.x - cx)
        var dt = atan2(b.y - cy, b.x - cx) - t1
        if sweep && dt < 0 { dt += 2 * .pi }
        if !sweep && dt > 0 { dt -= 2 * .pi }
        let n = max(1, Int(ceil(abs(dt) / (.pi / 2) - 0.001)))
        let step = dt / CGFloat(n), kappa = 4 / 3 * tan(step / 4)
        var t = t1
        for _ in 0..<n {
            let t2 = t + step
            let p1 = CGPoint(x: cx + r * (cos(t) - kappa * sin(t)), y: cy + r * (sin(t) + kappa * cos(t)))
            let p2 = CGPoint(x: cx + r * (cos(t2) + kappa * sin(t2)), y: cy + r * (sin(t2) - kappa * cos(t2)))
            p.addCurve(to: CGPoint(x: cx + r * cos(t2), y: cy + r * sin(t2)), control1: p1, control2: p2)
            t = t2
        }
    }
}
