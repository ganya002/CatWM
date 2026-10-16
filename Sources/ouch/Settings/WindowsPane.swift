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
                OSwitchRow("Focus follows mouse", description: "Hovering a window focuses it", isOn: $doc.config.focusFollowsMouse)
                    .setting("windows.ffm", ui)
                OSwitchRow("Only in window mode", description: "Hovering focuses a window only while window mode is on",
                           isOn: $doc.config.focusFollowsMouseInModeOnly)
                    .disabled(!doc.config.focusFollowsMouse)
                    .setting("windows.ffmModeOnly", ui)
                OSwitchRow("Mouse follows focus", description: "The pointer jumps to the window you focus", isOn: $doc.config.mouseFollowsFocus)
                    .setting("windows.mff", ui)
                OSwitchRow("Dim other windows", description: "Darkens everything but the focused window", isOn: $doc.config.dimOtherWindows)
                    .setting("windows.dimOthers", ui)
                ORow("Dim strength", description: "How dark the other windows get") {
                    OSlider(value: Binding(get: { Double(doc.config.dimStrength * 100) },
                                           set: { doc.config.dimStrength = CGFloat($0.rounded()) / 100 }),
                            range: 0...100, step: 1, ticks: [30], resetValue: 30, width: 160, label: "Dim strength",
                            format: { "\(Int($0))%" })
                }
                .disabled(!doc.config.dimOtherWindows)
                .setting("windows.dimStrength", ui)
                OSwitchRow("Blur other windows", description: "Softens everything but the focused window", isOn: $doc.config.blurOtherWindows)
                    .setting("windows.blurOthers", ui)
                ORow("Blur radius", description: "How soft the other windows look") {
                    OSlider(value: Binding(get: { Double(doc.config.blurRadius) },
                                           set: { doc.config.blurRadius = CGFloat($0.rounded()) }),
                            range: 2...60, step: 1, ticks: [20], resetValue: 20, width: 160, label: "Blur radius",
                            format: { "\(Int($0)) pt" })
                }
                .disabled(!doc.config.blurOtherWindows)
                .setting("windows.blurRadius", ui)
            }

            OGroup("Mouse") {
                OSwitchRow("Drag to swap", description: "Drop a window on another to trade places", isOn: $doc.config.mouseSwapsWindows)
                    .setting("windows.dragSwap", ui)
                OSwitchRow("Drag window edges to resize the main pane",
                           description: "Resize a tiled window with the mouse, and the main pane follows", isOn: $doc.config.mouseResizesWindows)
                    .setting("windows.resizeMain", ui)
            }

            OGroup("Pointer menu") {
                OSwitchRow("Quick actions at the pointer",
                           description: "In window mode, tap the mode's modifier. Press a shortcut below to run it",
                           isOn: $doc.config.cursorActions)
                    .setting("windows.cursorActions", ui)
                if doc.config.cursorActions {
                    ForEach(pointerShortcuts) { spec in pointerShortcutRow(spec) }
                }
            }

            OGroup("Floating") {
                ORow("Apps in the list", description: doc.config.floatingIsBlacklist ? "Float; everything else tiles" : "Are the only ones that tile") {
                    OSegmented(title: "Apps in the list", options: [(true, "Float"), (false, "Tile")],
                               selection: $doc.config.floatingIsBlacklist)
                }
                .setting("windows.floatingMode", ui)
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
                OSwitchRow("Use Ouch workspaces", description: "Instant, per-display workspaces instead of macOS Spaces",
                           isOn: $doc.config.virtualWorkspaces)
                    .setting("windows.workspaces", ui)
                ORow("Sort windows by", description: "How the Sort Windows panel groups them when it opens") {
                    OMenuPicker(title: "Sort windows by", options: SortStrategy.allCases.map { ($0, $0.title) },
                                selection: $doc.config.sortStrategy)
                }
                .disabled(!doc.config.virtualWorkspaces)
                .setting("windows.sortStrategy", ui)
                OSwitchRow("Suggest sorting a crowded workspace", description: "A tip under the menu bar icon, at most once a day",
                           isOn: Binding(get: { doc.config.sortNudge > 0 }, set: { doc.config.sortNudge = $0 ? 5 : 0 }))
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting("windows.sortNudge", ui)
                ORow("Crowded from", description: "Windows on one workspace") {
                    OSlider(value: Binding(get: { Double(doc.config.sortNudge) },
                                           set: { doc.config.sortNudge = Int($0.rounded()) }),
                            range: Double(min(3, doc.config.sortNudge))...Double(max(20, doc.config.sortNudge)), step: 1, ticks: [5], resetValue: 5, width: 160, label: "Crowded from",
                            format: { "\(Int($0)) windows" })
                }
                .disabled(!doc.config.virtualWorkspaces || doc.config.sortNudge == 0)
                .setting("windows.sortCrowded", ui)
            }

            AdvancedSection(pane: .windows, ui: ui) {
                OGroup("Windows") {
                    OSwitchRow("New windows become main", isOn: $doc.config.newWindowsToMain).setting("windows.newMain", ui)
                    OSwitchRow("Float small windows", description: "Dialogs and panels stay put", isOn: $doc.config.floatSmallWindows)
                        .setting("windows.floatSmall", ui)
                    ORow("Add app by bundle ID", description: "Wildcards like com.adobe.* work too") {
                        OTextField(placeholder: "com.example.app", text: $ui.newID, mono: true, onSubmit: add).frame(width: 190)
                        OButton("Add", size: .sm, action: add)
                            .disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .setting("windows.bundleID", ui)
                }
                OGroup("Workspaces") {
                    OSwitchRow("Stay on this workspace when closing a window", isOn: $doc.config.stayOnWorkspaceAfterClose)
                        .disabled(!doc.config.virtualWorkspaces)
                        .setting("windows.stay", ui)
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

    /// A bind `keyActions` cannot show, usually because its key is still empty. Add resumes that row
    /// instead of appending another one.
    private func unfinishedShortcut(_ spec: CursorShortcutSpec) -> BindRow? {
        doc.binds.first {
            $0.submap == windowMode && (spec.nextWorkspace
                ? Actions.isNextWorkspace($0.dispatcher, $0.args)
                : Actions.same($0.dispatcher, $0.args, spec.dispatcher, spec.args))
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
                Image(systemName: "plus").font(.system(size: 11.5, weight: .medium))
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
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 26, height: 26).padding(1)
        }
    }
}
