import AppKit
import SwiftUI

/// Full-window map of the shortcuts on a MacBook keyboard. Pick a modifier combo (or hold the keys
/// down) and every key shows what it does with it; click a key to change or add its shortcut.
struct ShortcutMap: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @StateObject private var model = ShortcutMapModel()

    var body: some View {
        let all = doc.keyActions(in: model.mode)
        let flags = model.flags
        let layer = all.filter { $0.flags == flags }
        VStack(spacing: 0) {
            header(all)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MacKeyboard(doc: doc, model: model, layer: layer, all: all, reveal: reveal)
                        .frame(maxWidth: 940)
                        .frame(maxWidth: .infinity)
                    hint(layer)
                    list(layer)
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)
            }
        }
        .ignoresSafeArea(edges: .top) // the header's first row is the title bar
        .background(Theme.window.ignoresSafeArea())
        .onAppear {
            model.mode = doc.submaps.contains(ui.bindMode) ? ui.bindMode : ""
            model.picked = model.busiest(all: doc.keyActions(in: model.mode))
            model.startWatchingModifiers()
        }
        .onDisappear { model.stopWatchingModifiers() }
        .onChange(of: model.mode) { _, m in
            model.selected = nil
            model.picked = model.busiest(all: doc.keyActions(in: m))
        }
    }

    /// The title bar row, level with the traffic lights: the set switch centred on the window, Done on
    /// the right. Below it the heading sits where every pane's does, over the modifier picker.
    private func header(_ all: [ConfigDocument.KeyAction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if doc.submaps.count > 1 {
                    Segmented(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                              selection: $model.mode)
                }
                HStack {
                    Spacer()
                    Button("Done") { close() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.trailing, 14)
            }
            // Regular-size controls, centred on the traffic lights (the title bar is 28pt).
            .frame(height: 28)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text("Shortcut Map").font(Theme.heading(22))
                    .padding(.top, 4).padding(.bottom, 12)
                HStack(spacing: 14) {
                    modifierToggles
                    Spacer(minLength: 8)
                    combos(all)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    /// ⌃ ⌥ ⇧ ⌘ as one strip of toggles, lit like the keys they stand for.
    private var modifierToggles: some View {
        let mods: [(NSEvent.ModifierFlags, String, String)] = [(.control, "⌃", "Control"), (.option, "⌥", "Option"),
                                                               (.shift, "⇧", "Shift"), (.command, "⌘", "Command")]
        return HStack(spacing: 2) {
            ForEach(mods, id: \.1) { flag, symbol, name in
                let on = model.flags.contains(flag)
                Button { model.toggle(flag) } label: {
                    HStack(spacing: 5) {
                        Text(symbol).font(Theme.body(13, .semibold))
                        Text(name).font(Theme.body(12.5, .medium))
                    }
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.85))
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Color.accentColor : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? [.isSelected, .isToggle] : .isToggle)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
        .animation(.easeOut(duration: 0.12), value: model.flags.rawValue)
    }

    /// Jumps to a row in the Keyboard Shortcuts pane and flashes it.
    private func reveal(_ row: BindRow) {
        model.selected = nil
        ui.bindMode = row.submap
        ui.search = ""
        ui.expanded.insert(row.id)
        ui.reveal = row.id
        ui.pane = .keybinds
        withAnimation(Motion.snap) { ui.showMap = false }
    }

    private func close() {
        model.selected = nil
        withAnimation(Motion.snap) { ui.showMap = false }
    }

    /// Shortcuts to the modifier combos that have shortcuts, busiest first.
    private func combos(_ all: [ConfigDocument.KeyAction]) -> some View {
        let counts = Dictionary(grouping: all, by: { $0.flags.rawValue }).mapValues(\.count)
        let list = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (flags: NSEvent.ModifierFlags(rawValue: $0.key), count: $0.value) }
        return HStack(spacing: 6) {
            if !list.isEmpty {
                Text("In use").font(Theme.body(11.5)).foregroundStyle(Theme.secondary)
            }
            ForEach(list, id: \.flags.rawValue) { item in
                let on = item.flags == model.flags
                let name = item.flags.isEmpty ? "None" : ConfigDocument.modifierCaps(item.flags).joined()
                Button {
                    model.held = []
                    model.selected = nil
                    withAnimation(.easeOut(duration: 0.15)) { model.picked = item.flags }
                } label: {
                    HStack(spacing: 5) {
                        Text(name).font(Theme.body(12, .semibold))
                        Text("\(item.count)").font(Theme.body(11)).monospacedDigit()
                            .foregroundStyle(on ? Color.white.opacity(0.8) : Theme.secondary)
                    }
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Capsule().fill(on ? Color.accentColor : Theme.card))
                    .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.hairline))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show \(name == "None" ? "shortcuts without modifiers" : name + " shortcuts")")
                .accessibilityLabel("\(name), \(item.count) shortcuts")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.flags.rawValue)
    }

    /// What the hovered key does, or how to use the map.
    private func hint(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let caps = ConfigDocument.modifierCaps(model.flags)
        return HStack(spacing: 8) {
            if let code = model.hovered, let key = MacKeyboard.spec(code) {
                Keycaps(caps: caps + [model.legend(key)])
                if let a = layer.first(where: { $0.code == code }) {
                    Circle().fill(a.category.color).frame(width: 7, height: 7)
                    Text(a.title)
                } else {
                    Text("Nothing yet. Click to add a shortcut.").foregroundStyle(Theme.secondary)
                }
            } else {
                Text("Hold ⌃ ⌥ ⇧ ⌘ or pick them above to see their shortcuts. Click any key to change it.")
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(Theme.body(12.5))
        .frame(height: 22)
        .frame(maxWidth: 940).frame(maxWidth: .infinity)
    }

    /// Every shortcut in the layer, in keyboard order, so nothing hides behind a key you can't see.
    private func list(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let order = Dictionary(MacKeyboard.keys.enumerated().compactMap { i, k in k.code.map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
        let sorted = layer.sorted { (order[$0.code] ?? 999, $0.code) < (order[$1.code] ?? 999, $1.code) }
        return Group {
            if sorted.isEmpty {
                Text(model.flags.isEmpty && model.mode.isEmpty ? "Global shortcuts need ⌥, ⌃ or ⌘ so they don't block typing."
                     : "No shortcuts use \(ConfigDocument.modifierCaps(model.flags).joined()) here yet.")
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(sorted) { a in
                        Button {
                            if MacKeyboard.spec(a.code) != nil { model.selected = a.code }
                        } label: {
                            HStack(spacing: 8) {
                                Keycaps(caps: ConfigDocument.modifierCaps(a.flags) + [ConfigDocument.capLabel(a.key)])
                                    .frame(minWidth: 60, alignment: .leading)
                                Circle().fill(a.category.color).frame(width: 7, height: 7)
                                Text(a.title).lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { model.hovered = $0 ? a.code : (model.hovered == a.code ? nil : model.hovered) }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: 940).frame(maxWidth: .infinity)
        .transaction { $0.animation = nil } // swap layers at once; fading rows overlapped the empty message
    }
}

final class ShortcutMapModel: ObservableObject {
    @Published var mode = ""
    /// Modifiers chosen by clicking.
    @Published var picked: NSEvent.ModifierFlags = []
    /// Modifiers physically held down; they win while held.
    @Published var held: NSEvent.ModifierFlags = []
    @Published var hovered: UInt16?
    @Published var selected: UInt16?
    private var monitor: Any?

    var flags: NSEvent.ModifierFlags { held.isEmpty ? picked : held }

    /// What the keys type on the current keyboard layout, so the map matches the keyboard in front of you.
    private let typed: [UInt16: (base: String, shifted: String?)] = {
        var out: [UInt16: (String, String?)] = [:]
        for k in MacKeyboard.keys {
            guard let code = k.code, case .char = k.label,
                  let base = ConfigDocument.typedCharacter(keyCode: code, flags: []) else { continue }
            out[code] = (base, ConfigDocument.typedCharacter(keyCode: code, flags: .shift))
        }
        return out
    }()

    /// Upper and lower legend for a typing key: one letter, or a shifted symbol over the base one.
    func legends(_ k: MacKeyboard.Key) -> (top: String?, main: String) {
        guard case .char(let base, let shifted) = k.label else { return (nil, "") }
        if let code = k.code, let t = typed[code] {
            if t.base.uppercased() != t.base || t.base.lowercased() != t.base { return (nil, t.base.uppercased()) }
            return (t.shifted == t.base ? nil : t.shifted, t.base)
        }
        return (shifted, base)
    }

    /// A key's name on a keycap, for the hint and popover.
    func legend(_ k: MacKeyboard.Key) -> String {
        switch k.label {
        case .char: legends(k).main
        case .word(let w, _): k.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel) ?? w
        case .function(_, let n): "F\(n)"
        case .arrow: k.code.flatMap { ConfigDocument.keyName(for: $0) }.map(ConfigDocument.capLabel) ?? ""
        case .modifier(let symbol, _, _): symbol
        case .globe: "fn"
        case .space: "Space"
        case .touchID: ""
        }
    }

    /// The combo with the most shortcuts, which is where the map opens.
    func busiest(all: [ConfigDocument.KeyAction]) -> NSEvent.ModifierFlags {
        let counts = Dictionary(grouping: all, by: { $0.flags.rawValue }).mapValues(\.count)
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }.map { NSEvent.ModifierFlags(rawValue: $0.key) } ?? []
    }

    func toggle(_ f: NSEvent.ModifierFlags) {
        held = []
        selected = nil
        withAnimation(.easeOut(duration: 0.15)) { picked.formSymmetricDifference(f) }
    }

    func startWatchingModifiers() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            let f = e.modifierFlags.intersection([.command, .option, .control, .shift])
            if let self, f != self.held {
                if !f.isEmpty { self.selected = nil }
                withAnimation(.easeOut(duration: 0.12)) { self.held = f }
            }
            return e
        }
    }

    func stopWatchingModifiers() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = []
    }
}

// MARK: - Keyboard

/// A MacBook Air keyboard (ANSI), drawn to scale. Sizes are in key units; 1u is one letter key plus its gap.
struct MacKeyboard: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var model: ShortcutMapModel
    /// Shortcuts with the modifiers showing, and every shortcut in the set.
    let layer: [ConfigDocument.KeyAction]
    let all: [ConfigDocument.KeyAction]
    let reveal: (BindRow) -> Void

    enum Label {
        case char(String, String?) // US fallback: base and shifted
        case word(String, trailing: Bool)
        case function(String, Int)
        case modifier(String, String, trailing: Bool)
        case arrow(String)
        case globe, space, touchID
    }

    struct Key: Identifiable {
        let code: UInt16?
        let frame: CGRect
        let label: Label
        var modifier: NSEvent.ModifierFlags = []
        var id: String { "\(frame.minX),\(frame.minY)" }
    }

    static let width: CGFloat = 14.5
    static let functionRow: CGFloat = 0.62
    static let height: CGFloat = functionRow + 5

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
        row(1, [(nil, 2.25, .modifier("⇧", "shift", trailing: false))]
            + chars([(6, "Z", nil), (7, "X", nil), (8, "C", nil), (9, "V", nil), (11, "B", nil), (45, "N", nil), (46, "M", nil),
                     (43, ",", "<"), (47, ".", ">"), (44, "/", "?")])
            + [(nil, 2.25, .modifier("⇧", "shift", trailing: true))])
        row(1, [(nil, 1, .globe), (nil, 1, .modifier("⌃", "control", trailing: false)), (nil, 1, .modifier("⌥", "option", trailing: false)),
                (nil, 1.25, .modifier("⌘", "command", trailing: false)), (49, 5, .space),
                (nil, 1.25, .modifier("⌘", "command", trailing: true)), (nil, 1, .modifier("⌥", "option", trailing: true))])
        // The inverted-T arrows: half-height keys, up and down sharing one slot.
        let ay = y - 1, ax: CGFloat = 11.5
        out += [Key(code: 123, frame: CGRect(x: ax, y: ay + 0.5, width: 1, height: 0.5), label: .arrow("arrowtriangle.left.fill")),
                Key(code: 126, frame: CGRect(x: ax + 1, y: ay, width: 1, height: 0.5), label: .arrow("arrowtriangle.up.fill")),
                Key(code: 125, frame: CGRect(x: ax + 1, y: ay + 0.5, width: 1, height: 0.5), label: .arrow("arrowtriangle.down.fill")),
                Key(code: 124, frame: CGRect(x: ax + 2, y: ay + 0.5, width: 1, height: 0.5), label: .arrow("arrowtriangle.right.fill"))]
        return out
    }()

    static func spec(_ code: UInt16) -> Key? { keys.first { $0.code == code } }

    var body: some View {
        let bound = Dictionary(layer.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let elsewhere = Set(all.map(\.code))
        GeometryReader { g in
            let pad: CGFloat = 0.32
            let unit = g.size.width / (Self.width + pad * 2)
            ZStack(alignment: .topLeading) {
                // The midnight aluminium around the keys, with its recessed well.
                RoundedRectangle(cornerRadius: unit * 0.42, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.28, blue: 0.34), Color(red: 0.19, green: 0.22, blue: 0.27)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: unit * 0.42, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)))
                RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous)
                    .fill(Color(red: 0.13, green: 0.15, blue: 0.19))
                    .frame(width: (Self.width + 0.12) * unit, height: (Self.height + 0.12) * unit)
                    .offset(x: (pad - 0.06) * unit, y: (pad - 0.06) * unit)
                ForEach(Self.keys) { k in
                    let action = k.code.flatMap { bound[$0] }
                    let gap = unit * 0.1
                    KeyCap(key: k, unit: unit, model: model, action: action,
                           hasOthers: action == nil && k.code.map(elsewhere.contains) == true)
                        .frame(width: k.frame.width * unit - gap, height: k.frame.height * unit - gap)
                        .popover(isPresented: Binding(get: { k.code != nil && model.selected == k.code },
                                                      set: { if !$0, model.selected == k.code { model.selected = nil } }),
                                 arrowEdge: .bottom) {
                            if let code = k.code { KeyPopover(doc: doc, model: model, key: k, code: code, reveal: reveal) }
                        }
                        .offset(x: (pad + k.frame.minX) * unit + gap / 2, y: (pad + k.frame.minY) * unit + gap / 2)
                }
            }
        }
        .aspectRatio((Self.width + 0.64) / (Self.height + 0.64), contentMode: .fit)
        .environment(\.colorScheme, .dark)
    }
}

