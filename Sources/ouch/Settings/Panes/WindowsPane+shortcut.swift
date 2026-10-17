import AppKit
import SwiftUI

extension WindowsPane {
    @ViewBuilder var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Focus") {
                OptionRows(pane: .windows, section: "Focus", doc: doc, ui: ui)
            }

            OGroup("Mouse") {
                OptionRows(pane: .windows, section: "Mouse", doc: doc, ui: ui)
            }

            OGroup("Pointer menu") {
                OptionRows(pane: .windows, section: "Pointer menu", doc: doc, ui: ui)
                if doc.config.cursorActions {
                    ForEach(pointerShortcuts) { spec in pointerShortcutRow(spec) }
                }
            }

            OGroup("Floating") {
                OptionRows(pane: .windows, section: "Floating", doc: doc, ui: ui)
                if doc.config.floating.isEmpty {
                    ORow("No apps yet", description: "Add one that's running, or by bundle ID under Advanced") { addMenu }
                } else {
                    ForEach(doc.config.floating, id: \.self) { id in
                        HStack(spacing: 12) {
                            appIcon(id)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appName(id) ?? id).font(Theme.body(14)).oneLine()
                                if appName(id) != nil { Text(id).font(Theme.mono(11, .regular)).foregroundStyle(Theme.inkMuted).oneLine(.middle) }
                            }
                            Spacer(minLength: 0)
                            RemoveButton(help: "Remove \(appName(id) ?? id)") {
                                withAnimation(Motion.easeOut) { doc.config.floating.removeAll { $0 == id } }
                            }
                        }
                        .frame(minHeight: 48).padding(.vertical, 6)
                    }
                    HStack { Spacer(); addMenu }.padding(.vertical, 10)
                }
            }

            OGroup("Workspaces") {
                OptionRows(pane: .windows, section: "Workspaces", doc: doc, ui: ui)
            }

            AdditionalOptionGroups(pane: .windows, doc: doc, ui: ui)

            AdvancedSection(pane: .windows, ui: ui) {
                OGroup("Windows") {
                    OptionRows(pane: .windows, section: "Windows", advanced: true, doc: doc, ui: ui)
                    ORow(WindowsPane.searchBundleID.title, description: "Wildcards like com.adobe.* work too") {
                        OTextField(placeholder: "com.example.app", text: $ui.newID, mono: true, onSubmit: add).frame(width: 190)
                        OButton("Add", size: .sm, action: add)
                            .disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .setting(WindowsPane.searchBundleID.id, ui)
                }
                OGroup("Workspaces") {
                    OptionRows(pane: .windows, section: "Workspaces", advanced: true, doc: doc, ui: ui)
                    ORow(WindowsPane.searchHome.title, description: WindowManager.shared.homeSpaceSummary.isEmpty ? "The Desktop you're on when Ouch starts"
                        : "Workspaces live on \(WindowManager.shared.homeSpaceSummary)") {
                        OButton("Use This Desktop", size: .sm) { WindowManager.shared.makeCurrentSpaceHome() }
                    }
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting(WindowsPane.searchHome.id, ui)
                }
                AdditionalOptionGroups(pane: .windows, advanced: true, doc: doc, ui: ui)
            }
        }
    }

    func shortcut(for spec: CursorShortcutSpec) -> ConfigDocument.KeyAction? {
        doc.keyActions(in: windowMode).first {
            $0.code < 0x1000 && (spec.nextWorkspace
                ? Actions.isNextWorkspace($0.row.dispatcher, $0.arg)
                : Actions.same($0.row.dispatcher, $0.arg, spec.dispatcher, spec.args))
        }
    }

    func pointerShortcutRow(_ spec: CursorShortcutSpec) -> some View {
        let hit = shortcut(for: spec)
        return ORow(spec.title) {
            if let hit {
                let caps = ConfigDocument.modifierCaps(hit.flags) + [ConfigDocument.capLabel(hit.key)]
                Button {
                    ui.open(SettingEntry(id: "bind.\(hit.row.id)", title: doc.title(hit.row), pane: .shortcuts, bind: hit.row))
                } label: { Kbd(keys: caps) }
                    .buttonStyle(.plain)
                    .tooltip("Edit in Shortcuts")
                    .accessibilityLabel("Shortcut \(caps.joined(separator: " ")) for \(spec.title)")
            } else {
                OButton("Add", size: .sm) { addShortcut(spec) }
                    .accessibilityLabel("Add a shortcut for \(spec.title)")
            }
        }
    }

    func unfinishedShortcut(_ spec: CursorShortcutSpec) -> BindRow? {
        doc.binds.first { row in
            guard row.submap == windowMode else { return false }
            let matches = spec.nextWorkspace
                ? Actions.isNextWorkspace(row.dispatcher, row.args)
                : Actions.same(row.dispatcher, row.args, spec.dispatcher, spec.args)
            guard matches else { return false }
            guard case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { return true }
            return !pairs.contains { keyCodes[$0.key.lowercased()] != nil }
        }
    }

}
