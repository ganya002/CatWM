import AppKit
import CatWMKit
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        let status = settingsUI.status
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            if !(status.trusted && status.keybindsActive) {
                StatusHero(settingsUI: settingsUI).setting(GeneralPane.searchStatus.id, settingsUI)
            }

            OGroup("Startup") {
                if LoginItem.isAvailable {
                    OSwitchRow(GeneralPane.searchLogin.title, isOn: loginBinding)
                        .setting(GeneralPane.searchLogin.id, settingsUI)
                } else {
                    ORow(GeneralPane.searchLogin.title, description: "Only the main CatWM can open at login")
                        .setting(GeneralPane.searchLogin.id, settingsUI)
                }
                if LoginItem.isAvailable && status.loginNeedsApproval {
                    ORow("Waiting for approval", description: "Allow CatWM in Login Items",
                         symbol: "exclamationmark.triangle.fill") {
                        OButton("Open Login Items", size: .small) { LoginItem.shared.openSettings() }
                    }
                }
                if !status.inputMonitoring && CapsLockChord.shared.isBound {
                    ORow(GeneralPane.searchInputMonitoring.title,
                         description: "Needs Input Monitoring; otherwise Caps Lock waits for a hold") {
                        OButton("Allow…", size: .small) { Permissions.requestInputMonitoring() }
                    }
                    .setting(GeneralPane.searchInputMonitoring.id, settingsUI)
                }
            }

            OGroup(GeneralPane.searchTiling.title) {
                OSwitchRow("Tile windows",
                           isOn: Binding(get: { settingsUI.status.tilingEnabled }, set: { enabled in
                               if enabled != WindowManager.shared.tilingEnabled { WindowManager.shared.toggleTiling() }
                               settingsUI.refreshStatus()
                           }))
                    .disabled(!status.running)
                    .setting(GeneralPane.searchTiling.id, settingsUI)
                ORow(GeneralPane.searchModifier.title, description: "The key you hold for most shortcuts") {
                    OMenuPicker(title: "Shortcut key", options: modifierOptions,
                                selection: Binding(get: { doc.modValue }, set: { doc.modValue = $0 }))
                }
                .setting(GeneralPane.searchModifier.id, settingsUI)
            }

            if ConfigStore.shared.isScript { configGroup }

            OGroup("Updates") {
                if updater.isConfigured {
                    OSwitchRow(GeneralPane.searchAutoCheck.title,
                               isOn: Binding(get: { updater.automaticallyChecks },
                                             set: { updater.automaticallyChecks = $0 }))
                        .setting(GeneralPane.searchAutoCheck.id, settingsUI)
                    if updater.automaticallyChecks {
                        OSwitchRow(GeneralPane.searchAutoDownload.title,
                                   isOn: Binding(get: { updater.automaticallyDownloads },
                                                 set: { updater.automaticallyDownloads = $0 }))
                            .setting(GeneralPane.searchAutoDownload.id, settingsUI)
                            .transition(.opacity)
                    }
                    OSwitchRow(GeneralPane.searchBeta.title, description: "Get new versions early. They may have bugs.",
                               isOn: Binding(get: { updater.receivesBeta }, set: { updater.receivesBeta = $0 }))
                        .setting(GeneralPane.searchBeta.id, settingsUI)
                    ORow(GeneralPane.searchCheckNow.title,
                         description: updater.lastChecked.map {
                             "Last checked \($0.formatted(.relative(presentation: .named)))"
                         } ?? "Not checked yet") {
                        OButton("Check Now", icon: "arrow.down.circle", size: .small) { updater.checkForUpdates() }
                    }
                    .setting(GeneralPane.searchCheckNow.id, settingsUI)
                } else {
                    ORow("Updates aren't set up", description: "Release builds published with Amore update themselves")
                        .setting(GeneralPane.searchCheckNow.id, settingsUI)
                }
            }
            .animation(Motion.easeOut, value: updater.automaticallyChecks)

            OGroup("Reset") {
                ORow(GeneralPane.searchReset.title,
                     description: "Layouts, gaps, floating apps and shortcuts. Your shortcut key stays.") {
                    OButton("Reset…", variant: .danger, size: .small) {
                        if confirm("Reset all settings to their defaults?",
                                   "Resets layouts, gaps, floating apps and shortcuts. Your shortcut key is kept.") {
                            doc.resetEverything()
                        }
                    }
                }
                .setting(GeneralPane.searchReset.id, settingsUI)
            }

            AdditionalOptionGroups(pane: .general, doc: doc, settingsUI: settingsUI)
            if !OptionRows.additionalSections(pane: .general, advanced: true).isEmpty {
                AdvancedSection(pane: .general, settingsUI: settingsUI) {
                    AdditionalOptionGroups(pane: .general, advanced: true, doc: doc, settingsUI: settingsUI)
                }
            }

            AmoreCredit().frame(maxWidth: .infinity)
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { settingsUI.status.launchAtLogin || settingsUI.status.loginNeedsApproval }, set: { enabled in
            LoginItem.shared.set(enabled)
            settingsUI.refreshStatus()
        })
    }

    private var modifierOptions: [(value: String, label: String)] {
        var options = ConfigDocument.modifierChoices.map { (value: $0.value, label: $0.label) }
        if !options.contains(where: { $0.value == doc.modValue }) { options.append((doc.modValue, doc.modValue)) }
        return options
    }
}

