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

    var windowMode: String {
        doc.binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && !["", "reset"].contains($0.args.lowercased()) }?.args ?? ""
    }

    var pointerShortcuts: [CursorShortcutSpec] {
        Self.pointerShortcutList.filter { $0.id != "workspace" || doc.config.virtualWorkspaces }
    }

    static let pointerShortcutList: [CursorShortcutSpec] = [
        CursorShortcutSpec(id: "float", title: "Float or tile", dispatcher: "togglefloating", args: ""),
        CursorShortcutSpec(id: "zoom", title: "Zoom", dispatcher: "fullscreen", args: ""),
        CursorShortcutSpec(id: "native", title: "Native Full Screen", dispatcher: "nativefullscreen", args: ""),
        CursorShortcutSpec(id: "main", title: "Make Main", dispatcher: "layoutmsg", args: "swapwithmaster"),
        CursorShortcutSpec(id: "layout", title: "Next Layout", dispatcher: "cyclelayout", args: "next"),
        CursorShortcutSpec(id: "display", title: "Send to Next Display", dispatcher: "movewindowtomonitor", args: "+1"),
        CursorShortcutSpec(id: "workspace", title: "Send to Next Workspace", dispatcher: "movetoworkspacesilent", args: "+1", nextWorkspace: true),
        CursorShortcutSpec(id: "dim", title: "Dim Other Windows", dispatcher: "toggledim", args: ""),
        CursorShortcutSpec(id: "blur", title: "Blur Other Windows", dispatcher: "toggleblur", args: ""),
        CursorShortcutSpec(id: "minimize", title: "Minimize", dispatcher: "minimize", args: ""),
        CursorShortcutSpec(id: "close", title: "Close", dispatcher: "killactive", args: ""),
    ]

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
