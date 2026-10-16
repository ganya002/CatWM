// Keys: the full-window Shortcut Map for viewing and editing binds per modifier combo.
import AppKit
import SwiftUI

/// Full-window map of the shortcuts on a MacBook keyboard. Pick a modifier combo (or hold the keys
/// down) and every bound key shows what it does with it, coloured by group; click a key to change or
/// add its shortcut. Below, the same layer as a list.
struct ShortcutMap: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @StateObject private var model = ShortcutMapModel()

    var body: some View {
        let all = doc.keyActions(in: model.mode)
        let flags = model.flags
        let layer = all.filter { $0.flags == flags }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(all)
                VStack(alignment: .leading, spacing: 14) {
                    keyboard(layer).zIndex(1) // the key editor hangs over the legend and list
                    legend(all)
                }
                .frame(maxWidth: 940)
                .frame(maxWidth: .infinity)
                .zIndex(1)
                list(layer)
            }
            .padding(.horizontal, 36).padding(.top, 22).padding(.bottom, 40)
        }
        .onAppear {
            model.mode = doc.submaps.contains(ui.bindMode) ? ui.bindMode : ""
            model.picked = model.busiest(all: doc.keyActions(in: model.mode))
            model.startWatching()
        }
        .onDisappear { model.stopWatching() }
        .onChange(of: model.mode) { _, m in
            model.selected = nil
            model.picked = model.busiest(all: doc.keyActions(in: m))
        }
    }

    /// Breadcrumb and title like every pane, Done on the right; below, the modifier picker, the set and the busiest combos.
    private func header(_ all: [ConfigDocument.KeyAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Settings")
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                Text("Shortcuts")
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                Text("Map")
            }
            .font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
            HStack(alignment: .center, spacing: 8) {
                Text("Shortcut Map").font(Theme.display(40)).tracking(-1).oneLine()
                Spacer(minLength: 12)
                if doc.submaps.count > 1 {
                    OSegmented(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                               selection: $model.mode)
                }
                OButton("Done", variant: .primary, shortcut: ["⎋"]) { close() }
                    .keyboardShortcut(model.selected == nil ? .cancelAction : nil) // ⎋ cancels the key editor first
            }
            HStack(spacing: 14) {
                modifierToggles
                Spacer(minLength: 8)
                combos(all)
            }
            .padding(.top, 14)
        }
    }

    /// ⌃ ⌥ ⇧ ⌘ as one track of toggles.
    private var modifierToggles: some View {
        let mods: [(NSEvent.ModifierFlags, String, String)] = [(.control, "⌃", "Control"), (.option, "⌥", "Option"),
                                                               (.shift, "⇧", "Shift"), (.command, "⌘", "Command")]
        return HStack(spacing: 2) {
            ForEach(mods, id: \.1) { flag, symbol, name in
                let on = model.flags.contains(flag)
                Button { model.toggle(flag) } label: {
                    HStack(spacing: 5) {
                        Text(symbol).font(Theme.keys(12.5, .medium))
                        Text(name).font(Theme.body(12.5, on ? .medium : .regular))
                    }
                    .foregroundStyle(on ? Theme.onAccent : Theme.inkMuted)
                    .padding(.horizontal, 11).frame(height: 24)
                    .background(Capsule().fill(on ? Theme.accent : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? [.isSelected, .isToggle] : .isToggle)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.well))
        .animation(Motion.spring, value: model.flags.rawValue)
    }

    /// Jumps to a row in the Shortcuts pane and lights it up.
    private func reveal(_ row: BindRow) {
        model.selected = nil
        ui.bindMode = row.submap
        ui.shortcutFilter = ""
        ui.expanded.insert(row.id)
        ui.reveal = row.id
        ui.pane = .shortcuts
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
        return HStack(spacing: 4) {
            if !list.isEmpty {
                Text("In use").font(Theme.body(12)).foregroundStyle(Theme.inkMuted).padding(.trailing, 4)
            }
            ForEach(list.prefix(5), id: \.flags.rawValue) { item in
                let on = item.flags == model.flags
                let name = item.flags.isEmpty ? "None" : ConfigDocument.modifierCaps(item.flags).joined()
                Button {
                    model.held = []
                    model.selected = nil
                    withAnimation(.easeOut(duration: 0.15)) { model.picked = item.flags }
                } label: {
                    HStack(spacing: 5) {
                        Text(name).font(Theme.keys(12, .medium))
                        Text("\(item.count)").font(Theme.body(11.5)).monospacedDigit()
                            .foregroundStyle(on ? Theme.onAccent.opacity(0.8) : Theme.inkMuted)
                    }
                    .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(on ? Theme.accent : Theme.well))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .tooltip("Show \(name == "None" ? "shortcuts without modifiers" : name + " shortcuts")")
                .accessibilityLabel("\(name), \(item.count) shortcuts")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.flags.rawValue)
    }

    // MARK: Keyboard

    /// The layer written on the keys, with the selected key's editor and the hovered key's tooltip on top.
    private func keyboard(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let one = KeyHintKeyboard.size(scale: 1)
        let codes = Set(layer.map(\.code))
        // Held or picked modifiers wear a white ring, and so do the keys of the list row under the pointer.
        var hot = Set(KeyHintKeyboard.keys.filter { !$0.modifier.isEmpty && model.flags.contains($0.modifier) }.compactMap(\.code))
        if let id = model.hotRow { hot.formUnion(layer.filter { $0.row.id == id }.map(\.code)) }
        let hints = layer.map { KeyHint($0) }
        let pressed = model.pressed.flatMap { codes.contains($0) ? $0 : nil }
        return GeometryReader { g in
            let scale = g.size.width / one.width
            ZStack(alignment: .topLeading) {
                KeyHintKeyboard(binds: hints, pressed: pressed, hot: hot, scale: scale)
                    .onKeyTap(tap)
                    .onKeyHover { k, inside in
                        if k.modifier.isEmpty, let code = k.code { model.hover(code, inside) }
                    }
                if let code = model.selected, let k = KeyHintKeyboard.key(for: code) {
                    // A click anywhere else on the keyboard closes the editor, like a popover.
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: Theme.fast)) { model.selected = nil } }
                    selection(k, code: code, scale: scale, size: g.size, frame: g.frame(in: .global))
                }
                if model.selected == nil, let code = model.tip, let k = KeyHintKeyboard.key(for: code) {
                    tooltip(k, layer: layer, scale: scale, width: g.size.width)
                }
            }
        }
        .aspectRatio(one.width / one.height, contentMode: .fit)
    }

    private func tap(_ k: KeyHintKeyboard.Key) {
        if !k.modifier.isEmpty { model.toggle(k.modifier); return }
        guard let code = k.code else { return }
        model.tip = nil
        model.selected = model.selected == code ? nil : code
    }

    /// A focus ring around the selected key, and its editor below it or above it, whichever has room
    /// in the window (pinned inside the window when neither does), nudged in from the keyboard's edges.
    @ViewBuilder
    private func selection(_ k: KeyHintKeyboard.Key, code: UInt16, scale: CGFloat, size: CGSize, frame: CGRect) -> some View {
        let r = KeyHintKeyboard.rect(of: k, scale: scale)
        let windowHeight = SettingsWindow.shared.window?.contentView?.bounds.height ?? 680
        let h = model.editorHeight, edge: CGFloat = 12
        let roomBelow = windowHeight - edge - (frame.minY + r.maxY + 8)
        let roomAbove = frame.minY + r.minY - 8 - edge
        // Top of the editor in keyboard space.
        let top: CGFloat = h <= roomBelow ? r.maxY + 8
            : h <= roomAbove ? r.minY - 8 - h
            : max(edge, windowHeight - edge - h) - frame.minY
        let w = KeyEditor.width, margin: CGFloat = 20
        let x = min(max(r.midX, w / 2 - margin), size.width - w / 2 + margin)
        RoundedRectangle(cornerRadius: KeyHintKeyboard.cornerRadius(scale: scale) + 2, style: .continuous)
            .strokeBorder(Theme.focus, lineWidth: 2)
            .frame(width: r.width + 4, height: r.height + 4)
            .offset(x: r.minX - 2, y: r.minY - 2)
            .allowsHitTesting(false)
        KeyEditor(doc: doc, model: model, key: k, code: code, flyoutLeading: x + w / 2 + Theme.submenuWidth > size.width + 120,
                  reveal: reveal)
            .id("\(code) \(model.flags.rawValue) \(model.mode)")
            .fixedSize()
            .background(GeometryReader { p in
                Color.clear
                    .onAppear { model.editorHeight = p.size.height }
                    .onChange(of: p.size.height) { _, h in model.editorHeight = h }
            })
            .frame(width: 0, height: 0, alignment: .top)
            .offset(x: x, y: top)
            .transition(.opacity)
    }

    /// What the hovered key does and how to press it, over the key. Nudged in from the window's edges,
    /// with the caret still on the key.
    private func tooltip(_ k: KeyHintKeyboard.Key, layer: [ConfigDocument.KeyAction], scale: CGFloat, width: CGFloat) -> some View {
        let r = KeyHintKeyboard.rect(of: k, scale: scale)
        let action = layer.first { $0.code == k.code }
        var chords = [ConfigDocument.modifierCaps(model.flags) + [KeyHintKeyboard.legend(k)]]
        if let entry = modeEntry { chords.insert(entry, at: 0) }
        let w = model.tipWidth, margin: CGFloat = 28
        let shift = max(0, -margin - (r.midX - w / 2)) + min(0, width + margin - (r.midX + w / 2))
        return OTooltip(text: tooltipText(action: action, code: k.code), chords: chords, caret: .bottomAt(-shift))
            .fixedSize()
            .background(GeometryReader { p in
                Color.clear
                    .onAppear { model.tipWidth = p.size.width }
                    .onChange(of: p.size.width) { _, w in model.tipWidth = w }
            })
            .frame(width: 0, height: 0, alignment: .bottom)
            .offset(x: r.midX + shift, y: r.minY - 8)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func tooltipText(action: ConfigDocument.KeyAction?, code: UInt16?) -> String {
        if let title = action?.title { return title }
        guard let code else { return "No shortcut. Click to add one." }
        if ConfigDocument.keyName(for: code) == nil { return "Can't take a shortcut yet" }
        if model.mode.isEmpty, model.flags.isEmpty { return "Pick a modifier to add a shortcut" }
        return "No shortcut. Click to add one."
    }

    /// The keys that enter the mode on show, e.g. ⌘⇪, so tooltips read "⌘⇪ then L".
    private var modeEntry: [String]? {
        guard !model.mode.isEmpty, let a = doc.keyActions(in: "").first(where: {
            $0.row.dispatcher == "submap" && $0.arg.lowercased() == model.mode.lowercased()
        }) else { return nil }
        return ConfigDocument.modifierCaps(a.flags) + [ConfigDocument.capLabel(a.key)]
    }

    // MARK: Legend and list

    /// The colour groups in this set on one line, and how to use the map.
    private func legend(_ all: [ConfigDocument.KeyAction]) -> some View {
        let present = Set(all.map { KeyHint($0).group })
        return HStack(spacing: 16) {
            ForEach(KeyGroup.allCases.filter(present.contains)) { g in
                HStack(spacing: 6) {
                    Circle().fill(g.color).frame(width: 7, height: 7)
                    Text(g.title).foregroundStyle(Theme.inkMuted).oneLine()
                }
                .fixedSize()
            }
            Spacer(minLength: 12)
            // Whole or shorter, never cut off mid-hint beside a long legend.
            ViewThatFits(in: .horizontal) {
                Text("Hold ⌃ ⌥ ⇧ ⌘ to switch layers, click a key to edit").fixedSize()
                Text("Click a key to edit").fixedSize()
                Color.clear.frame(width: 0)
            }
            .foregroundStyle(Theme.inkFaint)
        }
        .font(Theme.body(12.5))
        .frame(height: 20)
    }

    /// One bind row in the list; a range row's keys stay together.
    private struct Entry: Identifiable {
        let row: BindRow
        let codes: [UInt16]
        let group: KeyGroup
        var id: UUID { row.id }
    }

    /// Every shortcut in the layer by group, in keyboard order, so nothing hides behind a key you can't see.
    private func list(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let order = Dictionary(KeyHintKeyboard.keys.enumerated().compactMap { i, k in k.code.map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
        let rank = { (c: UInt16) in (order[c] ?? 999, c) }
        let entries = Dictionary(grouping: layer, by: { $0.row.id }).values.compactMap { acts -> Entry? in
            let sorted = acts.sorted { rank($0.code) < rank($1.code) }
            guard let first = sorted.first else { return nil }
            return Entry(row: first.row, codes: sorted.map(\.code), group: KeyHint(first).group)
        }
        .sorted { rank($0.codes[0]) < rank($1.codes[0]) }
        let sections = KeyGroup.allCases.compactMap { g -> (group: KeyGroup, rows: [Entry])? in
            let rows = entries.filter { $0.group == g }
            return rows.isEmpty ? nil : (g, rows)
        }
        return Group {
            if sections.isEmpty {
                Text(model.flags.isEmpty && model.mode.isEmpty ? "Global shortcuts need ⌥, ⌃ or ⌘ so they don't block typing."
                     : "No shortcuts use \(ConfigDocument.modifierCaps(model.flags).joined()) here yet.")
                    .font(Theme.body(13)).foregroundStyle(Theme.inkMuted).oneLine()
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 40, alignment: .top)], alignment: .leading, spacing: 28) {
                    ForEach(sections, id: \.group) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                Circle().fill(section.group.color).frame(width: 7, height: 7)
                                Text(section.group.title).font(Theme.body(12, .medium)).tracking(0.24)
                                    .foregroundStyle(Theme.inkMuted).oneLine()
                            }
                            .padding(.bottom, 2)
                            OGroup {
                                ForEach(section.rows) { e in row(e) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 940).frame(maxWidth: .infinity)
        .transaction { $0.animation = nil } // swap layers at once; fading rows overlapped the empty message
    }

    /// Label on the left, its keys on the right. Hovering lights the keys; clicking opens the first one.
    private func row(_ e: Entry) -> some View {
        Button {
            if let first = e.codes.first, KeyHintKeyboard.key(for: first) != nil {
                model.tip = nil
                model.selected = first
            }
        } label: {
            HStack(spacing: 12) {
                Text(doc.title(e.row)).font(Theme.body(13.5)).foregroundStyle(Theme.ink).oneLine()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Kbd(keys: doc.prettyShortcut(e.row)).fixedSize()
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { on in
            if on { model.hotRow = e.id } else if model.hotRow == e.id { model.hotRow = nil }
        }
    }
}

final class ShortcutMapModel: ObservableObject {
    @Published var mode = ""
    /// Modifiers chosen by clicking.
    @Published var picked: NSEvent.ModifierFlags = []
    /// Modifiers physically held down; they win while held.
    @Published var held: NSEvent.ModifierFlags = []
    /// The key under the pointer, and the one whose tooltip shows (after `OTooltip.delay`).
    @Published var hovered: UInt16?
    @Published var tip: UInt16?
    @Published var tipWidth: CGFloat = 0
    /// The key editor's measured height, to place it where it fits in the window.
    @Published var editorHeight: CGFloat = 480
    @Published var selected: UInt16? {
        // Modifier changes are ignored while the editor is open, so catch up with them when it closes.
        didSet { if selected == nil, oldValue != nil { held = NSEvent.modifierFlags.intersection(Self.watched) } }
    }
    /// The key flashing because its shortcut was just pressed.
    @Published var pressed: UInt16?
    /// The list row under the pointer; its keys light up on the keyboard.
    @Published var hotRow: UUID?
    private var monitor: Any?
    private var fireObserver: NSObjectProtocol?
    private var tipTimer: DispatchWorkItem?
    private var flashTimer: DispatchWorkItem?

    var flags: NSEvent.ModifierFlags { held.isEmpty ? picked : held }

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

    /// Tooltips wait `OTooltip.delay` on the first key; once one shows it follows the pointer from key to key.
    func hover(_ code: UInt16, _ inside: Bool) {
        tipTimer?.cancel()
        if inside {
            hovered = code
            if tip != nil { tip = code; return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hovered == code else { return }
                withAnimation(.easeOut(duration: Theme.fast)) { self.tip = code }
            }
            tipTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + OTooltip.delay, execute: work)
        } else if hovered == code {
            hovered = nil
            // A beat before hiding, so sliding onto the next key keeps the tip up.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hovered == nil else { return }
                withAnimation(.easeOut(duration: Theme.fast)) { self.tip = nil }
            }
            tipTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    /// Flashes a key whose shortcut was pressed, if it's on the layer showing. `submap` is nil for a key
    /// that reached the window, which belongs to whichever mode is on show.
    private func flash(_ code: UInt16, flags f: NSEvent.ModifierFlags, submap: String?) {
        guard f == flags, submap.map({ $0 == mode }) ?? true else { return }
        flashTimer?.cancel()
        withAnimation(.easeOut(duration: Theme.fast)) { pressed = code }
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: Theme.slow)) { self?.pressed = nil } }
        flashTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private static let watched: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// Follows held modifiers, and flashes keys as their shortcuts are pressed: ones the window manager
    /// takes arrive through `Hotkeys.didFire`, the rest as key presses in this window.
    func startWatching() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            guard let self else { return e }
            let f = e.modifierFlags.intersection(Self.watched)
            if e.type == .keyDown {
                if self.selected == nil, !e.isARepeat { self.flash(e.keyCode, flags: f, submap: nil) }
            } else if f != self.held, self.selected == nil { // the key editor has its own modifier toggles
                withAnimation(.easeOut(duration: 0.12)) { self.held = f }
            }
            return e
        }
        fireObserver = NotificationCenter.default.addObserver(forName: Hotkeys.didFire, object: nil, queue: .main) { [weak self] n in
            guard let b = n.userInfo?["bind"] as? KeyBinding else { return }
            let f = NSEvent.ModifierFlags(rawValue: UInt(b.mods.rawValue)).intersection(Self.watched)
            self?.flash(b.keyCode, flags: f, submap: b.submap)
        }
    }

    func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let fireObserver { NotificationCenter.default.removeObserver(fireObserver) }
        monitor = nil
        fireObserver = nil
        tipTimer?.cancel()
        held = []
        tip = nil
        hovered = nil
    }
}

