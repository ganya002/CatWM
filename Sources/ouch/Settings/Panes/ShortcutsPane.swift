import AppKit
import SwiftUI
import MacKeysCore

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
