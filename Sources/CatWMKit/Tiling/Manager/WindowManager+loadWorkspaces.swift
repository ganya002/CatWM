import AppKit

extension WindowManager {
    package func loadWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let defaults = Instance.defaults
        desktops.nativeCatalog.saved = (defaults.dictionary(forKey: DefaultsKey.wsNativeSpaces) ?? [:])
            .compactMapValues { $0 as? UInt64 }
        desktops.nativeCatalog.homes = defaults.dictionary(forKey: DefaultsKey.wsNativeDisplays)
            as? [String: String] ?? [:]
        desktops.nativeCatalog.uuids = defaults.dictionary(forKey: DefaultsKey.wsNativeSpaceUUIDs)
            as? [String: String] ?? [:]
        for (key, value) in defaults.dictionary(forKey: DefaultsKey.wsOwners) as? [String: String] ?? [:] {
            if let id = CGWindowID(key) { floats.savedOwnerOf[id] = value }
        }
        monitorOf = defaults.dictionary(forKey: DefaultsKey.wsMonitors) as? [String: String] ?? [:]
        labels = defaults.dictionary(forKey: DefaultsKey.wsLabels) as? [String: String] ?? [:]
        virtualShown = defaults.dictionary(forKey: DefaultsKey.wsShown) as? [String: String] ?? [:]
        for (key, value) in defaults.dictionary(forKey: DefaultsKey.wsHome) ?? [:] {
            if let space = value as? UInt64 { desktops.homeSpace[key] = space }
        }
        for (key, value) in defaults.dictionary(forKey: DefaultsKey.wsFloating) as? [String: Bool] ?? [:] {
            if let id = CGWindowID(key) { floats.savedFloating[id] = value }
        }
        loadNativeMigration(defaults)
        ["ws.windows", "ws.owners", "ws.floating"].forEach(defaults.removeObject(forKey:))
        loadWorkspaceLayouts(defaults)
        loadTilingRecovery(defaults: defaults)
        monitorOf = monitorOf.filter { isVirtual($0.key) }
    }

    private func loadWorkspaceLayouts(_ defaults: UserDefaults) {
        let saved = defaults.dictionary(forKey: DefaultsKey.wsLayouts) as? [String: String] ?? [:]
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

    package func owner(_ window: Window) -> String { "\(window.pid) \(window.bundleID ?? "")" }

    package func saveWorkspaces() {
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
        let defaults = Instance.defaults
        defaults.set(monitors, forKey: DefaultsKey.wsMonitors)
        defaults.set(virtualShown, forKey: DefaultsKey.wsShown)
        defaults.set(desktops.homeSpace, forKey: DefaultsKey.wsHome)
        defaults.set(labels, forKey: DefaultsKey.wsLabels)
        defaults.set(layouts, forKey: DefaultsKey.wsLayouts)
    }

    package func showWorkspace(
        _ workspace: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true
    ) {
        guard config.virtualWorkspaces else { return }
        showNativeWorkspace(workspace, focusing: preferred, focus: takesFocus, quiet: closeAndSort.quietWorkspaceHUD)
    }

    package func showWorkspaceHUD(_ workspace: String, on monitor: Screen) {
        let number = workspaceNumber(workspace)
        let text = labels[workspace].map { "\(number) · \($0)" } ?? number
        let layout = state(workspace: workspace).layout
        DispatchQueue.main.async { [weak self] in
            guard self?.shown[monitor.uuid] == workspace else { return }
            self?.surface.showHUD(text, layout: layout, on: monitor.nsScreen)
        }
    }

    package func focusShownWorkspace(_ workspace: String, preferred: Window?, on screen: Screen) {
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

    package func moveFocusedWindow(to workspace: String, follow: Bool) {
        guard let window = focusedWindow() else { return }
        moveWindowAndTabs(window.id, to: workspace, follow: follow)
    }

    package func moveWindowAndTabs(_ id: CGWindowID, to workspace: String, follow: Bool) {
        guard workspaceOf[id] != nil, workspaceOf[id] != workspace else { return }
        moveTabs(of: id, to: workspace) { member, lead in
            if let member = windows[member] { moveWindow(member, toWorkspace: workspace, follow: follow && lead) }
        }
    }
}