// MARK: - Key editor

/// The action menu's categories: one level of nesting over the catalog.
private enum MenuCategory: String, CaseIterable, Identifiable {
    case focus = "Focus", move = "Move", workspace = "Workspace", layout = "Layout", window = "Window", mode = "Mode", app = "App"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .focus: "scope"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .workspace: "square.stack.3d.up"
        case .layout: "rectangle.split.3x1"
        case .window: "macwindow"
        case .mode: "keyboard"
        case .app: "gearshape"
        }
    }

    init(_ a: Action) {
        switch a.category {
        case .focus: self = .focus
        case .move: self = .move
        case .displays: self = a.dispatcher == "focusmonitor" ? .focus : .move
        case .spaces: self = .workspace
        case .layout: self = .layout
        case .window, .commands: self = .window
        case .app, .custom: self = a.dispatcher == "submap" ? .mode : .app
        }
    }
}

/// The edit in progress. Nothing reaches the config until Save.
private final class KeyDraft: ObservableObject {
    @Published var dispatcher: String
    @Published var args: String
    @Published var flags: NSEvent.ModifierFlags
    @Published var mode: String
    @Published var search = ""
    /// The category whose submenu is out.
    @Published var open: MenuCategory?
    /// The bind being edited (nil for a new one), and whether it's one key of a range.
    let row: BindRow?
    let isRange: Bool

