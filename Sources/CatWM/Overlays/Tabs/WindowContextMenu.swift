import AppKit
import CatWMKit

enum WindowContextMenu {
    struct Display {
        let index: Int
        let name: String
        let keys: [String]
    }

    struct Input {
        var floating: Bool
        var grouped: Bool
        var tiled: Bool
        var workspaces: [String]
        var currentWorkspace: String?
        var displays: [Display]
        var keys: (_ dispatcher: String, _ args: String) -> [String]
        var run: (_ dispatcher: String, _ args: String) -> Void
    }

    static func open(_ id: CGWindowID) {
        let manager = WindowManager.shared
        guard let window = manager.windows[id] else { return }
        manager.focus(window, warp: false)
        let keys = ShortcutIndex()
        let input = input(for: window, keys: keys.keys)
        Popup.shared.context({ items(input) })
    }

    static func items(_ input: Input) -> [MenuItem] {
        let keys = input.keys, run = input.run
        var out: [MenuItem] = [
            MenuItem(id: "float", label: "Toggle floating", shortcut: keys(WindowActions.togglefloating.name, ""),
                     action: { run(WindowActions.togglefloating.name, "") }),
            MenuItem(id: "fullscreen", label: "Fullscreen", shortcut: keys(WindowActions.fullscreen.name, ""),
                     action: { run(WindowActions.fullscreen.name, "") })
        ]
        if !input.workspaces.isEmpty {
            let children = input.workspaces.map { name in
                MenuItem(id: "ws-\(name)", kind: .radio, label: "Workspace \(name)",
                         shortcut: keys(WindowActions.movetoworkspace.name, name),
                         checked: name == input.currentWorkspace,
                         action: { run(WindowActions.movetoworkspace.name, name) })
            }
            out.append(MenuItem(id: "workspace", kind: .sub, label: "Move to workspace", children: children))
        }
        if !input.displays.isEmpty {
            let children = input.displays.map { display in
                MenuItem(id: "display-\(display.index)", label: display.name, shortcut: display.keys,
                         action: { run(WindowActions.movewindow.name, "mon:\(display.index)") })
            }
            out.append(MenuItem(id: "display", kind: .sub, label: "Move to display", children: children))
        }
        if input.grouped {
            out.append(MenuItem(id: "out", label: "Move out of group",
                                shortcut: keys(WindowActions.moveoutofgroup.name, ""),
                                action: { run(WindowActions.moveoutofgroup.name, "") }))
        }
        if input.tiled {
            out.append(MenuItem(id: "swap", label: "Swap with master",
                                shortcut: keys(WindowActions.layoutmsg.name, "swapwithmaster"),
                                action: { run(WindowActions.layoutmsg.name, "swapwithmaster") }))
        }
        out.append(.sep("s1"))
        out.append(MenuItem(id: "retile", label: "Retile", shortcut: keys(WindowActions.retile.name, ""),
                            action: { run(WindowActions.retile.name, "") }))
        return out
    }

    private static func input(for window: Window, keys: @escaping (String, String) -> [String]) -> Input {
        let manager = WindowManager.shared
        let summary = manager.workspaceSummary()
        let screens = Screen.all()
        var displays: [Display] = []
        if screens.count > 1, let source = manager.screen(of: window, in: screens) {
            for (index, screen) in screens.enumerated() where screen.uuid != source.uuid {
                let direction = Direction.allCases.first {
                    manager.screen(from: source, spec: $0.rawValue, in: screens)?.uuid == screen.uuid
                }
                let shortcut = direction.map { keys(WindowActions.movewindow.name, "mon:\($0.rawValue)") } ?? []
                displays.append(Display(index: index, name: screen.name, keys: shortcut))
            }
        }
        return Input(floating: window.isFloating, grouped: manager.tabs.isGrouped(window.id),
                     tiled: !window.isFloating && manager.tilingEnabled,
                     workspaces: summary.all.map(\.name), currentWorkspace: manager.workspaceOf[window.id]
                         .map(manager.workspaceNumber),
                     displays: displays, keys: keys, run: { manager.dispatch($0, $1, inMode: true) })
    }
}

enum TabMenu {
    static func items(for id: CGWindowID) -> [MenuItem] {
        let manager = WindowManager.shared
        guard manager.windows[id] != nil else { return [] }
        let isActive = manager.tabs.group(of: id)?.active == id
        let focused = manager.focusedWindow()?.id == id
        var out: [MenuItem] = []
        if !isActive {
            out.append(MenuItem(id: "select", label: "Select tab", action: { manager.selectTab(id) }))
        }
        out.append(MenuItem(id: "out", label: "Move out of group",
                            shortcut: focused ? ShortcutIndex().keys(WindowActions.moveoutofgroup.name) : [],
                            action: { manager.untab(id) }))
        if let workspaces = workspaceMenu(id, manager) { out.append(workspaces) }
        out.append(.sep("s1"))
        out.append(MenuItem(id: "close", label: "Close tab", danger: true, action: { _ = manager.closeWindow(id) }))
        let others = (manager.tabs.group(of: id)?.members ?? []).filter { $0 != id }
        if !others.isEmpty {
            out.append(MenuItem(id: "close-others", label: "Close other tabs", danger: true,
                                action: { others.forEach { _ = manager.closeWindow($0) } }))
        }
        return out
    }

    private static func workspaceMenu(_ id: CGWindowID, _ manager: WindowManager) -> MenuItem? {
        guard manager.config.virtualWorkspaces else { return nil }
        let all = manager.workspaceSummary().all
        guard !all.isEmpty else { return nil }
        let current = manager.workspaceOf[id].map(manager.workspaceNumber)
        let children = all.map { entry in
            MenuItem(id: "ws-\(entry.name)", kind: .radio, label: "Workspace \(entry.name)",
                     checked: entry.name == current, action: {
                         guard let workspace = manager.resolveWorkspace(entry.name) else { return }
                         manager.moveWindowAndTabs(id, to: workspace, follow: false)
                     })
        }
        return MenuItem(id: "workspace", kind: .sub, label: "Move to workspace", children: children)
    }
}
