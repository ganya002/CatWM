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
                    keyboard(layer)
                    legend(all)
                }
                .frame(maxWidth: 940)
                .frame(maxWidth: .infinity)
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
                    .keyboardShortcut(.cancelAction)
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
        .background(Capsule().fill(Theme.surfaceSunken))
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
                    .background(Capsule().fill(on ? Theme.accent : Theme.surfaceSunken))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .help("Show \(name == "None" ? "shortcuts without modifiers" : name + " shortcuts")")
                .accessibilityLabel("\(name), \(item.count) shortcuts")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.flags.rawValue)
    }

    // MARK: Keyboard

    /// The layer written on the keys, with the selected key's popover and the hovered key's tooltip on top.
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
                KeyHintKeyboard(binds: hints, style: .labels, pressed: pressed, hot: hot, scale: scale)
                    .onKeyTap(tap)
                    .onKeyHover { k, inside in
                        if k.modifier.isEmpty, let code = k.code { model.hover(code, inside) }
                    }
                if let code = model.selected, let k = KeyHintKeyboard.key(for: code) {
                    selection(k, code: code, scale: scale)
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

    /// A focus ring around the selected key, anchoring its popover.
    private func selection(_ k: KeyHintKeyboard.Key, code: UInt16, scale: CGFloat) -> some View {
        let r = KeyHintKeyboard.rect(of: k, scale: scale)
        return RoundedRectangle(cornerRadius: KeyHintKeyboard.unit * scale * 0.12 + 2, style: .continuous)
            .strokeBorder(Theme.focus, lineWidth: 2)
            .frame(width: r.width + 4, height: r.height + 4)
            .popover(isPresented: Binding(get: { model.selected == code },
                                          set: { if !$0, model.selected == code { model.selected = nil } }),
                     arrowEdge: .bottom) {
                KeyPopover(doc: doc, model: model, key: k, code: code, reveal: reveal)
            }
            .offset(x: r.minX - 2, y: r.minY - 2)
            .allowsHitTesting(false)
            .id(code)
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
        return OTooltip(text: action?.title ?? "No shortcut. Click to add one.", chords: chords, caret: .bottomAt(-shift))
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
            Text("Hold ⌃ ⌥ ⇧ ⌘ to switch layers, click a key to edit").foregroundStyle(Theme.inkFaint).oneLine()
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
    @Published var selected: UInt16?
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
            } else if f != self.held {
                if !f.isEmpty { self.selected = nil }
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

// MARK: - Key popover

/// Change, remove or add the shortcut on one key, and see what the key does with other modifiers.
private struct KeyPopover: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var model: ShortcutMapModel
    let key: KeyHintKeyboard.Key
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
                Kbd(keys: ConfigDocument.modifierCaps(flags) + [KeyHintKeyboard.legend(key)])
                Spacer(minLength: 0)
                Text(model.mode.isEmpty ? "Global" : "\(model.mode.capitalized) mode").kicker(Theme.inkMuted)
            }
            if here.isEmpty {
                addSection(flags)
            } else {
                ForEach(here) { a in current(a) }
            }
            if !others.isEmpty {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("With other modifiers").font(Theme.body(12, .medium)).foregroundStyle(Theme.inkMuted)
                        .padding(.bottom, 4)
                    ForEach(others) { a in
                        Button {
                            model.held = []
                            withAnimation(.easeOut(duration: 0.15)) { model.picked = a.flags }
                        } label: {
                            HStack(spacing: 8) {
                                Kbd(keys: ConfigDocument.modifierCaps(a.flags) + [KeyHintKeyboard.legend(key)])
                                Circle().fill(KeyHint(a).group.color).frame(width: 7, height: 7)
                                Text(a.title).font(Theme.body(13)).oneLine()
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show \(ConfigDocument.modifierCaps(a.flags).joined()) shortcuts")
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private func current(_ a: ConfigDocument.KeyAction) -> some View {
        let i = doc.binds.firstIndex { $0.id == a.row.id }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: a.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.surface)
                    .frame(width: 26, height: 26).background(Circle().fill(KeyHint(a).group.color))
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.title).font(Theme.heading()).oneLine()
                    Text(a.category.rawValue).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                Spacer(minLength: 0)
            }
            if a.isRange {
                Text("Part of “\(doc.title(a.row))”. Edit its keys in Shortcuts.")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            } else if let i, doc.binds[i].dispatcher == "exec" {
                OTextField(placeholder: "open -na Terminal", text: $doc.binds[i].args, mono: true)
            }
            if let issue = doc.issue(a.row) {
                OStatus(kind: issue.severity == .error ? .danger : .warning, text: issue.message)
            }
            HStack(spacing: 8) {
                if let i, !a.isRange {
                    Menu {
                        ActionMenuItems { pick in
                            doc.binds[i].dispatcher = pick.dispatcher
                            doc.binds[i].args = pick.args
                        }
                    } label: {
                        Text("Change Action").font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 11).frame(height: 26)
                            .background(Capsule().fill(Theme.surfaceSunken))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    OButton("Remove", variant: .danger, size: .sm) {
                        withAnimation(Motion.easeOut) { doc.binds.removeAll { $0.id == a.row.id } }
                    }
                } else {
                    OButton("Edit in Shortcuts", icon: "arrow.right", size: .sm) { reveal(a.row) }
                }
            }
        }
    }

    @ViewBuilder private func addSection(_ flags: NSEvent.ModifierFlags) -> some View {
        if model.mode.isEmpty && flags.subtracting(.shift).isEmpty {
            Text("Global shortcuts need ⌥, ⌃ or ⌘ so they don't block typing. Pick a modifier first, or use window mode for single keys.")
                .font(Theme.body(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        } else if let name = ConfigDocument.keyName(for: code) {
            Text("No shortcut yet").font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted)
            Menu {
                ActionMenuItems { a in
                    doc.binds.append(BindRow(mods: doc.modsString(for: flags), key: name, dispatcher: a.dispatcher, args: a.args,
                                             submap: model.mode))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11.5, weight: .semibold))
                    Text("Add Shortcut")
                }
                .font(Theme.body(12.5, .medium)).foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 11).frame(height: 26)
                .background(Capsule().fill(Theme.accent))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }
}
