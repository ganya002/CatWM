import AppKit
import SwiftUI

extension MenuModel {
    static func build() -> [MenuItem] {
        let manager = WindowManager.shared
        let keys = ShortcutIndex()
        let axGranted = Permission.accessibility.isGranted
        let trusted = axGranted && manager.isStarted
        let state = manager.menuBarState()
        let layout = state?.layout
        var out: [MenuItem] = []

        if !axGranted {
            out.append(MenuItem(id: "attention", kind: .attention, label: "Ouch needs Accessibility",
                                keywords: "permission grant",
                                action: { Permission.accessibility.request() }))
        }

        out.append(MenuItem(id: "tiling", kind: .check, label: "Tiling", symbol: "rectangle.split.3x1",
                            shortcut: keys.keys("toggletiling"),
                            checked: manager.tilingEnabled, enabled: trusted, hidden: true,
                            keywords: "enable disable pause toggle",
                            keepOpen: true, action: { manager.toggleTiling() }))

        let workspaceName = state?.workspace.map { "Workspace \($0)" } ?? "Desktop"
        out.append(.label("where", layout.map { "\(workspaceName) · \($0.title)" } ?? workspaceName))
        out += workspaceItems(manager, keys: keys, trusted: trusted)
        out.append(.sep("s1"))

        out.append(layoutMenu(manager, keys: keys, trusted: trusted, layout: layout))
        if let bring = bringWindowMenu(manager, trusted: trusted) { out.append(bring) }

        out.append(.sep("s2"))
        out += footerItems(manager, keys: keys, trusted: trusted)
        return out
    }

    private static func workspaceItems(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool) -> [MenuItem] {
        let summary = manager.workspaceSummary()
        guard manager.config.virtualWorkspaces && trusted else { return [] }
        var out = [MenuItem(id: "workspaces", kind: .workspaces)]
        let highest = summary.all.compactMap { Int($0.name) }.max() ?? 0
        for number in 1...max(9, min(highest, 10)) {
            out.append(MenuItem(id: "ws-\(number)", label: "Go to Workspace \(number)",
                                shortcut: keys.keys("workspace", "\(number)"),
                                hidden: true, keywords: "switch space desktop",
                                action: { manager.showWorkspace("\(number)") }))
        }
        return out
    }

    private static func layoutMenu(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool,
                                   layout: Layout?) -> MenuItem {
        var layoutItems: [MenuItem] = [
            MenuItem(id: "picker", kind: .layoutPicker),
            MenuItem(id: "next-layout", label: "Next Layout", symbol: "chevron.right",
                     shortcut: keys.keys("cyclelayout", "next"),
                     enabled: trusted, hidden: true, keepOpen: true,
                     action: { manager.dispatch("cyclelayout", "next") }),
            MenuItem(id: "prev-layout", label: "Previous Layout", symbol: "chevron.left",
                     shortcut: keys.keys("cyclelayout", "prev"),
                     enabled: trusted, hidden: true, keepOpen: true,
                     action: { manager.dispatch("cyclelayout", "prev") })
        ]
        layoutItems += Layout.allCases.map { option in
            MenuItem(id: "layout-\(option.rawValue)", kind: .radio, label: option.title,
                     shortcut: keys.keys("layout", option.rawValue), checked: option == layout,
                     enabled: trusted, hidden: true, keywords: "layout \(option.blurb)",
                     action: { manager.dispatch("layout", option.rawValue) })
        }
        return MenuItem(id: "layout", kind: .sub, label: "Layout", symbol: "square.grid.2x2", value: layout?.title,
                        enabled: trusted, width: 276, children: layoutItems)
    }

    private static func bringWindowMenu(_ manager: WindowManager, trusted: Bool) -> MenuItem? {
        guard manager.config.virtualWorkspaces && trusted else { return nil }
        let incoming = manager.windowsOnOtherDesktops().map { window in
            let app = NSRunningApplication(processIdentifier: window.pid)
            let title = window.element.string(kAXTitleAttribute) ?? "Untitled"
            return MenuItem(id: "bring-\(window.id)", label: title.isEmpty ? "Untitled" : title, image: app?.icon,
                            value: app?.localizedName, keywords: "bring import window desktop space",
                            action: { manager.bringWindowHere(window) })
        }
        guard !incoming.isEmpty else { return nil }
        return MenuItem(id: "bring-window", kind: .sub, label: "Bring Window Here",
                        symbol: "rectangle.badge.arrow.down", keywords: "import other desktops spaces",
                        width: 340, children: incoming)
    }

    private static func footerItems(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool) -> [MenuItem] {
        let paused = TutorialLesson.paused
        return [
            MenuItem(id: "settings", label: "Settings…", symbol: "gearshape", shortcut: ["⌘", ","],
                     keywords: "preferences options",
                     rotates: true, action: { SettingsWindow.shared.show(pane: nil) }),
            MenuItem(id: "tutorial", label: paused == nil ? "Keyboard Tutorial…" : "Resume Tutorial…",
                     symbol: "graduationcap",
                     value: paused?.name, enabled: trusted,
                     keywords: "learn practice drill keys lessons onboarding help",
                     action: { Onboarding.shared.startTutorial() }),
            MenuItem(id: "help", kind: .sub, label: "Help", symbol: "questionmark.circle",
                     children: helpItems(manager, keys: keys, trusted: trusted)),
            .sep("s3"),
            MenuItem(id: "quit", kind: .footer, label: "Quit Ouch", shortcut: ["⌘", "Q"], keywords: "exit",
                     action: { NSApp.terminate(nil) })
        ]
    }

    private static func helpItems(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool) -> [MenuItem] {
        [
            MenuItem(id: "map", label: "Shortcut Map", symbol: "keyboard", shortcut: ["⌘", "/"],
                     keywords: "keys overview cheat sheet",
                     action: { SettingsWindow.shared.show(pane: .shortcuts, map: true) }),
            MenuItem(id: "keyhelp", label: "Keyboard Help", symbol: "keyboard.badge.ellipsis", shortcut: keys.modeChord,
                     enabled: trusted, hidden: true, keywords: "keys overlay cheat sheet window mode",
                     action: { KeyHelp.shared.showFromMenu(preferredMode: keys.modeName) }),
            MenuItem(id: "tour", label: "Quick Tour", symbol: "play.circle", enabled: trusted,
                     keywords: "learn tutorial onboarding keyboard tour", action: { Onboarding.shared.startTour() }),
            MenuItem(id: "tutorial-restart", label: "Restart Tutorial", symbol: "arrow.counterclockwise",
                     enabled: trusted, hidden: true, keywords: "learn tutorial start over",
                     action: { Onboarding.shared.startTutorial(fromStart: true) }),
            MenuItem(id: "tips", kind: .check, label: "Show Tips", checked: Tips.shared.enabled, hidden: true,
                     keywords: "hints help tooltips",
                     keepOpen: true, action: { Tips.shared.enabled.toggle() }),
            MenuItem(id: "reload", label: "Reload Config", symbol: "arrow.triangle.2.circlepath",
                     shortcut: keys.keys("reload"),
                     hidden: true, keywords: "refresh file", keepOpen: true, rotates: true,
                     action: { manager.reload() }),
            MenuItem(id: "updates", label: "Check for Updates…", symbol: "arrow.down.circle",
                     keywords: "version upgrade", action: { AppDelegate.checkForUpdates() })
        ]
    }
}
