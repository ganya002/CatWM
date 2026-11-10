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
            out.append(MenuItem(id: "attention", kind: .attention, label: "CatWM needs Accessibility",
                                keywords: "permission grant",
                                action: { Permission.accessibility.request() }))
        }
        if let failure = ConfigStore.shared.failures.first {
            let file = URL(fileURLWithPath: failure.file ?? ConfigStore.shared.scriptURL.path)
            out.append(MenuItem(id: "config-error", kind: .attention, label: "Config error: \(failure.text)",
                                keywords: "config typescript error broken",
                                action: { NSWorkspace.shared.open(file) }))
        }

        out.append(MenuItem(id: "tiling", kind: .check, label: "Tiling", symbol: "rectangle.split.3x1",
                            shortcut: keys.keys(WindowActions.toggletiling.name),
                            checked: manager.tilingEnabled, enabled: trusted, hidden: true,
                            keywords: "enable disable pause toggle",
                            keepOpen: true, action: { manager.toggleTiling() }))

        out.append(layoutMenu(manager, keys: keys, trusted: trusted, layout: layout))
        if let workspaces = workspacesMenu(manager, keys: keys, trusted: trusted, state: state) {
            out.append(workspaces)
        }
        out.append(.sep("s1"))
        out += footerItems(manager, keys: keys, trusted: trusted)
        return out
    }

    private static func workspacesMenu(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool,
                                       state: MenuBarState?) -> MenuItem? {
        guard manager.config.virtualWorkspaces && trusted else { return nil }
        var children = workspaceItems(manager, keys: keys, trusted: trusted)
        if let bring = bringWindowMenu(manager, trusted: trusted) { children.append(bring) }
        let count = manager.workspaceSummary().all.count
        let value = state?.workspace.map { "\($0) of \(count)" }
        return MenuItem(id: "workspaces-menu", kind: .sub, label: "Workspaces", symbol: "square.on.square",
                        value: value, keywords: "switch space desktop", width: 276, children: children)
    }

    private static func workspaceItems(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool) -> [MenuItem] {
        let summary = manager.workspaceSummary()
        guard manager.config.virtualWorkspaces && trusted else { return [] }
        var out = [MenuItem(id: "workspaces", kind: .workspaces)]
        let highest = summary.all.compactMap { Int($0.name) }.max() ?? 0
        for number in 1...max(9, min(highest, 10)) {
            out.append(MenuItem(id: "ws-\(number)", label: "Go to Workspace \(number)",
                                shortcut: keys.keys(WindowActions.workspace.name, "\(number)"),
                                hidden: true, keywords: "switch space desktop",
                                action: { manager.showWorkspaceNumber("\(number)") }))
        }
        return out
    }

    private static func layoutMenu(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool,
                                   layout: Layout?) -> MenuItem {
        var layoutItems: [MenuItem] = [
            MenuItem(id: "picker", kind: .layoutPicker),
            MenuItem(id: "next-layout", label: "Next Layout", symbol: "chevron.right",
                     shortcut: keys.keys(WindowActions.cyclelayout.name, "next"),
                     enabled: trusted, hidden: true, keepOpen: true,
                     action: { manager.dispatch(WindowActions.cyclelayout.name, "next") }),
            MenuItem(id: "prev-layout", label: "Previous Layout", symbol: "chevron.left",
                     shortcut: keys.keys(WindowActions.cyclelayout.name, "prev"),
                     enabled: trusted, hidden: true, keepOpen: true,
                     action: { manager.dispatch(WindowActions.cyclelayout.name, "prev") })
        ]
        layoutItems += Layout.allCases.map { option in
            MenuItem(id: "layout-\(option.rawValue)", kind: .radio, label: option.title,
                     shortcut: keys.keys(WindowActions.layout.name, option.rawValue), checked: option == layout,
                     enabled: trusted, hidden: true, keywords: "layout \(option.blurb)",
                     action: { manager.dispatch(WindowActions.layout.name, option.rawValue) })
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
        [
            MenuItem(id: "settings", label: "Settings…", symbol: "gearshape", shortcut: ["⌘", ","],
                     keywords: "preferences options",
                     rotates: true, action: { SettingsWindow.shared.show(pane: nil) }),
            MenuItem(id: "help", kind: .sub, label: "Help", symbol: "questionmark.circle",
                     children: helpItems(manager, keys: keys, trusted: trusted), dot: WhatsNew.shared.hasNews),
            .sep("s3"),
            MenuItem(id: "quit", kind: .footer, label: "Quit CatWM", shortcut: ["⌘", "Q"], keywords: "exit",
                     action: { NSApp.terminate(nil) })
        ]
    }

    private static func whatsNewItem(dot: Bool) -> MenuItem {
        MenuItem(id: "whats-new", label: "What's New…", symbol: "sparkles",
                 keywords: "release notes changes features update version catch up", dot: dot,
                 action: { WhatsNew.shared.show() })
    }

    private static func helpItems(_ manager: WindowManager, keys: ShortcutIndex, trusted: Bool) -> [MenuItem] {
        let paused = TutorialLesson.paused
        let news = [whatsNewItem(dot: WhatsNew.shared.hasNews)]
        return news + [
            MenuItem(id: "tutorial", label: paused == nil ? "Keyboard Tutorial…" : "Resume Tutorial…",
                     symbol: "graduationcap",
                     value: paused?.name, enabled: trusted,
                     keywords: "learn practice drill keys lessons onboarding help",
                     action: { Onboarding.shared.startTutorial() }),
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
                     shortcut: keys.keys(WindowActions.reload.name),
                     hidden: true, keywords: "refresh file", keepOpen: true, rotates: true,
                     action: { manager.reload() }),
            MenuItem(id: "updates", label: "Check for Updates…", symbol: "arrow.down.circle",
                     keywords: "version upgrade", action: { AppDelegate.checkForUpdates() })
        ]
    }
}
