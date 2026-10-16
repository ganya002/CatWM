// Settings: the Shortcuts pane (action catalog, bind rows, shortcut recorder).
import AppKit
import SwiftUI
import MacKeysCore

// MARK: - Shortcuts

/// The action catalog as menu items: a submenu per category, numbered families folded into their own submenu.
enum ActionMenuItems {
    static func items(current: Action? = nil, pick: @escaping (Action) -> Void) -> [MenuItem] {
        func row(_ a: Action, _ title: String) -> MenuItem {
            MenuItem(id: "a.\(a.id)", kind: current == nil ? .action : .radio, label: title, checked: a.id == current?.id,
                     action: { pick(a) })
        }
        func sub(_ id: String, _ label: String, symbol: String?, _ children: [MenuItem]) -> MenuItem {
            MenuItem(id: id, kind: .sub, label: label, symbol: symbol, width: MenuItem.fitWidth(children), children: children)
        }
        return Actions.byCategory.map { cat, actions in
            sub("c.\(cat.rawValue)", cat.rawValue, symbol: cat.symbol, Actions.menuEntries(actions).map { entry in
                switch entry {
                case .action(let a): row(a, a.title)
                case .group(let name, let list): sub("g.\(name)", name, symbol: nil, list.map { row($0, $0.short ?? $0.title) })
                }
            })
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private var keyboardFinishOptions: [(value: String, label: String)] {
        var options = [
            (value: "auto", label: "Auto (this Mac)"),
            (value: "macbook-pro", label: "MacBook Pro (family)"),
            (value: "macbook-air", label: "MacBook Air (family)"),
            (value: "macbook-neo", label: "MacBook Neo (family)"),
            (value: "magic-keyboard", label: "Magic Keyboard (family)"),
        ] + FinishID.allCases.map { (value: MacKeyboard.slug($0.name), label: $0.name) }
        if !options.contains(where: { $0.value == doc.config.keyboardFinish }) {
            options.append((value: doc.config.keyboardFinish, label: doc.config.keyboardFinish))
        }
        return options
    }

    /// How to open keyboard help, from the shortcut that enters window mode right now.
    private var keyboardHelpHint: String {
        let enter = doc.binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && $0.args.lowercased() != "reset" }
        guard let enter, let flags = ConfigDocument.flags(doc.resolvedMods(enter.mods)) else { return "Press \(doc.config.keyboardHelpKey) in window mode" }
        let hold = ConfigDocument.modifierCaps(flags.subtracting(.shift)).joined()
        return hold.isEmpty ? "Press \(doc.config.keyboardHelpKey) in window mode" : "Hold \(hold) after \(doc.prettyShortcut(enter).joined()), or press \(doc.config.keyboardHelpKey) in window mode"
    }

    private func category(_ r: BindRow) -> ActionCategory {
        Actions.match(r)?.category ?? Actions.rangeSummary(r)?.category ?? .custom
    }

    private func matches(_ r: BindRow) -> Bool {
        guard r.submap == ui.bindMode else { return false }
        guard !ui.shortcutFilter.isEmpty else { return true }
        let q = ui.shortcutFilter.lowercased()
        return [doc.title(r), r.dispatcher, r.args, r.key, doc.prettyShortcut(r).joined()].contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        let sections = ActionCategory.allCases.map { cat in (cat, doc.binds.filter { category($0) == cat && matches($0) }) }
            .filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                if doc.submaps.count > 1 {
                    OSegmented(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                               selection: $ui.bindMode)
                        .tooltip("Global shortcuts work everywhere. Mode shortcuts only work in the mode, so single keys are fine.")
                }
                OTextField(placeholder: "Filter shortcuts", text: $ui.shortcutFilter).frame(maxWidth: 200)
                Spacer(minLength: 0)
                addMenu
                OIconButton(symbol: "keyboard", label: "Shortcut map", variant: .secondary) {
                    withAnimation(Motion.snap) { ui.showMap = true }
                }
                .setting("shortcuts.map", ui)
            }
            .setting("shortcuts.list", ui)

            OGroup("Keyboard") {
                OptionSwitch(\.keyboardHelp, doc: doc, ui: ui, description: keyboardHelpHint)
                OptionRow(\Config.keyboardFinish, ui: ui) { label in
                    OMenuPicker(title: label, options: keyboardFinishOptions, selection: $doc.config.keyboardFinish)
                }
            }

            ForEach(sections, id: \.0) { cat, rows in
                OGroup(cat.rawValue) {
                    ForEach(rows) { row in
                        BindRowView(doc: doc, ui: ui, rowID: row.id).setting("bind.\(row.id)", ui)
                    }
                }
            }
            if sections.isEmpty {
                Text(ui.shortcutFilter.isEmpty ? "No shortcuts yet" : "No shortcuts match “\(ui.shortcutFilter)”")
                    .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .onDisappear { ui.recording = nil }
    }

    private var addMenu: some View {
        OMenuButton(style: OButtonStyle(variant: .primary), items: {
            let ranges: [MenuItem] = [
                MenuItem(id: "r.ws", label: "Go to Workspaces 1–10 with 1…0", action: { add("workspace", "1..10", key: "1..0") }),
                MenuItem(id: "r.mv", label: "Move Window to Workspaces 1–10 with 1…0", action: { add("movetoworkspace", "1..10", key: "1..0") }),
                .sep("r.s1"),
                MenuItem(id: "r.fh", label: "Focus with H J K L", action: { add("movefocus", "l|d|u|r", key: "h|j|k|l") }),
                MenuItem(id: "r.fa", label: "Focus with Arrow Keys", action: { add("movefocus", "l|d|u|r", key: "left|down|up|right") }),
                MenuItem(id: "r.mh", label: "Move Window with H J K L", action: { add("movewindow", "l|d|u|r", key: "h|j|k|l") }),
                MenuItem(id: "r.ma", label: "Move Window with Arrow Keys", action: { add("movewindow", "l|d|u|r", key: "left|down|up|right") }),
                .sep("r.s2"),
                MenuItem(id: "r.custom", label: "Custom Range…", action: { add("workspace", "1..5", key: "1..5", expand: true) }),
            ]
            return ActionMenuItems.items { a in add(a.dispatcher, a.args) } + [
                MenuItem(id: "ranges", kind: .sub, label: "Ranges", symbol: "ellipsis.rectangle", width: MenuItem.fitWidth(ranges), children: ranges),
                .sep("s"),
                // Matches no preset, so the raw editor shows.
                MenuItem(id: "custom", label: "Custom Dispatcher…", symbol: "terminal", action: { add("layoutmsg", "") }),
            ]
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(Theme.symbol(Theme.Icon.sm))
                Text("Add Shortcut")
            }
        }
        .fixedSize()
    }

    private func add(_ dispatcher: String, _ args: String, key: String = "", expand: Bool = false) {
        let row = BindRow(mods: ui.bindMode.isEmpty ? doc.modVarName : "", key: key, dispatcher: dispatcher, args: args,
                          submap: ui.bindMode)
        doc.binds.append(row)
        if expand { ui.expanded.insert(row.id) }
        ui.shortcutFilter = ""
        DispatchQueue.main.async { ui.recording = row.id }
    }
}

// MARK: - Bind rows

private struct BindRowView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let rowID: UUID

