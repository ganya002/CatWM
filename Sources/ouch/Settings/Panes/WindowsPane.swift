import AppKit
import SwiftUI

struct WindowsPane: View {

    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    var runningApps: [(name: String, id: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }
            .map { ($0.localizedName ?? $0.bundleIdentifier!, $0.bundleIdentifier!, $0.icon) }
            .filter { app in !doc.config.floating.contains(app.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var addMenu: some View {
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

}
