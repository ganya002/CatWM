import AppKit

extension WindowManager {
    func loadWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let defaults = UserDefaults.standard
        desktops.nativeCatalog.saved = (defaults.dictionary(forKey: "ws.nativeSpaces") ?? [:]).compactMapValues {
            $0 as? UInt64
        }
        desktops.nativeCatalog.homes = defaults.dictionary(forKey: "ws.nativeDisplays") as? [String: String] ?? [:]
        desktops.nativeCatalog.uuids = defaults.dictionary(forKey: "ws.nativeSpaceUUIDs") as? [String: String] ?? [:]
        for (key, value) in defaults.dictionary(forKey: "ws.owners") as? [String: String] ?? [:] {
            if let id = CGWindowID(key) { floats.savedOwnerOf[id] = value }
        }
        monitorOf = defaults.dictionary(forKey: "ws.monitors") as? [String: String] ?? [:]
        labels = defaults.dictionary(forKey: "ws.labels") as? [String: String] ?? [:]
        virtualShown = defaults.dictionary(forKey: "ws.shown") as? [String: String] ?? [:]
        for (key, value) in defaults.dictionary(forKey: "ws.home") ?? [:] {
            if let space = value as? UInt64 { desktops.homeSpace[key] = space }
        }
        for (key, value) in defaults.dictionary(forKey: "ws.floating") as? [String: Bool] ?? [:] {
            if let id = CGWindowID(key) { floats.savedFloating[id] = value }
        }
        loadNativeMigration(defaults)
        ["ws.windows", "ws.owners", "ws.floating"].forEach(defaults.removeObject(forKey:))
        loadWorkspaceLayouts(defaults)
        loadTilingRecovery(defaults: defaults)
        monitorOf = monitorOf.filter { isVirtual($0.key) }
    }

    private func loadWorkspaceLayouts(_ defaults: UserDefaults) {
        let saved = defaults.dictionary(forKey: "ws.layouts") as? [String: String] ?? [:]
        for (workspace, value) in saved where isVirtual(workspace) {
            let parts = value.split(separator: " ").map(String.init)
            guard let layout = parts.first.flatMap(Layout.init(rawValue:)) else { continue }
            let screenState = state(workspace: workspace)
            screenState.layout = layout
            if parts.count > 1, let ratio = Double(parts[1]) {
                screenState.ratio = min(0.9, max(0.1, CGFloat(ratio)))
            }
            if parts.count > 2, let mainCount = Int(parts[2]) {
                screenState.mainCount = max(1, min(10, mainCount))
            }
        }
    }

    func owner(_ window: Window) -> String { "\(window.pid) \(window.bundleID ?? "")" }

    func saveWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let monitors = monitorOf.filter { isVirtual($0.key) && !isPending($0.key) }
        let layouts = Dictionary(
            states.filter { isVirtual($0.key) && !isPending($0.key) }
                .map { ($0.key, "\($0.value.layout.rawValue) \($0.value.ratio) \($0.value.mainCount)") },
            uniquingKeysWith: { first, _ in first })
        let key = [
            "\(monitors.sorted { $0.key < $1.key })",
            "\(virtualShown.sorted { $0.key < $1.key })",
            "\(desktops.homeSpace.sorted { $0.key < $1.key })",
            "\(labels.sorted { $0.key < $1.key })",
            "\(layouts.sorted { $0.key < $1.key })"
        ].joined(separator: "|")
        guard key != lastSavedWorkspaces else { return }
        lastSavedWorkspaces = key
        let defaults = UserDefaults.standard
        defaults.set(monitors, forKey: "ws.monitors")
        defaults.set(virtualShown, forKey: "ws.shown")
        defaults.set(desktops.homeSpace, forKey: "ws.home")
        defaults.set(labels, forKey: "ws.labels")
        defaults.set(layouts, forKey: "ws.layouts")
    }

    func showWorkspace(
        _ workspace: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true
    ) {
        guard config.virtualWorkspaces else { return }
        showNativeWorkspace(workspace, focusing: preferred, focus: takesFocus, quiet: closeAndSort.quietWorkspaceHUD)
    }

    func showWorkspaceHUD(_ workspace: String, on monitor: Screen) {
        let number = workspaceNumber(workspace)
        let text = labels[workspace].map { "\(number) · \($0)" } ?? number
        let layout = state(workspace: workspace).layout
        DispatchQueue.main.async { [weak self] in
            guard self?.shown[monitor.uuid] == workspace else { return }
            self?.surface.showHUD(text, layout: layout, on: monitor.nsScreen)
        }
    }

    func focusShownWorkspace(_ workspace: String, preferred: Window?, on screen: Screen) {
        let candidates = [preferred?.id, lastFocused[workspace]].compactMap(\.self) + order
        if let id = candidates.first(where: { id in
            workspaceOf[id] == workspace && windows[id].map { window in
                !window.minimized && NSRunningApplication(processIdentifier: window.pid)?.isHidden != true
            } == true
        }), let window = windows[id] {
            focus(window, warp: !screen.frame.contains(mouseLocation()))
        } else {
            parkFocus(on: screen)
        }
    }

    func moveFocusedWindow(to workspace: String, follow: Bool) {
        guard let window = focusedWindow() else { return }
        moveWindowAndTabs(window.id, to: workspace, follow: follow)
    }

    func moveWindowAndTabs(_ id: CGWindowID, to workspace: String, follow: Bool) {
        guard workspaceOf[id] != nil, workspaceOf[id] != workspace else { return }
        moveTabs(of: id, to: workspace) { member, lead in
            if let member = windows[member] { moveWindow(member, toWorkspace: workspace, follow: follow && lead) }
        }
    }
}
