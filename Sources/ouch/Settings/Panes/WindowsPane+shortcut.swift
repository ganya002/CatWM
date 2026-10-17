import AppKit
import SwiftUI

extension WindowsPane {
    @ViewBuilder var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Focus") {
                OptionSwitch(\.focusFollowsMouse, doc: doc, ui: ui)
                OptionSwitch(\.focusFollowsMouseInModeOnly, doc: doc, ui: ui)
                    .disabled(!doc.config.focusFollowsMouse)
                OptionSwitch(\.mouseFollowsFocus, doc: doc, ui: ui)
                OptionSwitch(\.dimOtherWindows, doc: doc, ui: ui)
                OptionSlider(\.dimStrength, doc: doc, ui: ui, format: { "\(Int($0))%" })
                    .disabled(!doc.config.dimOtherWindows)
                OptionSwitch(\.blurOtherWindows, doc: doc, ui: ui)
                OptionSlider(\.blurRadius, doc: doc, ui: ui, format: { "\(Int($0)) pt" })
                    .disabled(!doc.config.blurOtherWindows)
            }

            OGroup("Mouse") {
                OptionSwitch(\.mouseSwapsWindows, doc: doc, ui: ui)
                OptionSwitch(\.mouseResizesWindows, doc: doc, ui: ui)
            }

            OGroup("Pointer menu") {
                OptionSwitch(\.cursorActions, doc: doc, ui: ui)
                if doc.config.cursorActions {
                    ForEach(pointerShortcuts) { spec in pointerShortcutRow(spec) }
                }
            }

            OGroup("Floating") {
                OptionRow(\Config.floatingIsBlacklist, ui: ui,
                          description: doc.config.floatingIsBlacklist ? "Float; everything else tiles" : "Are the only ones that tile") { label in
                    OSegmented(title: label, options: [(true, "Float"), (false, "Tile")], selection: $doc.config.floatingIsBlacklist)
                }
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
                OptionSwitch(\.virtualWorkspaces, doc: doc, ui: ui)
                OptionRow(\Config.sortStrategy, ui: ui) { label in
                    OMenuPicker(title: label, options: SortStrategy.allCases.map { ($0, $0.title) }, selection: $doc.config.sortStrategy)
                }
                .disabled(!doc.config.virtualWorkspaces)
                let nudge = ConfigOption.at(\Config.sortNudge)
                OSwitchRow(nudge.ui.label, description: nudge.ui.help,
                           isOn: Binding(get: { doc.config.sortNudge > 0 }, set: { doc.config.sortNudge = $0 ? Int(nudge.resetValue) : 0 }))
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting(nudge.ui.id, ui)
                ORow("Crowded from", description: "Windows on one workspace") {
                    OSlider(value: Binding(get: { Double(doc.config.sortNudge) },
                                           set: { doc.config.sortNudge = Int($0.rounded()) }),
                            range: nudge.sliderRange(holding: Double(doc.config.sortNudge)), step: 1, ticks: [nudge.resetValue],
                            resetValue: nudge.resetValue, width: 160, label: "Crowded from", format: { "\(Int($0)) windows" })
                }
                .disabled(!doc.config.virtualWorkspaces || doc.config.sortNudge == 0)
                .setting("windows.sortCrowded", ui)
            }

            AdvancedSection(pane: .windows, ui: ui) {
                OGroup("Windows") {
                    OptionSwitch(\.newWindowsToMain, doc: doc, ui: ui)
                    OptionSwitch(\.floatSmallWindows, doc: doc, ui: ui)
                    ORow("Add app by bundle ID", description: "Wildcards like com.adobe.* work too") {
                        OTextField(placeholder: "com.example.app", text: $ui.newID, mono: true, onSubmit: add).frame(width: 190)
                        OButton("Add", size: .sm, action: add)
                            .disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .setting("windows.bundleID", ui)
                }
                OGroup("Workspaces") {
                    OptionSwitch(\.stayOnWorkspaceAfterClose, doc: doc, ui: ui)
                        .disabled(!doc.config.virtualWorkspaces)
                    ORow("Home Desktop", description: WindowManager.shared.homeSpaceSummary.isEmpty ? "The Desktop you're on when Ouch starts"
                        : "Workspaces live on \(WindowManager.shared.homeSpaceSummary)") {
                        OButton("Use This Desktop", size: .sm) { WindowManager.shared.makeCurrentSpaceHome() }
                    }
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting("windows.home", ui)
                }
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