    init(_ a: ConfigDocument.KeyAction?, flags: NSEvent.ModifierFlags, mode: String) {
        row = a?.row
        isRange = a?.isRange ?? false
        dispatcher = a?.row.dispatcher ?? ""
        args = a?.arg ?? ""
        self.flags = flags
        self.mode = mode
    }
}

private struct CategoryAnchor: PreferenceKey {
    static var defaultValue: [MenuCategory: Anchor<CGRect>] = [:]
    static func reduce(value: inout [MenuCategory: Anchor<CGRect>], nextValue: () -> [MenuCategory: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Create, change or remove the shortcut on one key: a md Surface with the key itself and its chord
/// on top, the action as a menu nested by category (with search across all of them), compact
/// controls for the action's argument, the modifiers and the set, then Remove, Cancel and Save.
private struct KeyEditor: View {
    static let width: CGFloat = 340
    private static let flyoutWidth: CGFloat = 268

    @ObservedObject var doc: ConfigDocument
    @ObservedObject var model: ShortcutMapModel
    let key: KeyHintKeyboard.Key
    let code: UInt16
    /// Submenus open to the left when there's no room on the right.
    let flyoutLeading: Bool
    let reveal: (BindRow) -> Void
    @StateObject private var draft: KeyDraft
    @FocusState private var searching: Bool

    init(doc: ConfigDocument, model: ShortcutMapModel, key: KeyHintKeyboard.Key, code: UInt16, flyoutLeading: Bool,
         reveal: @escaping (BindRow) -> Void) {
        self.doc = doc
        self.model = model
        self.key = key
        self.code = code
        self.flyoutLeading = flyoutLeading
        self.reveal = reveal
        let here = doc.keyActions(in: model.mode).first { $0.code == code && $0.flags == model.flags }
        _draft = StateObject(wrappedValue: KeyDraft(here, flags: model.flags, mode: model.mode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            hairline
            if draft.isRange, let row = draft.row {
                note("One key of “\(doc.title(row))”", detail: "Its keys are edited together in Shortcuts")
            } else if ConfigDocument.keyName(for: code) == nil {
                note("This key can't take a shortcut yet", detail: nil)
            } else {
                OSearchField(placeholder: "Search actions", text: $draft.search, focus: $searching, onSubmit: pickFirstResult)
                    .padding(.horizontal, 2)
                hairline
                menu
                if hasArgument {
                    hairline
                    argument
                }
                hairline
                options
            }
            if let issue {
                hairline
                OStatus(kind: issue.severity == .error ? .danger : .warning, text: issue.message)
                    .tooltip(issue.message)
                    .padding(.horizontal, 8).frame(height: 34)
            }
            others
            hairline
            actions
        }
        .frame(width: Self.width)
        .surface(.md, glass: true)
        .overlayPreferenceValue(CategoryAnchor.self) { anchors in flyoutLayer(anchors) }
        .onChange(of: draft.search) { _, _ in draft.open = nil }
        .onAppear { DispatchQueue.main.async { searching = !draft.isRange } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shortcut on \(KeyHintKeyboard.legend(key))")
    }

    private var hairline: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private func note(_ text: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(Theme.body(13)).oneLine()
            if let detail { Text(detail).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine() }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
    }

    // MARK: State

    /// Mode actions for every set in the config, in place of the catalog's single Enter Window Mode.
    private var catalog: [Action] {
        var modes = doc.submaps.filter { !$0.isEmpty }
        if !modes.contains(where: { $0.lowercased() == "window" }) { modes.insert("window", at: 0) }
        let enter = modes.map { Action(title: "Enter \($0.capitalized) Mode", category: .app, dispatcher: "submap", args: $0, symbol: "keyboard") }
        let leave = Actions.all.filter { $0.dispatcher == "submap" && $0.args == "reset" }
        return Actions.all.filter { $0.dispatcher != "submap" } + enter + leave
    }

    /// The chosen action, if it's one the menu offers.
    private var action: Action? {
        guard !draft.dispatcher.isEmpty else { return nil }
        if draft.dispatcher == "submap" {
            return catalog.first { $0.dispatcher == "submap" && $0.args.lowercased() == draft.args.lowercased() }
        }
        return Actions.match(BindRow(mods: "", key: "", dispatcher: draft.dispatcher, args: draft.args))
    }

    private var title: String {
        if draft.dispatcher == "exec" { return draft.args.isEmpty ? "Run Command" : "Run “\(draft.args)”" }
        if let action { return action.title }
        if draft.dispatcher.isEmpty { return "New shortcut" }
        return "\(draft.dispatcher) \(draft.args)".trimmingCharacters(in: .whitespaces)
    }

    /// The bind as it would be saved.
    private var candidate: BindRow? {
        guard let name = ConfigDocument.keyName(for: code), !draft.dispatcher.isEmpty, !draft.isRange else { return nil }
        var r = draft.row ?? BindRow(mods: "", key: name, dispatcher: "", args: "")
        // Untouched modifiers keep how they were written ($mod stays $mod).
        if draft.row == nil || draft.flags != model.flags { r.mods = doc.modsString(for: draft.flags) }
        r.dispatcher = draft.dispatcher
        r.args = draft.args
        r.submap = draft.mode
        return r
    }

    private var issue: (severity: ConfigDocument.Severity, message: String)? { candidate.flatMap { doc.issue($0) } }

    private var changed: Bool {
        guard let row = draft.row, let c = candidate else { return true }
        return c.mods != row.mods || c.dispatcher != row.dispatcher || c.args != row.args || c.submap != row.submap
    }

    private var canSave: Bool { candidate != nil && issue?.severity != .error && changed }

    // MARK: Head

    /// The key as it is on the keyboard (wearing the new action), and how to press it.
    private var head: some View {
        let capScale = min(1, 96 / key.frame.width)
        let preview = draft.dispatcher.isEmpty ? nil : KeyHint(code: code, dispatcher: draft.dispatcher, arg: draft.args, title: title)
        var chords = [ConfigDocument.modifierCaps(draft.flags) + [KeyHintKeyboard.legend(key)]]
        if let entry = modeEntry(draft.mode) { chords.insert(entry, at: 0) }
        return HStack(spacing: 12) {
            KeyHintKeyboard.keycap(key, hint: preview, scale: capScale)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Theme.heading(14)).oneLine()
                    .foregroundStyle(draft.dispatcher.isEmpty ? Theme.inkMuted : Theme.ink)
                HStack(spacing: 5) {
                    ForEach(Array(chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").font(Theme.body(11.5)).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 10)
        .animation(.easeOut(duration: Theme.fast), value: title)
    }

    /// The keys that enter a mode, e.g. ⌘⇪, so the chord reads "⌘⇪ then L".
    private func modeEntry(_ mode: String) -> [String]? {
        guard !mode.isEmpty, let a = doc.keyActions(in: "").first(where: {
            $0.row.dispatcher == "submap" && $0.arg.lowercased() == mode.lowercased()
        }) else { return nil }
        return ConfigDocument.modifierCaps(a.flags) + [ConfigDocument.capLabel(a.key)]
    }

    // MARK: Menu

    @ViewBuilder private var menu: some View {
        let query = draft.search.trimmingCharacters(in: .whitespaces)
        VStack(spacing: 0) {
            if query.isEmpty {
                ForEach(MenuCategory.allCases) { categoryRow($0) }
            } else {
                let hits = results(query)
                ForEach(hits) { a in
                    MenuRow(action: { pick(a) }) {
                        symbol(a.symbol)
                        Text(a.title).oneLine()
                        Spacer(minLength: 8)
                        Text(MenuCategory(a).rawValue).foregroundStyle(Theme.inkFaint).oneLine().fixedSize()
                    }
                }
                if hits.isEmpty {
                    Text("No actions match “\(query)”").foregroundStyle(Theme.inkMuted).oneLine()
                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Every word of the query in the title (or the category), best eight.
    private func results(_ query: String) -> [Action] {
        let words = query.lowercased().split(separator: " ")
        return Array(catalog.filter { a in
            let text = (a.title + " " + MenuCategory(a).rawValue).lowercased()
            return words.allSatisfy { text.contains($0) }
        }.prefix(8))
    }

    private func pickFirstResult() {
        let query = draft.search.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { save() } else if let first = results(query).first { pick(first) }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkMuted).frame(width: 18)
    }

    /// A category, with the chosen action on its right when it's in there. Hover or click opens its submenu.
    private func categoryRow(_ c: MenuCategory) -> some View {
        let current = action.map(MenuCategory.init) == c
        return MenuRow(highlighted: draft.open == c, action: { draft.open = draft.open == c ? nil : c }) {
            symbol(c.symbol)
            Text(c.rawValue).oneLine().fixedSize()
            Spacer(minLength: 8)
            if current, let a = action {
                Text(a.title).foregroundStyle(Theme.accentInk).oneLine()
            }
            Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.inkFaint)
        }
        .onHover { if $0 { draft.open = c } }
        .anchorPreference(key: CategoryAnchor.self, value: .bounds) { [c: $0] }
        .accessibilityLabel("\(c.rawValue) actions")
    }

    private func flyoutLayer(_ anchors: [MenuCategory: Anchor<CGRect>]) -> some View {
        GeometryReader { g in
            if let c = draft.open, let a = anchors[c] {
                let r = g[a]
                flyout(c)
                    .fixedSize()
                    .offset(x: flyoutLeading ? -Self.flyoutWidth - 2 : g.size.width + 2, y: r.minY - 4)
                    .transition(.opacity)
            }
        }
    }

    /// One category's actions; numbered families (workspaces, layouts) are one row each, with the
    /// number picked inline afterwards.
    private func flyout(_ c: MenuCategory) -> some View {
        VStack(spacing: 0) {
            ForEach(Actions.menuEntries(catalog.filter { MenuCategory($0) == c })) { entry in
                switch entry {
                case .action(let a):
                    MenuRow(action: { pick(a) }) {
                        symbol(a.symbol)
                        Text(a.title).oneLine()
                        Spacer(minLength: 8)
                        if isCurrent(a) { check }
                    }
                case .group(let name, let list):
                    MenuRow(action: { pick(list.first(where: isCurrent) ?? list[0]) }) {
                        symbol(list[0].symbol)
                        Text(name).oneLine()
                        Spacer(minLength: 8)
                        if list.contains(where: isCurrent) { check } else {
                            Text("\(list.count)").foregroundStyle(Theme.inkFaint).monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(width: Self.flyoutWidth)
        .surface(.md, glass: true)
    }

    private var check: some View {
        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accentInk)
    }

    private func isCurrent(_ a: Action) -> Bool {
        guard let action else { return false }
        return action.dispatcher == a.dispatcher && action.args == a.args
    }

    private func pick(_ a: Action) {
        let wasExec = draft.dispatcher == "exec"
        draft.dispatcher = a.dispatcher
        if a.dispatcher != "exec" { draft.args = a.args } else if !wasExec { draft.args = "" }
        draft.open = nil
        draft.search = ""
        // The click on a menu row drops focus; without this typing lands in the sidebar's search.
        if a.dispatcher != "exec" { searching = true }
    }

    // MARK: Argument and options

    private var hasArgument: Bool {
        draft.dispatcher == "exec" || action?.group != nil || (action == nil && !draft.dispatcher.isEmpty)
    }

    /// The command to run, the number in a family, or the raw dispatcher of a bind the menu doesn't know.
    @ViewBuilder private var argument: some View {
        HStack(spacing: 10) {
            if draft.dispatcher == "exec" {
                Text("Command").foregroundStyle(Theme.inkMuted).oneLine().fixedSize()
                OTextField(placeholder: "open -na Terminal", text: $draft.args, mono: true, autofocus: true)
            } else if let a = action, let group = a.group {
                let family = catalog.filter { $0.group == group }
                Text(group).oneLine()
                Spacer(minLength: 8)
                OMenuPicker(title: group, options: family.map { ($0.id, $0.short ?? $0.title) },
                            selection: Binding(get: { a.id }, set: { id in if let f = family.first(where: { $0.id == id }) { pick(f) } }))
            } else {
                Text("\(draft.dispatcher) \(draft.args)").font(Theme.mono(12)).oneLine()
                Spacer(minLength: 8)
                if let row = draft.row { OButton("Edit in Shortcuts", size: .sm) { reveal(row) } }
            }
        }
        .font(Theme.body(13))
        .padding(.horizontal, 8).frame(minHeight: 40)
        .onHover { if $0 { draft.open = nil } }
    }

    private var options: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Modifiers").foregroundStyle(Theme.inkMuted).oneLine()
                Spacer(minLength: 8)
                modifierToggles
            }
            .frame(height: 38)
            if doc.submaps.count > 1 {
                hairline
                HStack(spacing: 10) {
                    Text("Shortcut set").foregroundStyle(Theme.inkMuted).oneLine()
                    Spacer(minLength: 8)
                    OMenuPicker(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                                selection: $draft.mode)
                }
                .frame(height: 40)
            }
        }
        .font(Theme.body(13))
        .padding(.horizontal, 8)
        .onHover { if $0 { draft.open = nil } }
    }

    /// ⌃ ⌥ ⇧ ⌘ for this shortcut, as one track of toggles.
    private var modifierToggles: some View {
        let mods: [(NSEvent.ModifierFlags, String, String)] = [(.control, "⌃", "Control"), (.option, "⌥", "Option"),
                                                               (.shift, "⇧", "Shift"), (.command, "⌘", "Command")]
        return HStack(spacing: 2) {
            ForEach(mods, id: \.1) { flag, symbol, name in
                let on = draft.flags.contains(flag)
                Button { withAnimation(Motion.spring) { draft.flags.formSymmetricDifference(flag) } } label: {
                    Text(symbol).font(Theme.keys(12.5, .medium))
                        .foregroundStyle(on ? Theme.onAccent : Theme.inkMuted)
                        .frame(width: 30, height: 22)
                        .background(Capsule().fill(on ? Theme.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .tooltip(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? [.isSelected, .isToggle] : .isToggle)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.well))
        .fixedSize()
    }

    /// What the key does with other modifiers in this set; a click shows that layer.
    @ViewBuilder private var others: some View {
        let list = doc.keyActions(in: model.mode).filter { $0.code == code && $0.flags != model.flags }
            .sorted { $0.flags.rawValue < $1.flags.rawValue }
        if !list.isEmpty {
            hairline
            VStack(alignment: .leading, spacing: 0) {
                Text("With other modifiers").font(Theme.body(12, .medium)).foregroundStyle(Theme.inkMuted).oneLine()
                    .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                ForEach(list.prefix(4)) { a in
                    MenuRow(action: {
                        model.held = []
                        withAnimation(.easeOut(duration: 0.15)) { model.picked = a.flags }
                    }) {
                        Kbd(keys: ConfigDocument.modifierCaps(a.flags) + [KeyHintKeyboard.legend(key)]).fixedSize()
                        Circle().fill(KeyHint(a).group.color).frame(width: 7, height: 7)
                        Text(a.title).oneLine()
                        Spacer(minLength: 0)
                    }
                    .tooltip("Show \(ConfigDocument.modifierCaps(a.flags).joined()) shortcuts")
                }
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 6) {
            if let row = draft.row, !draft.isRange {
                OButton("Remove", variant: .ghostDanger, size: .sm) { remove(row) }
            }
            Spacer(minLength: 8)
            OButton("Cancel", size: .sm) { close() }
                .keyboardShortcut(.cancelAction)
            if draft.isRange, let row = draft.row {
                OButton("Edit in Shortcuts", icon: "arrow.right", variant: .primary, size: .sm) { reveal(row) }
            } else {
                OButton("Save", variant: .primary, size: .sm, shortcut: ["↩"]) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 4)
    }

    private func close() {
        withAnimation(.easeOut(duration: Theme.fast)) { model.selected = nil }
    }

    private func remove(_ row: BindRow) {
        withAnimation(Motion.easeOut) { doc.binds.removeAll { $0.id == row.id } }
        close()
    }

    /// Writes the bind, then shows the layer and set it landed in.
    private func save() {
        guard canSave, let r = candidate else { return }
        if let i = doc.binds.firstIndex(where: { $0.id == r.id }) { doc.binds[i] = r } else { doc.binds.append(r) }
        let flags = draft.flags, mode = draft.mode
        close()
        if mode != model.mode {
            model.mode = mode
            DispatchQueue.main.async { model.held = []; model.picked = flags } // after the set change picks its busiest layer
        } else if flags != model.flags {
            model.held = []
            withAnimation(.easeOut(duration: 0.15)) { model.picked = flags }
        }
    }
}

/// A menu row: label on a rounded hover fill, the full width of the surface.
private struct MenuRow<Label: View>: View {
    var highlighted = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { label }
                .font(Theme.body(13)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 8).frame(height: Theme.rowHeight)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(hover.on || highlighted ? Theme.wellHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}
