import AppKit
import Carbon
import SwiftUI

// A MacBook keyboard (ANSI, drawn to scale, legends from the user's own layout) that writes one layer
// of binds on its keys, coloured by group. The Shortcut Map and the keyboard help overlay both use it.
//
//     KeyHintKeyboard(binds: [KeyHint], style: .labels, pressed: UInt16?, hot: Set<UInt16>, scale: 1)
//         .onKeyTap { key in … }                  optional; keys become buttons
//         .onKeyHover { key, inside in … }        optional
//
// - `binds`: one layer (one mode, one set of modifiers). `KeyHint(_:)` builds them from a
//   `ConfigDocument.KeyAction` or a running `KeyBinding`.
// - `style`: `.labels` writes the action on the cap, `.lit` only colours bound keys, `.constellation`
//   hides unbound keys and the deck.
// - `pressed`: a key flashing in its group colour. `hot`: keys with a white ring that never recede;
//   pass held modifiers here (modifier keys carry their key codes, e.g. 55 for ⌘).
// - `scale`: 1 draws a 1u key 40pt wide. `size(scale:)` is the view's size, `rect(of:scale:)` a key's
//   frame inside it, for popovers and tooltips placed over a key.

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
        case "togglefloating": return "Float"
        case "retile", "reevaluate": return "Retile"
        case "toggletiling": return "Tiling"
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
        case .spaces: Theme.accent2Ink
        case .layout: Theme.sky
        case .window: Theme.ink
        case .leave: Theme.inkFaint
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
        let u = Self.unit * scale
        let bound = Dictionary(binds.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let typed = Self.typed()
        let size = Self.size(scale: scale)
        ZStack(alignment: .topLeading) {
            if style != .constellation {
                // The deck: a sunken well holding the keys.
                let deck = RoundedRectangle(cornerRadius: u * 0.42, style: .continuous)
                deck.fill(Theme.surfaceSunken).overlay(deck.strokeBorder(Theme.hairline))
            }
            ForEach(Self.keys) { k in
                let r = Self.rect(of: k, scale: scale)
                HintKeyCap(key: k, legends: Self.legends(k, typed), unit: u, style: style,
                           hint: k.code.flatMap { bound[$0] }, pressed: k.code != nil && k.code == pressed,
                           hot: k.code.map(hot.contains) ?? false, tap: tap, hover: hover)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Geometry

    /// Points per key unit at scale 1.
    static let unit: CGFloat = 40
    private static let pad: CGFloat = 0.32

    static func size(scale: CGFloat) -> CGSize {
        CGSize(width: (width + pad * 2) * unit * scale, height: (height + pad * 2) * unit * scale)
    }

    /// A key's cap inside the view, gaps taken out.
    static func rect(of k: Key, scale: CGFloat) -> CGRect {
        let u = unit * scale, gap = u * 0.1
        return CGRect(x: (pad + k.frame.minX) * u + gap / 2, y: (pad + k.frame.minY) * u + gap / 2,
                      width: k.frame.width * u - gap, height: k.frame.height * u - gap)
    }

    enum Label {
        case char(String, String?) // US fallback: base and shifted
        case word(String, trailing: Bool)
        case function(String, Int)
        case modifier(String, String, trailing: Bool)
        case arrow(String)
        case globe, space, touchID
    }

    /// One key; sizes are in key units, where 1u is one letter key plus its gap.
    struct Key: Identifiable {
        let code: UInt16?
        let frame: CGRect
        let label: Label
        /// Set on ⌃ ⌥ ⇧ ⌘.
        var modifier: NSEvent.ModifierFlags = []
        var id: String { "\(frame.minX),\(frame.minY)" }
    }

    static let width: CGFloat = 14.5
    static let functionRow: CGFloat = 0.62
    static let height: CGFloat = functionRow + 5

    /// A MacBook Air keyboard (ANSI), left to right, top to bottom.
    static let keys: [Key] = {
        var out: [Key] = []
        var y: CGFloat = 0
        func row(_ h: CGFloat, _ items: [(UInt16?, CGFloat, Label)]) {
            var x: CGFloat = 0
            for (code, w, label) in items {
                var k = Key(code: code, frame: CGRect(x: x, y: y, width: w, height: h), label: label)
                if case .modifier(let s, _, _) = label {
                    k.modifier = s == "⌃" ? .control : s == "⌥" ? .option : s == "⌘" ? .command : .shift
                }
                out.append(k)
                x += w
            }
            y += h
        }
        let fSymbols = ["sun.min", "sun.max", "rectangle.3.group", "magnifyingglass", "mic", "moon",
                        "backward", "playpause", "forward", "speaker", "speaker.wave.1", "speaker.wave.3"]
        let fCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        row(functionRow, [(53, 1.5, .word("esc", trailing: false))]
            + (0..<12).map { (fCodes[$0], 1, .function(fSymbols[$0], $0 + 1)) }
            + [(nil, 1, .touchID)])
        func chars(_ s: [(UInt16, String, String?)]) -> [(UInt16?, CGFloat, Label)] { s.map { ($0.0, 1, .char($0.1, $0.2)) } }
        row(1, chars([(50, "`", "~"), (18, "1", "!"), (19, "2", "@"), (20, "3", "#"), (21, "4", "$"), (23, "5", "%"), (22, "6", "^"),
                      (26, "7", "&"), (28, "8", "*"), (25, "9", "("), (29, "0", ")"), (27, "-", "_"), (24, "=", "+")])
            + [(51, 1.5, .word("delete", trailing: true))])
        row(1, [(48, 1.5, .word("tab", trailing: false))]
            + chars([(12, "Q", nil), (13, "W", nil), (14, "E", nil), (15, "R", nil), (17, "T", nil), (16, "Y", nil), (32, "U", nil),
                     (34, "I", nil), (31, "O", nil), (35, "P", nil), (33, "[", "{"), (30, "]", "}"), (42, "\\", "|")]))
        row(1, [(57, 1.75, .word("caps lock", trailing: false))]
            + chars([(0, "A", nil), (1, "S", nil), (2, "D", nil), (3, "F", nil), (5, "G", nil), (4, "H", nil), (38, "J", nil),
                     (40, "K", nil), (37, "L", nil), (41, ";", ":"), (39, "'", "\"")])
            + [(36, 1.75, .word("return", trailing: true))])
        row(1, [(56, 2.25, .modifier("⇧", "shift", trailing: false))]
            + chars([(6, "Z", nil), (7, "X", nil), (8, "C", nil), (9, "V", nil), (11, "B", nil), (45, "N", nil), (46, "M", nil),
                     (43, ",", "<"), (47, ".", ">"), (44, "/", "?")])
            + [(60, 2.25, .modifier("⇧", "shift", trailing: true))])
        row(1, [(nil, 1, .globe), (59, 1, .modifier("⌃", "control", trailing: false)), (58, 1, .modifier("⌥", "option", trailing: false)),
                (55, 1.25, .modifier("⌘", "command", trailing: false)), (49, 5, .space),
                (54, 1.25, .modifier("⌘", "command", trailing: true)), (61, 1, .modifier("⌥", "option", trailing: true))])
        // The inverted-T arrows: half-height keys, up and down sharing one slot.
        let ay = y - 1, ax: CGFloat = 11.5
        out += [Key(code: 123, frame: CGRect(x: ax, y: ay + 0.5, width: 1, height: 0.5), label: .arrow("arrowtriangle.left.fill")),
                Key(code: 126, frame: CGRect(x: ax + 1, y: ay, width: 1, height: 0.5), label: .arrow("arrowtriangle.up.fill")),
                Key(code: 125, frame: CGRect(x: ax + 1, y: ay + 0.5, width: 1, height: 0.5), label: .arrow("arrowtriangle.down.fill")),
                Key(code: 124, frame: CGRect(x: ax + 2, y: ay + 0.5, width: 1, height: 0.5), label: .arrow("arrowtriangle.right.fill"))]
        return out
    }()

    /// The key with this code; for modifiers, the left one.
    static func key(for code: UInt16) -> Key? { keys.first { $0.code == code } }

    // MARK: Legends

    private typealias Typed = [UInt16: (base: String, shifted: String?)]
    private static var typedCache: (layout: String, table: Typed)?

    /// What the typing keys type on the current keyboard layout, so the drawing matches the keyboard in
    /// front of you (Å Ø Æ on Norwegian). Rebuilt when the layout changes.
    private static func typed() -> Typed {
        var layout = ""
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            layout = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }
        if let c = typedCache, c.layout == layout { return c.table }
        var out: Typed = [:]
        for k in keys {
            guard let code = k.code, case .char = k.label,
                  let base = ConfigDocument.typedCharacter(keyCode: code, flags: []) else { continue }
            out[code] = (base, ConfigDocument.typedCharacter(keyCode: code, flags: .shift))
        }
        typedCache = (layout, out)
        return out
    }

    /// Upper and lower legend for a typing key: one letter, or a shifted symbol over the base one.
    private static func legends(_ k: Key, _ typed: Typed) -> (top: String?, main: String) {
        guard case .char(let base, let shifted) = k.label else { return (nil, legend(k, typed)) }
        if let code = k.code, let t = typed[code] {
            if t.base.uppercased() != t.base || t.base.lowercased() != t.base { return (nil, t.base.uppercased()) }
            return (t.shifted == t.base ? nil : t.shifted, t.base)
        }
        return (shifted, base)
    }

    /// A key's name as printed in hints and tooltips, e.g. "Å", "F5", "⇥", "⌘".
    static func legend(_ k: Key) -> String { legend(k, typed()) }

    private static func legend(_ k: Key, _ typed: Typed) -> String {
        switch k.label {
        case .char: legends(k, typed).main
        case .word(let w, _): k.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel) ?? w
        case .function(_, let n): "F\(n)"
        case .arrow: k.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel) ?? ""
        case .modifier(let symbol, _, _): symbol
        case .globe: "fn"
        case .space: "Space"
        case .touchID: ""
        }
    }
}

