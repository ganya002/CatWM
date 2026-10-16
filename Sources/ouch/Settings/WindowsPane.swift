// Settings: the Windows pane (floating, focus and window behavior options).
import AppKit
import SwiftUI

// MARK: - Windows

/// One action the pointer menu can run, and the dispatcher whose window-mode shortcut it shows.
private struct CursorShortcutSpec: Identifiable {
    let id: String
    let title: String
    let dispatcher: String
    let args: String
    /// Follows whichever bind sends a window to the next workspace, rather than one fixed dispatcher.
    var nextWorkspace = false
}

struct WindowsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private var runningApps: [(name: String, id: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }
            .map { ($0.localizedName ?? $0.bundleIdentifier!, $0.bundleIdentifier!, $0.icon) }
            .filter { app in !doc.config.floating.contains(app.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
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
                // One option, two rows: the switch turns the tip on at the default count, the slider sets the count.
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

    /// The window mode the pointer menu reads its shortcuts from, or "" when there is none.
    private var windowMode: String {
        doc.binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && !["", "reset"].contains($0.args.lowercased()) }?.args ?? ""
    }

    /// The pointer menu's actions, in menu order. Send to Next Workspace is only there with Ouch workspaces.
    private var pointerShortcuts: [CursorShortcutSpec] {
        Self.pointerShortcutList.filter { $0.id != "workspace" || doc.config.virtualWorkspaces }
    }

    private static let pointerShortcutList: [CursorShortcutSpec] = [
        CursorShortcutSpec(id: "float", title: "Float or tile", dispatcher: "togglefloating", args: ""),
        CursorShortcutSpec(id: "zoom", title: "Zoom", dispatcher: "fullscreen", args: ""),
        CursorShortcutSpec(id: "native", title: "Native Full Screen", dispatcher: "nativefullscreen", args: ""),
        CursorShortcutSpec(id: "main", title: "Make Main", dispatcher: "layoutmsg", args: "swapwithmaster"),
        CursorShortcutSpec(id: "layout", title: "Next Layout", dispatcher: "cyclelayout", args: "next"),
        CursorShortcutSpec(id: "display", title: "Send to Next Display", dispatcher: "movewindowtomonitor", args: "+1"),
        CursorShortcutSpec(id: "workspace", title: "Send to Next Workspace", dispatcher: "movetoworkspacesilent", args: "+1", nextWorkspace: true),
        CursorShortcutSpec(id: "minimize", title: "Minimize", dispatcher: "minimize", args: ""),
        CursorShortcutSpec(id: "close", title: "Close", dispatcher: "killactive", args: ""),
    ]

    /// The window-mode key already bound to this action. `keyActions` has split range binds, so one key shows.
    private func shortcut(for spec: CursorShortcutSpec) -> ConfigDocument.KeyAction? {
        doc.keyActions(in: windowMode).first {
            $0.code < 0x1000 && (spec.nextWorkspace
                ? Actions.isNextWorkspace($0.row.dispatcher, $0.arg)
                : Actions.same($0.row.dispatcher, $0.arg, spec.dispatcher, spec.args))
        }
    }

    private func pointerShortcutRow(_ spec: CursorShortcutSpec) -> some View {
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

    /// A bind `keyActions` cannot show because its key is empty or unknown. Add resumes that row
    /// instead of appending another one. A scroll or swipe bind is a real shortcut this list leaves
    /// out, so it is left alone and a new row is recorded.
    private func unfinishedShortcut(_ spec: CursorShortcutSpec) -> BindRow? {
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

    private func addShortcut(_ spec: CursorShortcutSpec) {
        let row: BindRow
        if let existing = unfinishedShortcut(spec) {
            row = existing
        } else {
            let mode = windowMode
            row = BindRow(mods: mode.isEmpty ? doc.modVarName : "", key: "",
                          dispatcher: spec.dispatcher, args: spec.args, submap: mode)
            doc.binds.append(row)
        }
        ui.open(SettingEntry(id: "bind.\(row.id)", title: spec.title, pane: .shortcuts, bind: row))
        DispatchQueue.main.async { ui.recording = row.id }
    }

    private var addMenu: some View {
        let doc = doc, apps = runningApps
        return OMenuButton(style: OButtonStyle(variant: .secondary, size: .sm), items: {
            apps.map { app in
                MenuItem(id: app.id, label: app.name, image: app.icon.map(resized), enabled: !doc.config.floating.contains(app.id), action: {
                    if !doc.config.floating.contains(app.id) { withAnimation(Motion.easeOut) { doc.config.floating.append(app.id) } }
                })
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(Theme.symbol(Theme.Icon.sm))
                Text("Add Running App")
            }
        }
        .fixedSize()
    }

    private func add() {
        let id = ui.newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !doc.config.floating.contains(id) else { return }
        withAnimation(Motion.easeOut) { doc.config.floating.append(id) }
        ui.newID = ""
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func appURL(_ id: String) -> URL? {
        id.hasSuffix("*") ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    private func appName(_ id: String) -> String? {
        appURL(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
    @ViewBuilder private func appIcon(_ id: String) -> some View {
        if let url = appURL(id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 26, height: 26).padding(1)
        }
    }
}
