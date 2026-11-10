import AppKit
import CatWMKit
import MacKeysCore
import SwiftUI

struct ShortcutsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI

    private func category(_ row: BindRow) -> ActionCategory {
        Actions.match(row)?.category ?? Actions.rangeSummary(row)?.category ?? .custom
    }

    private func matches(_ row: BindRow) -> Bool {
        guard row.submap == settingsUI.shortcutMode(in: doc) else { return false }
        guard !settingsUI.shortcutFilter.isEmpty else { return true }
        let query = settingsUI.shortcutFilter.lowercased()
        return [doc.title(row), row.dispatcher, row.args, row.key, doc.prettyShortcut(row).joined()].contains {
            $0.lowercased().contains(query)
        }
    }

    var body: some View {
        let sections = ActionCategory.allCases
            .map { cat in (cat, doc.binds.filter { category($0) == cat && matches($0) }) }
            .filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            HStack(spacing: Theme.Space.medium) {
                addMenu
                if doc.submaps.count > 1 {
                    OSegmented(title: "Shortcut set",
                               options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                               selection: Binding(
                                   get: { settingsUI.shortcutMode(in: doc) },
                                   set: { settingsUI.bindMode = $0 }))
                }
                OTextField(placeholder: "Filter shortcuts", text: $settingsUI.shortcutFilter).frame(maxWidth: 200)
                Spacer(minLength: 0)
                OIconButton(symbol: "keyboard", label: "Shortcut map", variant: .secondary) {
                    withAnimation(Motion.snap) { settingsUI.showMap = true }
                }
                .setting(ShortcutsPane.searchMap.id, settingsUI)
            }
            .setting(ShortcutsPane.searchList.id, settingsUI)

            OGroup("Keyboard") {
                OptionRows(pane: .shortcuts, section: "Keyboard", doc: doc, settingsUI: settingsUI)
            }

            AdditionalOptionGroups(pane: .shortcuts, doc: doc, settingsUI: settingsUI)
            if !OptionRows.additionalSections(pane: .shortcuts, advanced: true).isEmpty {
                AdvancedSection(pane: .shortcuts, settingsUI: settingsUI) {
                    AdditionalOptionGroups(pane: .shortcuts, advanced: true, doc: doc, settingsUI: settingsUI)
                }
            }

            ForEach(sections, id: \.0) { cat, rows in
                OGroup(cat.rawValue) {
                    ForEach(rows) { row in
                        BindRowView(doc: doc, settingsUI: settingsUI, rowID: row.id)
                            .setting("bind.\(row.id)", settingsUI)
                    }
                }
            }
            if sections.isEmpty {
                Text(settingsUI.shortcutFilter.isEmpty
                     ? "No shortcuts yet"
                     : "No shortcuts match “\(settingsUI.shortcutFilter)”")
                    .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .onDisappear { settingsUI.recording = nil }
    }

    private var addMenu: some View {
        OMenuButton(style: OButtonStyle(variant: .primary), items: {
            let ranges: [MenuItem] = [
                MenuItem(id: "r.ws", label: "Go to Workspaces 1–10 with 1…0",
                         action: { add("workspace", "1..10", key: "1..0") }),
                MenuItem(id: "r.mv", label: "Move Window to Workspaces 1–10 with 1…0",
                         action: { add("movetoworkspace", "1..10", key: "1..0") }),
                .sep("r.s1"),
                MenuItem(id: "r.fh", label: "Focus with H J K L",
                         action: { add("movefocus", "l|d|u|r", key: "h|j|k|l") }),
                MenuItem(id: "r.fa", label: "Focus with Arrow Keys",
                         action: { add("movefocus", "l|d|u|r", key: "left|down|up|right") }),
                MenuItem(id: "r.mh", label: "Move Window with H J K L",
                         action: { add("movewindow", "l|d|u|r", key: "h|j|k|l") }),
                MenuItem(id: "r.ma", label: "Move Window with Arrow Keys",
                         action: { add("movewindow", "l|d|u|r", key: "left|down|up|right") }),
                .sep("r.s2"),
                MenuItem(id: "r.custom", label: "Custom Range…",
                         action: { add("workspace", "1..5", key: "1..5", expand: true) })
            ]
            return ActionMenuItems.items { action in add(action.dispatcher, action.args) } + [
                MenuItem(id: "ranges", kind: .sub, label: "Ranges",
                         width: MenuItem.fitWidth(ranges), children: ranges),
                .sep("s"),
                MenuItem(id: "custom", label: "Custom Dispatcher…",
                         action: { add("layoutmsg", "") })
            ]
        }, label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(Theme.symbol(Theme.Icon.small))
                Text("Add Shortcut")
            }
        })
        .fixedSize()
    }

    private func add(_ dispatcher: String, _ args: String, key: String = "", expand: Bool = false) {
        let mode = settingsUI.shortcutMode(in: doc)
        let row = BindRow(mods: mode.isEmpty ? doc.modVarName : "", key: key, dispatcher: dispatcher,
                          args: args, submap: mode)
        doc.binds.append(row)
        if expand { settingsUI.expanded.insert(row.id) }
        settingsUI.shortcutFilter = ""
        DispatchQueue.main.async { settingsUI.recording = row.id }
    }
}

extension ShortcutsPane {
    static let searchList = SettingEntry(id: "shortcuts.list", title: "Keyboard shortcuts", pane: .shortcuts,
                                         keywords: "keybinds hotkeys bind")
    static let searchMap = SettingEntry(id: "shortcuts.map", title: "Shortcut map", pane: .shortcuts,
                                        keywords: "keyboard overview")
}