// MARK: - Keycap

/// One key. On the layer's binds it wears its group's colour as a ring, a glow and the label; without a
/// bind it recedes so the binds stand out.
private struct HintKeyCap: View {
    let key: KeyHintKeyboard.Key
    let legends: (top: String?, main: String)
    let unit: CGFloat
    let style: KeyHintKeyboard.Style
    let hint: KeyHint?
    let pressed: Bool
    let hot: Bool
    let tap: ((KeyHintKeyboard.Key) -> Void)?
    let hover: ((KeyHintKeyboard.Key, Bool) -> Void)?
    @StateObject private var hovering = Flag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var interactive: Bool { tap != nil && key.code != nil }
    private var color: Color { hint?.group.color ?? Theme.inkMuted }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.12, style: .continuous)
        let lit = hint != nil || hot || pressed
        let face = ZStack {
            shape.fill(pressed ? (hint == nil ? Theme.wellHover : color) : Theme.surface)
                .shadow(color: .black.opacity(0.12), radius: 0, y: unit * 0.025)
            if hovering.on && interactive && !pressed { shape.fill(Theme.ink.opacity(0.06)) }
            if hint != nil || hot {
                // A thin ring in the group's colour; ink for held modifiers and hot keys.
                shape.strokeBorder(hot ? Theme.ink : color, lineWidth: 1)
            } else {
                shape.strokeBorder(Theme.hairline, lineWidth: 0.75)
            }
            legend
        }
        .opacity(lit ? 1 : style == .constellation ? 0 : 0.45)
        .scaleEffect(hot && !key.modifier.isEmpty && !reduceMotion ? 0.96 : 1)
        .contentShape(shape)
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
        let name = legends.main.isEmpty ? KeyHintKeyboard.legend(key) : legends.main
        if !key.modifier.isEmpty { return "\(name) modifier" }
        guard let hint else { return "\(name), no shortcut" }
        return "\(name): \(hint.title)"
    }

    /// The colour the legend is printed in.
    private var ink: Color {
        if pressed { return Theme.surface }
        if hint != nil { return style == .lit ? color : Theme.inkMuted }
        return Theme.ink
    }

    @ViewBuilder private var legend: some View {
        if let hint, style != .lit {
            labelled(hint)
        } else {
            plain
        }
    }

    /// The key's own legend small in the corner and the action centred, in its group colour.
    private func labelled(_ hint: KeyHint) -> some View {
        let label = hint.label
        let full = key.frame.height >= 0.9
        let corner = cornerLegend
        let numeric = Int(label) != nil
        let glyph = label.count == 1 && !numeric
        let font: Font = numeric ? Theme.body(unit * (full ? 0.34 : 0.24), .regular)
            : glyph ? Theme.keys(unit * (full ? 0.34 : 0.24), .regular)
            : Theme.body(unit * (full ? 0.2 : 0.15), .medium)
        return ZStack(alignment: .topLeading) {
            if full && !corner.isEmpty {
                Text(corner).font(.system(size: unit * 0.15)).oneLine()
                    .foregroundStyle(pressed ? Theme.surface.opacity(0.75) : Theme.ink.opacity(0.7))
                    .padding(.leading, unit * 0.09).padding(.top, unit * 0.06)
            }
            Text(label).font(font).oneLine().minimumScaleFactor(0.8)
                .foregroundStyle(pressed ? Theme.surface : color)
                .padding(.horizontal, unit * 0.06)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: full && !corner.isEmpty ? unit * 0.05 : 0)
        }
    }

    /// The legend that moves to the corner when a label takes the middle.
    private var cornerLegend: String {
        switch key.label {
        case .char: legends.main
        case .word(let w, _): w
        case .function(_, let n): "F\(n)"
        case .modifier(let symbol, _, _): symbol
        case .globe: "fn"
        case .arrow, .space, .touchID: ""
        }
    }

    /// The key as printed on a MacBook.
    @ViewBuilder private var plain: some View {
        let small = Font.system(size: unit * 0.17, weight: .regular)
        let ink = self.ink
        switch key.label {
        case .char:
            if let top = legends.top {
                VStack(spacing: unit * 0.04) {
                    Text(top).font(.system(size: unit * 0.2))
                    Text(legends.main).font(.system(size: unit * 0.24))
                }
                .foregroundStyle(ink)
            } else {
                Text(legends.main).font(.system(size: unit * 0.3)).foregroundStyle(ink)
            }
        case .word(let w, let trailing):
            Text(w).font(small).oneLine().foregroundStyle(ink)
                .padding(.horizontal, unit * 0.1).padding(.vertical, unit * 0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailing ? .bottomTrailing : .bottomLeading)
        case .function(let symbol, let n):
            VStack(spacing: unit * 0.04) {
                Image(systemName: symbol).font(.system(size: unit * 0.15))
                Text("F\(n)").font(.system(size: unit * 0.12))
            }
            .foregroundStyle(ink)
        case .modifier(let symbol, let name, let trailing):
            VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
                Text(symbol).font(.system(size: unit * 0.2))
                Spacer(minLength: 0)
                Text(name).font(small).oneLine()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, unit * 0.1).padding(.vertical, unit * 0.08)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailing ? .trailing : .leading)
        case .arrow(let symbol):
            Image(systemName: symbol).font(.system(size: unit * 0.13, weight: .medium)).foregroundStyle(ink)
        case .globe:
            VStack(alignment: .leading, spacing: 0) {
                Text("fn").font(small).frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 0)
                Image(systemName: "globe").font(.system(size: unit * 0.2))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, unit * 0.1).padding(.vertical, unit * 0.08)
        case .space:
            EmptyView()
        case .touchID:
            Circle().strokeBorder(Theme.hairline, lineWidth: 1).padding(unit * 0.08)
        }
    }
}
