import AppKit
import SwiftUI

extension MenuModel {
    func rebuild() {
        items = source()
    }

    func reset() {
        query = ""
        path = []
        highlight = [:]
        appeared = false
        openWork?.cancel()
        trimWork?.cancel()
    }

    static func build() -> [MenuItem] {
        let wm = WindowManager.shared
        let keys = ShortcutIndex()
        let axGranted = Permission.accessibility.isGranted
        let trusted = axGranted && wm.isStarted
        let state = wm.menuBarState()
        let layout = state?.layout
        var out: [MenuItem] = []

        if !axGranted {
            out.append(MenuItem(id: "attention", kind: .attention, label: "Ouch needs Accessibility", keywords: "permission grant",
                                action: { Permission.accessibility.request() }))
        }

        out.append(MenuItem(id: "tiling", kind: .check, label: "Tiling", symbol: "rectangle.split.3x1", shortcut: keys.keys("toggletiling"),
                            checked: wm.tilingEnabled, enabled: trusted, hidden: true, keywords: "enable disable pause toggle",
                            keepOpen: true, action: { wm.toggleTiling() }))

        let wsName = state?.workspace.map { "Workspace \($0)" } ?? "Desktop"
        out.append(.label("where", layout.map { "\(wsName) · \($0.title)" } ?? wsName))
        let summary = wm.workspaceSummary()
        if wm.config.virtualWorkspaces && trusted {
            out.append(MenuItem(id: "workspaces", kind: .workspaces))
            let highest = summary.all.compactMap { Int($0.name) }.max() ?? 0
            for n in 1...max(9, min(highest, 10)) {
                out.append(MenuItem(id: "ws-\(n)", label: "Go to Workspace \(n)", shortcut: keys.keys("workspace", "\(n)"),
                                    hidden: true, keywords: "switch space desktop", action: { wm.showWorkspace("\(n)") }))
            }
        }
        out.append(.sep("s1"))

        var layoutItems: [MenuItem] = [
            MenuItem(id: "picker", kind: .layoutPicker),
            MenuItem(id: "next-layout", label: "Next Layout", symbol: "chevron.right", shortcut: keys.keys("cyclelayout", "next"),
                     enabled: trusted, hidden: true, keepOpen: true, action: { wm.dispatch("cyclelayout", "next") }),
            MenuItem(id: "prev-layout", label: "Previous Layout", symbol: "chevron.left", shortcut: keys.keys("cyclelayout", "prev"),
                     enabled: trusted, hidden: true, keepOpen: true, action: { wm.dispatch("cyclelayout", "prev") }),
        ]
        layoutItems += Layout.allCases.map { l in
            MenuItem(id: "layout-\(l.rawValue)", kind: .radio, label: l.title, shortcut: keys.keys("layout", l.rawValue), checked: l == layout,
                     enabled: trusted, hidden: true, keywords: "layout \(l.blurb)", action: { wm.dispatch("layout", l.rawValue) })
        }
        out.append(MenuItem(id: "layout", kind: .sub, label: "Layout", symbol: "square.grid.2x2", value: layout?.title,
                            enabled: trusted, width: 276, children: layoutItems))

        if wm.config.virtualWorkspaces && trusted {
            let incoming = wm.windowsOnOtherDesktops().map { w in
                let app = NSRunningApplication(processIdentifier: w.pid)
                let title = w.element.string(kAXTitleAttribute) ?? "Untitled"
                return MenuItem(id: "bring-\(w.id)", label: title.isEmpty ? "Untitled" : title, image: app?.icon,
                                value: app?.localizedName, keywords: "bring import window desktop space",
                                action: { wm.bringWindowHere(w) })
            }
            if !incoming.isEmpty {
                out.append(MenuItem(id: "bring-window", kind: .sub, label: "Bring Window Here", symbol: "rectangle.badge.arrow.down",
                                    keywords: "import other desktops spaces", width: 340, children: incoming))
            }
        }

        out.append(.sep("s2"))

        out.append(MenuItem(id: "settings", label: "Settings…", symbol: "gearshape", shortcut: ["⌘", ","], keywords: "preferences options",
                            rotates: true, action: { SettingsWindow.shared.show(pane: nil) }))
        let paused = TutorialLesson.paused
        out.append(MenuItem(id: "tutorial", label: paused == nil ? "Keyboard Tutorial…" : "Resume Tutorial…", symbol: "graduationcap",
                            value: paused?.name, enabled: trusted, keywords: "learn practice drill keys lessons onboarding help",
                            action: { Onboarding.shared.startTutorial() }))
        out.append(MenuItem(id: "help", kind: .sub, label: "Help", symbol: "questionmark.circle", children: [
            MenuItem(id: "map", label: "Shortcut Map", symbol: "keyboard", shortcut: ["⌘", "/"], keywords: "keys overview cheat sheet",
                     action: { SettingsWindow.shared.show(pane: .shortcuts, map: true) }),
            MenuItem(id: "keyhelp", label: "Keyboard Help", symbol: "keyboard.badge.ellipsis", shortcut: keys.modeChord,
                     enabled: trusted, hidden: true, keywords: "keys overlay cheat sheet window mode", action: { KeyHelp.shared.showFromMenu(preferredMode: keys.modeName) }),
            MenuItem(id: "tour", label: "Quick Tour", symbol: "play.circle", enabled: trusted,
                     keywords: "learn tutorial onboarding keyboard tour", action: { Onboarding.shared.startTour() }),
            MenuItem(id: "tutorial-restart", label: "Restart Tutorial", symbol: "arrow.counterclockwise", enabled: trusted,
                     hidden: true, keywords: "learn tutorial start over", action: { Onboarding.shared.startTutorial(fromStart: true) }),
            MenuItem(id: "tips", kind: .check, label: "Show Tips", checked: Tips.shared.enabled, hidden: true, keywords: "hints help tooltips",
                     keepOpen: true, action: { Tips.shared.enabled.toggle() }),
            MenuItem(id: "reload", label: "Reload Config", symbol: "arrow.triangle.2.circlepath", shortcut: keys.keys("reload"),
                     hidden: true, keywords: "refresh file", keepOpen: true, rotates: true, action: { wm.reload() }),
            MenuItem(id: "updates", label: "Check for Updates…", symbol: "arrow.down.circle", keywords: "version upgrade",
                     action: { AppDelegate.checkForUpdates() }),
        ]))
        out.append(.sep("s3"))
        out.append(MenuItem(id: "quit", kind: .footer, label: "Quit Ouch", shortcut: ["⌘", "Q"], keywords: "exit",
                            action: { NSApp.terminate(nil) }))
        return out
    }

    func item(_ id: String, in list: [MenuItem]? = nil) -> MenuItem? {
        for i in list ?? items {
            if i.id == id { return i }
            if let found = item(id, in: i.children) { return found }
        }
        return nil
    }

    func column(_ level: Int) -> [MenuItem] {
        if !query.isEmpty { return level == 0 ? results.map(\.item) : [] }
        guard level > 0 else { return items }
        guard level <= path.count, let parent = item(path[level - 1]) else { return [] }
        return parent.children
    }

    func hover(_ item: MenuItem, level: Int) {
        guard item.selectable else { return }
        highlight[level] = item.id
        trimWork?.cancel()
        openWork?.cancel()
        let open = path.count > level ? path[level] : nil
        if item.kind == .sub {
            guard open != item.id else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                withAnimation(Motion.easeOut) { self.path = Array(self.path.prefix(level)) + [item.id] }
            }
            openWork = work
            opening = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        } else if open != nil {
            let work = DispatchWorkItem { [weak self] in self?.trim(to: level) }
            trimWork = work
            trimLevel = level
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

}
