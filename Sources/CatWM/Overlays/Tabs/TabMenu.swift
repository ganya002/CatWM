import AppKit

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
                            shortcut: focused ? ShortcutIndex().keys("moveoutofgroup") : [],
                            action: { manager.untab(id) }))
        if let workspaces = workspaceMenu(id, manager) { out.append(workspaces) }
        out.append(.sep("s1"))
        out.append(MenuItem(id: "close", label: "Close tab", danger: true, action: { _ = manager.closeWindow(id) }))
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
