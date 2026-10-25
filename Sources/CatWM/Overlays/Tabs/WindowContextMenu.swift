import AppKit

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
            MenuItem(id: "float", label: "Toggle floating", shortcut: keys("togglefloating", ""),
                     action: { run("togglefloating", "") }),
            MenuItem(id: "fullscreen", label: "Fullscreen", shortcut: keys("fullscreen", ""),
                     action: { run("fullscreen", "") })
        ]
        if !input.workspaces.isEmpty {
            let children = input.workspaces.map { name in
                MenuItem(id: "ws-\(name)", kind: .radio, label: "Workspace \(name)",
                         shortcut: keys("movetoworkspace", name), checked: name == input.currentWorkspace,
                         action: { run("movetoworkspace", name) })
            }
            out.append(MenuItem(id: "workspace", kind: .sub, label: "Move to workspace", children: children))
        }
        if !input.displays.isEmpty {
            let children = input.displays.map { display in
                MenuItem(id: "display-\(display.index)", label: display.name, shortcut: display.keys,
                         action: { run("movewindow", "mon:\(display.index)") })
            }
            out.append(MenuItem(id: "display", kind: .sub, label: "Move to display", children: children))
        }
        if input.grouped {
            out.append(MenuItem(id: "out", label: "Move out of group", shortcut: keys("moveoutofgroup", ""),
                                action: { run("moveoutofgroup", "") }))
        }
        if input.tiled {
            out.append(MenuItem(id: "swap", label: "Swap with master", shortcut: keys("layoutmsg", "swapwithmaster"),
                                action: { run("layoutmsg", "swapwithmaster") }))
        }
        out.append(.sep("s1"))
        out.append(MenuItem(id: "retile", label: "Retile", shortcut: keys("retile", ""), action: { run("retile", "") }))
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
                displays.append(Display(index: index, name: screen.nsScreen.localizedName,
                                        keys: direction.map { keys("movewindow", "mon:\($0.rawValue)") } ?? []))
            }
        }
        return Input(floating: window.isFloating, grouped: manager.tabs.isGrouped(window.id),
                     tiled: !window.isFloating && manager.tilingEnabled,
                     workspaces: summary.all.map(\.name), currentWorkspace: manager.workspaceOf[window.id]
                         .map(manager.workspaceNumber),
                     displays: displays, keys: keys, run: { manager.dispatch($0, $1, inMode: true) })
    }
}