/// One key. Bound keys glow in their action's colour and show its symbol; held modifiers light up.
private struct KeyCap: View {
    let key: MacKeyboard.Key
    let unit: CGFloat
    @ObservedObject var model: ShortcutMapModel
    let action: ConfigDocument.KeyAction?
    /// Unbound with these modifiers, but bound with others: a small dot says there's more to find.
    let hasOthers: Bool

    private static let ink = Color(white: 0.86)

    var body: some View {
        let pressed = !key.modifier.isEmpty && model.flags.contains(key.modifier)
        let hovered = key.code != nil && model.hovered == key.code
        let selected = key.code != nil && model.selected == key.code
        let shape = RoundedRectangle(cornerRadius: unit * 0.12, style: .continuous)
        let interactive = key.code != nil || !key.modifier.isEmpty
        Button {
            if !key.modifier.isEmpty { model.toggle(key.modifier) }
            else if let code = key.code { model.selected = model.selected == code ? nil : code }
        } label: {
            ZStack {
                shape.fill(fill(pressed: pressed))
                shape.fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center))
                shape.strokeBorder(Color.white.opacity(action != nil ? 0.28 : 0.06), lineWidth: 0.75)
                if hovered && interactive { shape.fill(Color.white.opacity(0.08)) }
                legend(pressed: pressed)
                if hasOthers {
                    Circle().fill(Self.ink.opacity(0.45)).frame(width: unit * 0.06, height: unit * 0.06)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(unit * 0.08)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.5), radius: 0, y: unit * 0.025)
            .overlay(shape.strokeBorder(Color.white, lineWidth: selected ? 2 : 0).padding(-1.5))
            .scaleEffect(pressed ? 0.96 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
        .onHover { on in
            guard key.code != nil else { return }
            if on { model.hovered = key.code } else if model.hovered == key.code { model.hovered = nil }
        }
        .animation(.easeOut(duration: 0.15), value: action?.title)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .help(action.map { "\(ConfigDocument.modifierCaps($0.flags).joined())\(model.legend(key)): \($0.title)" } ?? "")
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = model.legend(key)
        if !key.modifier.isEmpty { return "\(name) modifier" }
        guard let action else { return "\(name), no shortcut" }
        return "\(name): \(action.title)"
    }