extension GeneralPane {
    static let searchStatus = SettingEntry(id: "general.status", title: "Accessibility access", pane: .general,
                                           keywords: "permission status running grant")
    static let searchLogin = SettingEntry(id: "general.login", title: "Open at login", pane: .general,
                                          keywords: "startup launch login items")
    static let searchInputMonitoring = SettingEntry(id: "general.inputMonitoring",
                                                    title: "Instant Caps Lock shortcuts", pane: .general,
                                                    keywords: "input monitoring permission")
    static let searchTiling = SettingEntry(id: "general.tiling", title: "Tiling", pane: .general,
                                           keywords: "enable disable pause on off")
    static let searchModifier = SettingEntry(id: "general.modifier", title: "Shortcut key", pane: .general,
                                             keywords: "main modifier mod key option command control super")
    static let searchAutoCheck = SettingEntry(id: "general.autoCheck", title: "Check for updates automatically",
                                              pane: .general, keywords: "update sparkle")
    static let searchAutoDownload = SettingEntry(id: "general.autoDownload", title: "Download updates automatically",
                                                 pane: .general, keywords: "update sparkle")
    static let searchCheckNow = SettingEntry(id: "general.checkNow", title: "Check for updates", pane: .general,
                                             keywords: "update version")
    static let searchBeta = SettingEntry(id: "general.beta", title: "Include beta releases", pane: .general,
                                         keywords: "update channel early")
    static let searchReset = SettingEntry(id: "general.reset", title: "Reset all settings", pane: .general,
                                          keywords: "defaults restore factory")
}

extension GeneralPane {
    private var configGroup: some View {
        OGroup("Config") {
            ORow(ConfigStore.scriptName, description: "Settings saves its changes next to this file, never in it") {
                OButton("Open", size: .small) { NSWorkspace.shared.open(ConfigStore.shared.scriptURL) }
            }
            ForEach(doc.overrides, id: \.self) { path in
                ORow(ConfigScript.label(path),
                     description: "Changed in Settings, so `\(path)` in the file doesn't apply") {
                    OButton("Use File Value", size: .small) { doc.useScriptValue(path) }
                }
            }
            if doc.overrides.count > 1 {
                ORow("All changes from Settings", description: "Use every value from \(ConfigStore.scriptName) again") {
                    OButton("Use File Values", size: .small) { doc.useScriptValue(nil) }
                }
            }
        }
    }
}
