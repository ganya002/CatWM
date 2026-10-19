import AppKit

extension WindowManager {
    func loadWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let defaults = UserDefaults.standard
        for (key, value) in defaults.dictionary(forKey: "ws.windows") as? [String: String] ?? [:] {
            if let id = CGWindowID(key) { savedWorkspaceOf[id] = value }
        }
        for (key, value) in defaults.dictionary(forKey: "ws.owners") as? [String: String] ?? [:] {
            if let id = CGWindowID(key) { savedOwnerOf[id] = value }
        }
        monitorOf = defaults.dictionary(forKey: "ws.monitors") as? [String: String] ?? [:]
        labels = defaults.dictionary(forKey: "ws.labels") as? [String: String] ?? [:]
        virtualShown = defaults.dictionary(forKey: "ws.shown") as? [String: String] ?? [:]
        for (key, value) in defaults.dictionary(forKey: "ws.home") ?? [:] {
            if let space = value as? UInt64 { homeSpace[key] = space }
        }
        for (key, value) in defaults.dictionary(forKey: "ws.floating") as? [String: Bool] ?? [:] {
            if let id = CGWindowID(key) { savedFloating[id] = value }
        }
        loadWorkspaceLayouts(defaults)
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
        let windowsMap = Dictionary(
            workspaceOf
                .filter { windows[$0.key] != nil && isVirtual($0.value) && !isPending($0.value) }
                .map { (String($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first })
        let monitors = monitorOf.filter { isVirtual($0.key) && !isPending($0.key) }
        let floating = Dictionary(
            windowsMap.keys.compactMap { key -> (String, Bool)? in
                guard let window = CGWindowID(key).flatMap({ windows[$0] }),
                      case .chosen(let floating) = window.userFloating else { return nil }
                return (key, floating)
            },
            uniquingKeysWith: { first, _ in first })
        let layouts = Dictionary(
            states.filter { isVirtual($0.key) && !isPending($0.key) }
                .map { ($0.key, "\($0.value.layout.rawValue) \($0.value.ratio) \($0.value.mainCount)") },
            uniquingKeysWith: { first, _ in first })
        let key = [
            "\(windowsMap.sorted { $0.key < $1.key })",
            "\(monitors.sorted { $0.key < $1.key })",
            "\(virtualShown.sorted { $0.key < $1.key })",
            "\(homeSpace.sorted { $0.key < $1.key })",
            "\(labels.sorted { $0.key < $1.key })",
            "\(floating.sorted { $0.key < $1.key })",
            "\(layouts.sorted { $0.key < $1.key })"
        ].joined(separator: "|")
        guard key != lastSavedWorkspaces else { return }
        lastSavedWorkspaces = key
        let defaults = UserDefaults.standard
        defaults.set(windowsMap, forKey: "ws.windows")
        let owners = Dictionary(
            windowsMap.keys.compactMap { key in
                CGWindowID(key).flatMap { windows[$0] }.map { (key, owner($0)) }
            },
            uniquingKeysWith: { first, _ in first })
        defaults.set(owners, forKey: "ws.owners")
        defaults.set(monitors, forKey: "ws.monitors")
        defaults.set(virtualShown, forKey: "ws.shown")
        defaults.set(homeSpace, forKey: "ws.home")
        defaults.set(labels, forKey: "ws.labels")
        defaults.set(floating, forKey: "ws.floating")
        defaults.set(layouts, forKey: "ws.layouts")
    }

    func showWorkspace(
        _ workspace: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true, attempts: Int = 3
    ) {
        let timing = TilingTiming("workspace", windows: windows.count)
        defer { timing.finish() }
        let screens = Screen.all()
        guard let here = currentScreen() ?? screens.first else { return }
        let monitor = monitorOf[workspace].flatMap { uuid in screens.first { $0.uuid == uuid } } ?? here
        let leaving = virtualShown[monitor.uuid]
        if let cur = leaving, cur != workspace { previousWorkspace[monitor.uuid] = cur }
        monitorOf[workspace] = monitor.uuid
        virtualShown[monitor.uuid] = workspace
        autoSwitchAfter = Date().addingTimeInterval(0.6)
        if !takesFocus, !isOnHomeSpace(monitor) { return }
        if reachHomeSpace(workspace, leaving: leaving, on: monitor, focusing: preferred, attempts: attempts) {
            return
        }
        let previous = shown[monitor.uuid]
        let changed = previous != workspace
        model.show(workspace, on: monitor.uuid)
        Log.debug("workspaces: showing \(workspace) on \(monitor.nsScreen.localizedName)")
        if changed, takesFocus, let previous { beginSlide(from: previous, to: workspace, on: monitor) }
        refresh()
        timing.checkpoint("refresh")
        if changed, !quietWorkspaceHUD, config.enablesLayoutHUD, config.enablesLayoutHUDOnSpaceChange {
            showWorkspaceHUD(workspace, on: monitor)
        }
        timing.checkpoint("hud")
        guard takesFocus else {
            onChange?()
            return
        }
        focusShownWorkspace(workspace, preferred: preferred, on: monitor)
        timing.checkpoint("focus")
        onChange?()
        timing.checkpoint("notify")
    }

    private func reachHomeSpace(
        _ workspace: String, leaving: String?, on monitor: Screen, focusing preferred: Window?, attempts: Int
    ) -> Bool {
        guard !isOnHomeSpace(monitor), let home = homeSpace[monitor.uuid],
              let info = Spaces.list(display: monitor.uuid),
              let index = info.ids.firstIndex(of: home),
              let desktop = info.desktops.firstIndex(of: index) else { return false }
        guard attempts > 0 else {
            Log.info("workspaces: couldn't reach the home Space for \(workspace)")
            return true
        }
        stageHomeSpace(workspace, replacing: leaving, on: monitor, home: home)
        CGWarpMouseCursorPosition(monitor.center)
        guard let steps = goToSpace(desktop + 1) else {
            Log.info("workspaces: can't switch Spaces for \(workspace)")
            return true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 0.15 * Double(steps)) { [weak self] in
            self?.showWorkspace(workspace, focusing: preferred, attempts: attempts - 1)
        }
        return true
    }

    private func showWorkspaceHUD(_ workspace: String, on monitor: Screen) {
        let text = labels[workspace].map { "\(workspace) · \($0)" } ?? workspace
        let layout = state(workspace: workspace).layout
        DispatchQueue.main.async { [weak self] in
            guard self?.shown[monitor.uuid] == workspace else { return }
            HUD.shared.show(text, layout: layout, on: monitor.nsScreen)
        }
    }

    private func focusShownWorkspace(_ workspace: String, preferred: Window?, on monitor: Screen) {
        let candidates = [preferred?.id, lastFocused[workspace]].compactMap(\.self) + order + Array(visible)
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == workspace }),
           let window = windows[id] {
            focus(window)
        } else {
            parkFocus()
            if config.mouseFollowsFocus { CGWarpMouseCursorPosition(monitor.center) }
            CursorRefresh.soon()
        }
    }

    func stageHomeSpace(_ workspace: String, replacing old: String?, on screen: Screen, home: UInt64) {
        guard config.virtualWorkspaces, isVirtual(workspace) else { return }
        let timing = TilingTiming("stage-home", windows: windows.count)
        defer { timing.finish() }
        let screens = Screen.all()
        func onHome(_ id: CGWindowID) -> Bool { scanner.desktop.spaces[id]?.contains(home) == true }
        if let old, old != workspace, isVirtual(old) {
            for id in order where workspaceOf[id] == old && onHome(id) { park(id, screens: screens) }
        }
        let arriving = order.filter { id in
            guard workspaceOf[id] == workspace, let window = windows[id], !window.fullscreen, onHome(id),
                  !window.minimized,
                  NSRunningApplication(processIdentifier: window.pid)?.isHidden != true else { return false }
            return true
        }
        for id in arriving where floatsFreely(id) { unpark(floating: id, screens: screens) }
        let ids = arriving.filter { windows[$0]?.isFloating == false }
        let screenState = state(workspace: workspace)
        guard tilingEnabled, !ids.isEmpty, let slots = layoutTargets(ids, screenState, on: screen) else { return }
        var moves: [Animator.Move] = []
        for id in ids {
            guard let window = windows[id], let target = slots[id] else { continue }
            targets[id] = target
            if !(animator.destination(id) ?? window.cachedFrame).approxEqual(target) {
                moves.append(.init(window: window, to: target, bounds: screen.visible))
            }
        }
        animator.animate(moves, duration: 0)
        Log.debug(
            "workspaces: staged \(workspace) on the home Space (\(arriving.count) windows, parked \(old ?? "none"))"
        )
    }

    func moveFocusedWindow(to workspace: String, follow: Bool) {
        guard let window = focusedWindow(), workspaceOf[window.id] != workspace else { return }
        moveWindow(window, toWorkspace: workspace, follow: follow)
    }
}