    private func fill(pressed: Bool) -> AnyShapeStyle {
        if pressed { return AnyShapeStyle(Color.accentColor.gradient) }
        if let action {
            return AnyShapeStyle(LinearGradient(colors: [action.category.color.opacity(0.95), action.category.color.opacity(0.7)],
                                                startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(Color(red: 0.055, green: 0.06, blue: 0.075))
    }

    @ViewBuilder private func legend(pressed: Bool) -> some View {
        let small = Font.system(size: unit * 0.17, weight: .regular)
        let ink = action != nil || pressed ? Color.white : Self.ink
        switch key.label {
        case .char:
            let l = model.legends(key)
            if let action {
                VStack(spacing: unit * 0.02) {
                    Text(l.main).font(.system(size: unit * 0.17, weight: .semibold)).opacity(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: action.symbol).font(.system(size: unit * 0.3, weight: .semibold))
                        .frame(maxHeight: .infinity)
                }
                .foregroundStyle(ink)
                .padding(unit * 0.09)
            } else if let top = l.top {
                VStack(spacing: unit * 0.04) {
                    Text(top).font(.system(size: unit * 0.2))
                    Text(l.main).font(.system(size: unit * 0.24))
                }
                .foregroundStyle(ink)
            } else {
                Text(l.main).font(.system(size: unit * 0.3)).foregroundStyle(ink)
            }
        case .word(let w, let trailing):
            corner(Text(w).font(small), trailing: trailing, ink: ink)
        case .function(let symbol, let n):
            if let action {
                VStack(spacing: 0) {
                    Image(systemName: action.symbol).font(.system(size: unit * 0.2, weight: .semibold))
                    Text("F\(n)").font(.system(size: unit * 0.12))
                }
                .foregroundStyle(ink)
            } else {
                VStack(spacing: unit * 0.04) {
                    Image(systemName: symbol).font(.system(size: unit * 0.15))
                    Text("F\(n)").font(.system(size: unit * 0.12))
                }
                .foregroundStyle(ink)
            }
        case .modifier(let symbol, let name, let trailing):
            VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
                Text(symbol).font(.system(size: unit * 0.2))
                Spacer(minLength: 0)
                Text(name).font(small)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, unit * 0.1).padding(.vertical, unit * 0.08)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailing ? .trailing : .leading)
        case .arrow(let symbol):
            Image(systemName: action?.symbol ?? symbol)
                .font(.system(size: unit * (action == nil ? 0.13 : 0.2), weight: .semibold))
                .foregroundStyle(ink)
        case .globe:
            VStack(alignment: .leading, spacing: 0) {
                Text("fn").font(small).frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 0)
                Image(systemName: "globe").font(.system(size: unit * 0.2))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, unit * 0.1).padding(.vertical, unit * 0.08)
        case .space:
            if let action {
                Label(action.title, systemImage: action.symbol).font(.system(size: unit * 0.2, weight: .semibold)).foregroundStyle(ink)
            }
        case .touchID:
            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1).padding(unit * 0.08)
        }
    }

    /// Wide keys print their name in a bottom corner; with a shortcut its symbol sits on top.
    private func corner(_ text: Text, trailing: Bool, ink: Color) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            if let action {
                Image(systemName: action.symbol).font(.system(size: unit * 0.24, weight: .semibold))
            }
            Spacer(minLength: 0)
            text
        }
        .foregroundStyle(ink)
        .padding(.horizontal, unit * 0.1).padding(.vertical, unit * 0.08)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

