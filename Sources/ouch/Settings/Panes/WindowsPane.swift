import AppKit
import SwiftUI

struct WindowsPane: View {
    struct RunningApp {
        let name: String
        let id: String
        let icon: NSImage?
    }

    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI

    var runningApps: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in
                app.bundleIdentifier.map { RunningApp(name: app.localizedName ?? $0, id: $0, icon: app.icon) }
            }
            .filter { app in !doc.config.floating.contains(app.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var addMenu: some View {
        let doc = doc, apps = runningApps
        return OMenuButton(style: OButtonStyle(variant: .secondary, size: .small), items: {
            apps.map { app in
                MenuItem(id: app.id, label: app.name, image: app.icon.map(resized),
                         enabled: !doc.config.floating.contains(app.id), action: {
                    if !doc.config.floating.contains(app.id) {
                        withAnimation(Motion.easeOut) { doc.config.floating.append(app.id) }
                    }
                })
            }
        }, label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(Theme.symbol(Theme.Icon.small))
                Text("Add Running App")
            }
        })
        .fixedSize()
    }
}

extension WindowsPane {
    static let searchSortCrowded = SettingEntry(id: "windows.sortCrowded", title: "Crowded from", pane: .windows,
                                                keywords: "overview sort windows workspace count tip")
    static let searchBundleID = SettingEntry(id: "windows.bundleID", title: "Add app by bundle ID", pane: .windows,
                                             advanced: true, keywords: "floating wildcard identifier")
    static let searchHome = SettingEntry(id: "windows.home", title: "Home Desktop", pane: .windows, advanced: true,
                                         keywords: "spaces desktop workspaces live")
}
