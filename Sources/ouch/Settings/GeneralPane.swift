// Settings: the General pane (status hero, start at login, updates).
import AppKit
import SwiftUI

// The five Settings panes. Each shows what most people need up front and keeps the rest in its own
// collapsed Advanced section; hidden settings keep working and the search still finds them.

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        let s = ui.status
        VStack(alignment: .leading, spacing: 30) {
            StatusHero(ui: ui).setting("general.status", ui)

            OGroup("Startup") {
                OSwitchRow("Open at login", isOn: loginBinding)
                    .setting("general.login", ui)
                if s.loginNeedsApproval {
                    ORow("Waiting for approval", description: "Allow Ouch in Login Items", symbol: "exclamationmark.triangle.fill") {
                        OButton("Open Login Items", size: .sm) { LoginItem.openSettings() }
                    }
                }
                if !s.inputMonitoring && CapsLockChord.shared.isBound {
                    ORow("Instant Caps Lock shortcuts", description: "Needs Input Monitoring; otherwise Caps Lock waits for a hold") {
                        OButton("Allow…", size: .sm) { Permissions.requestInputMonitoring() }
                    }
                    .setting("general.inputMonitoring", ui)
                }
            }

            OGroup("Tiling") {
                OSwitchRow("Tile windows",
                           isOn: Binding(get: { ui.status.tilingEnabled }, set: { on in
                               if on != WindowManager.shared.tilingEnabled { WindowManager.shared.toggleTiling() }
                               ui.refreshStatus()
                           }))
                    .disabled(!s.running)
                    .setting("general.tiling", ui)
                ORow("Shortcut key", description: "The key you hold for most shortcuts") {
                    OMenuPicker(title: "Shortcut key", options: modifierOptions,
                                selection: Binding(get: { doc.modValue }, set: { doc.modValue = $0 }))
                }
                .setting("general.modifier", ui)
            }

            OGroup("Updates") {
                if updater.isConfigured {
                    OSwitchRow("Check for updates automatically",
                               isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                        .setting("general.autoCheck", ui)
                    if updater.automaticallyChecks {
                        OSwitchRow("Download updates automatically",
                                   isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                            .setting("general.autoDownload", ui)
                            .transition(.opacity)
                    }
                    OSwitchRow("Include beta releases", description: "Get new versions early. They may have bugs.",
                               isOn: Binding(get: { updater.receivesBeta }, set: { updater.receivesBeta = $0 }))
                        .setting("general.beta", ui)
                    ORow("Check for updates", description: updater.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))" }
                        ?? "Not checked yet") {
                        OButton("Check Now", icon: "arrow.down.circle", size: .sm) { updater.checkForUpdates() }
                    }
                    .setting("general.checkNow", ui)
                } else {
                    ORow("Updates aren't set up", description: "Release builds published with Amore update themselves")
                        .setting("general.checkNow", ui)
                }
            }
            .animation(Motion.easeOut, value: updater.automaticallyChecks)

            OGroup("Reset") {
                ORow("Reset all settings", description: "Layouts, gaps, floating apps and shortcuts. Your shortcut key stays.") {
                    OButton("Reset…", variant: .danger, size: .sm) {
                        if confirm("Reset all settings to their defaults?", "Resets layouts, gaps, floating apps and shortcuts. Your shortcut key is kept.") {
                            doc.resetEverything()
                        }
                    }
                }
                .setting("general.reset", ui)
            }

            AmoreCredit().frame(maxWidth: .infinity)
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { ui.status.launchAtLogin || ui.status.loginNeedsApproval }, set: { on in
            LoginItem.set(on)
            ui.refreshStatus()
        })
    }

    private var modifierOptions: [(value: String, label: String)] {
        var o = ConfigDocument.modifierChoices.map { (value: $0.value, label: $0.label) }
        if !o.contains(where: { $0.value == doc.modValue }) { o.append((doc.modValue, doc.modValue)) }
        return o
    }
}

/// Whether Ouch is working, straight on the pane: icon, a title, one line of detail, and the way to
/// fix it when it isn't. One layout for every state, so the icon stays put (and can bump) on a grant.
private struct StatusHero: View {
    @ObservedObject var ui: SettingsUI

    var body: some View {
        let s = ui.status
        let live = s.trusted && s.keybindsActive && s.tilingEnabled
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                BadgedAppIcon(badge: !s.trusted ? "lock.circle.fill" : live ? "checkmark.circle.fill"
                                  : s.keybindsActive ? "pause.circle.fill" : "exclamationmark.circle.fill",
                              color: live ? Theme.success : Theme.warning, size: 52)
                    .squish(on: live, when: live)
                VStack(alignment: .leading, spacing: 3) {
                    Text(!s.trusted ? "Ouch needs Accessibility access" : !s.tilingEnabled ? "Tiling is paused"
                         : s.keybindsActive ? "Ouch is running" : "Keyboard shortcuts aren't active")
                        .font(Theme.body(22)).tracking(-0.2).oneLine()
                        .contentTransition(.opacity)
                    Text(s.trusted ? summary(s) : "macOS only lets apps move other apps' windows with this permission.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if s.trusted && !s.keybindsActive {
                    OButton("Retry", icon: "arrow.clockwise", size: .sm) { Hotkeys.shared.restart(); ui.refreshStatus() }
                }
            }
            if !s.trusted {
                VStack(alignment: .leading, spacing: 8) {
                    OStep(n: 1, text: "Click **Grant Access**. A guide appears next to System Settings.")
                    OStep(n: 2, text: "Turn on Ouch in the list.")
                    OStep(n: 3, text: "Still not working after a rebuild? Click **Reset Permission**, then turn it on again.")
                }
                HStack(spacing: 8) {
                    OButton("Grant Access", icon: "lock.open", variant: .primary) { Permissions.request() }
                    OButton("Reset Permission", variant: .ghost) { Permissions.reset() }
                    Spacer()
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Waiting…").font(Theme.body(12)).foregroundStyle(Theme.inkMuted)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut, value: s.trusted)
    }

    private func summary(_ s: WindowManager.Status) -> String {
        let w = "\(s.tiled) tiled window\(s.tiled == 1 ? "" : "s")"
        let f = s.floating > 0 ? " · \(s.floating) floating" : ""
        let d = " · \(s.screens.count) display\(s.screens.count == 1 ? "" : "s")"
        return w + f + d
    }
}