// MARK: - Key popover

/// Change, remove or add the shortcut on one key, and see what the key does with other modifiers.
private struct KeyPopover: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var model: ShortcutMapModel
    let key: MacKeyboard.Key
    let code: UInt16
    let reveal: (BindRow) -> Void

    var body: some View {
        let flags = model.flags
        let mine = doc.keyActions(in: model.mode).filter { $0.code == code }
        let here = mine.filter { $0.flags == flags }
        let others = mine.filter { $0.flags != flags }
            .sorted { $0.flags.rawValue < $1.flags.rawValue }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Keycaps(caps: ConfigDocument.modifierCaps(flags) + [model.legend(key)])
                Spacer(minLength: 0)
                Text(model.mode.isEmpty ? "Global" : "\(model.mode.capitalized) mode")
                    .font(Theme.body(11)).foregroundStyle(Theme.secondary)
            }
            if here.isEmpty {
                addSection(flags)
            } else {
                ForEach(here) { a in current(a) }
            }
            if !others.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("With other modifiers").font(Theme.body(11, .semibold)).foregroundStyle(Theme.secondary)
                    ForEach(others) { a in
                        Button {
                            model.held = []
                            withAnimation(.easeOut(duration: 0.15)) { model.picked = a.flags }
                        } label: {
                            HStack(spacing: 8) {
                                Keycaps(caps: ConfigDocument.modifierCaps(a.flags) + [model.legend(key)])
                                Circle().fill(a.category.color).frame(width: 7, height: 7)
                                Text(a.title).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show \(ConfigDocument.modifierCaps(a.flags).joined()) shortcuts")
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    @ViewBuilder private func current(_ a: ConfigDocument.KeyAction) -> some View {
        let i = doc.binds.firstIndex { $0.id == a.row.id }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: a.category.symbol, color: a.category.color, size: 22)
                Text(a.title).font(Theme.body(13, .semibold)).lineLimit(2)
                Spacer(minLength: 0)
            }
            if a.isRange {
                Text("Part of “\(doc.title(a.row))”. Edit its keys in Keyboard Shortcuts.")
                    .font(Theme.body(11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let i, doc.binds[i].dispatcher == "exec" {
                TextField("Command", text: $doc.binds[i].args, prompt: Text("open -na Terminal"))
                    .labelsHidden().textFieldStyle(.roundedBorder).font(Theme.mono(12, .regular))
            }
            if let issue = doc.issue(a.row) {
                Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                    .font(Theme.body(11)).foregroundStyle(issue.severity == .error ? .red : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let i, !a.isRange {
                    Menu {
                        ActionMenuItems { pick in
                            doc.binds[i].dispatcher = pick.dispatcher
                            doc.binds[i].args = pick.args
                        }
                    } label: { Text("Change Action") }
                    .fixedSize()
                    Button("Remove") { withAnimation(.snappy) { doc.binds.removeAll { $0.id == a.row.id } } }
                } else {
                    Button("Edit in Keyboard Shortcuts") { reveal(a.row) }
                }
            }
        }
    }

    @ViewBuilder private func addSection(_ flags: NSEvent.ModifierFlags) -> some View {
        if model.mode.isEmpty && flags.subtracting(.shift).isEmpty {
            Text("Global shortcuts need ⌥, ⌃ or ⌘ so they don't block typing. Pick a modifier first, or use window mode for single keys.")
                .font(Theme.body(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        } else if let name = ConfigDocument.keyName(for: code) {
            Text("No shortcut yet.").foregroundStyle(Theme.secondary)
            Menu {
                ActionMenuItems { a in
                    doc.binds.append(BindRow(mods: doc.modsString(for: flags), key: name, dispatcher: a.dispatcher, args: a.args,
                                             submap: model.mode))
                }
            } label: { Label("Add Shortcut", systemImage: "plus") }
            .fixedSize()
        }
    }
}