    private var index: Int? { doc.binds.firstIndex { $0.id == rowID } }

    private func dispatcherOptions(_ current: String) -> [(value: String, label: String)] {
        Actions.dispatchers.map { ($0, $0) } + (Actions.dispatchers.contains(current) ? [] : [(current, current)])
    }

    var body: some View {
        if let i = index {
            let row = doc.binds[i]
            let action = Actions.match(row)
            let issue = doc.issue(row)
            let isRange = BindRange.isRange(row.key)
            let summary = isRange ? Actions.rangeSummary(row) : nil
            // Range rows read like any other row; their keys and values open on demand (or when they're broken).
            let editorOpen = isRange && (ui.expanded.contains(rowID) || summary == nil || issue?.severity == .error)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Recorder(doc: doc, ui: ui, row: row)
                    if isRange {
                        Text(summary?.title ?? "Custom range").font(Theme.body(14)).oneLine(.middle)
                            .foregroundStyle(summary == nil ? Theme.inkMuted : Theme.ink)
                        Spacer(minLength: 0)
                    } else {
                        actionMenu(i, action)
                        if row.dispatcher == "exec" {
                            OTextField(placeholder: "open -na Terminal", text: $doc.binds[i].args, mono: true)
                        } else if action == nil {
                            OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher)
                            OTextField(placeholder: "arguments", text: $doc.binds[i].args, mono: true)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    if let issue {
                        Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .foregroundStyle(issue.severity == .error ? Theme.danger : Theme.warning)
                            .tooltip(issue.message)
                            .accessibilityLabel(issue.message)
                    }
                    if isRange { editToggle(open: editorOpen, locked: summary == nil || issue?.severity == .error) }
                    RemoveButton(help: "Delete shortcut") {
                        withAnimation(Motion.easeOut) { doc.binds.removeAll { $0.id == rowID } }
                        ui.expanded.remove(rowID)
                    }
                }
                if editorOpen {
                    rangeEditor(i, row, valid: issue?.severity != .error)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let issue, issue.severity == .error {
                    Text(issue.message).textStyle(.caption).foregroundStyle(Theme.danger).oneLine()
                        .padding(.leading, Recorder.width + 12)
                }
            }
            .frame(minHeight: 48)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.accentSoft)
                    .padding(.horizontal, -12)
                    .opacity(ui.reveal == rowID ? 1 : 0)
            }
        }
    }

    /// Dispatcher, keys and values of a range row, with what each key ends up doing.
    private func rangeEditor(_ i: Int, _ row: BindRow, valid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher)
                OTextField(placeholder: "1..0", text: $doc.binds[i].key, mono: true).frame(minWidth: 90, maxWidth: 150)
                Image(systemName: "arrow.right").font(Theme.symbol(Theme.Icon.sm, .semibold)).foregroundStyle(Theme.inkMuted)
                    .accessibilityHidden(true)
                OTextField(placeholder: "1..10", text: $doc.binds[i].args, mono: true).frame(minWidth: 90, maxWidth: 150)
                Spacer(minLength: 0)
            }
            if valid {
                Text(rangePreview(row)).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .padding(.leading, Recorder.width + 12)
    }

    private func editToggle(open: Bool, locked: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                if ui.expanded.contains(rowID) { ui.expanded.remove(rowID) } else { ui.expanded.insert(rowID) }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(Theme.symbol(Theme.Icon.sm))
                .foregroundStyle(open ? Theme.accentInk : Theme.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(open ? Theme.accentSoft : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .tooltip(open ? "Hide keys and values" : "Edit keys and values")
        .accessibilityLabel(open ? "Hide keys and values" : "Edit keys and values")
    }

    /// "H → Focus Left · J → Focus Down · …", or the raw values when they aren't catalog actions.
    private func rangePreview(_ row: BindRow) -> String {
        guard case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { return "" }
        let mods = ConfigDocument.flags(doc.resolvedMods(row.mods)).map { ConfigDocument.modifierCaps($0).joined() } ?? ""
        func one(_ p: (key: String, arg: String)) -> String {
            let target = Actions.match(BindRow(mods: "", key: "", dispatcher: row.dispatcher, args: p.arg))?.title
                ?? (p.arg.isEmpty ? row.dispatcher : p.arg)
            return "\(mods)\(ConfigDocument.capLabel(p.key)) → \(target)"
        }
        let shown = pairs.count > 5 ? pairs.prefix(3).map(one) + ["…", one(pairs.last!)] : pairs.map(one)
        return shown.joined(separator: "  ·  ")
    }

    private func actionMenu(_ i: Int, _ action: Action?) -> some View {
        let doc = doc
        return OMenuButton(items: {
            ActionMenuItems.items(current: action) { a in
                guard doc.binds.indices.contains(i) else { return }
                doc.binds[i].dispatcher = a.dispatcher
                if a.dispatcher != "exec" || doc.binds[i].args.isEmpty || action?.dispatcher != "exec" {
                    doc.binds[i].args = a.args
                }
            }
        }) {
            HStack(spacing: 5) {
                Text(action?.title ?? "Custom").font(Theme.body(14)).oneLine()
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.xs, .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .contentShape(Rectangle())
        }
        .fixedSize()
    }
}

// MARK: - Recorder

/// Click to record a shortcut: keycaps on a sunken well, an `accent` outline while listening.
private struct Recorder: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let row: BindRow
    static let width: CGFloat = 150

    var body: some View {
        let recording = ui.recording == row.id
        Button {
            ui.recording = recording ? nil : row.id
        } label: {
            Group {
                if recording {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle").font(Theme.symbol(Theme.Icon.sm, .semibold))
                        Text(BindRange.isRange(row.key) ? "Press modifiers…" : "Press keys…")
                    }
                    .font(Theme.body(12.5, .medium)).foregroundStyle(Theme.accentInk).oneLine()
                } else if row.key.isEmpty {
                    Text("Click to record").font(Theme.body(12.5)).foregroundStyle(Theme.inkFaint).oneLine()
                } else {
                    // Freshly recorded keys drop in with a little bump.
                    Kbd(keys: doc.prettyShortcut(row)).squish(on: row.mods + row.key, anchor: .center)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: Self.width, height: 30, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(recording ? Theme.accentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(recording ? Theme.accent : Theme.hairline,
                              style: StrokeStyle(lineWidth: recording ? 1.5 : 1, dash: row.key.isEmpty && !recording ? [3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(recording ? (row.submap.isEmpty || BindRange.isRange(row.key) ? "Esc cancels" : "Click to cancel")
              : "Click to record a new shortcut")
        .accessibilityLabel(recording ? "Recording shortcut" : "Shortcut \(doc.prettyShortcut(row).joined()). Click to record")
    }
}
