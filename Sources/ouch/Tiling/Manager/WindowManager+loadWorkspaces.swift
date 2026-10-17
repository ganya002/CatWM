import AppKit

extension WindowManager {
    func loadWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let d = UserDefaults.standard
        for (k, v) in d.dictionary(forKey: "ws.windows") as? [String: String] ?? [:] {
            if let id = CGWindowID(k) { savedWorkspaceOf[id] = v }
        }
        for (k, v) in d.dictionary(forKey: "ws.owners") as? [String: String] ?? [:] {
            if let id = CGWindowID(k) { savedOwnerOf[id] = v }
        }
        monitorOf = d.dictionary(forKey: "ws.monitors") as? [String: String] ?? [:]
        labels = d.dictionary(forKey: "ws.labels") as? [String: String] ?? [:]
        virtualShown = d.dictionary(forKey: "ws.shown") as? [String: String] ?? [:]
        for (k, v) in d.dictionary(forKey: "ws.home") as? [String: NSNumber] ?? [:] { homeSpace[k] = v.uint64Value }
        for (k, v) in d.dictionary(forKey: "ws.floating") as? [String: Bool] ?? [:] {
            if let id = CGWindowID(k) { savedFloating[id] = v }
        }
        for (ws, v) in d.dictionary(forKey: "ws.layouts") as? [String: String] ?? [:] where isVirtual(ws) {
            let parts = v.split(separator: " ").map(String.init)
            guard let layout = parts.first.flatMap(Layout.init(rawValue:)) else { continue }
            let st = state(workspace: ws)
            st.layout = layout
            if parts.count > 1, let r = Double(parts[1]) { st.ratio = min(0.9, max(0.1, CGFloat(r))) }
            if parts.count > 2, let m = Int(parts[2]) { st.mainCount = max(1, min(10, m)) }
        }
        monitorOf = monitorOf.filter { isVirtual($0.key) }
    }

    func owner(_ w: Window) -> String { "\(w.pid) \(w.bundleID ?? "")" }

    func saveWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let windowsMap = Dictionary(workspaceOf.filter { windows[$0.key] != nil && isVirtual($0.value) && !isPending($0.value) }.map { (String($0.key), $0.value) },
                                    uniquingKeysWith: { a, _ in a })
        let monitors = monitorOf.filter { isVirtual($0.key) && !isPending($0.key) }
        let floating = Dictionary(windowsMap.keys.compactMap { k in CGWindowID(k).flatMap { windows[$0]?.userFloating }.map { (k, $0) } },
                                  uniquingKeysWith: { a, _ in a })
        let layouts = Dictionary(states.filter { isVirtual($0.key) && !isPending($0.key) }
                                    .map { ($0.key, "\($0.value.layout.rawValue) \($0.value.ratio) \($0.value.mainCount)") },
                                 uniquingKeysWith: { a, _ in a })
        let key = "\(windowsMap.sorted { $0.key < $1.key })|\(monitors.sorted { $0.key < $1.key })|\(virtualShown.sorted { $0.key < $1.key })|\(homeSpace.sorted { $0.key < $1.key })|\(labels.sorted { $0.key < $1.key })|\(floating.sorted { $0.key < $1.key })|\(layouts.sorted { $0.key < $1.key })"
        guard key != lastSavedWorkspaces else { return }
        lastSavedWorkspaces = key
        let d = UserDefaults.standard
        d.set(windowsMap, forKey: "ws.windows")
        d.set(Dictionary(windowsMap.keys.compactMap { k in CGWindowID(k).flatMap { windows[$0] }.map { (k, owner($0)) } },
                         uniquingKeysWith: { a, _ in a }), forKey: "ws.owners")
        d.set(monitors, forKey: "ws.monitors")
        d.set(virtualShown, forKey: "ws.shown")
        d.set(homeSpace.mapValues { NSNumber(value: $0) }, forKey: "ws.home")
        d.set(labels, forKey: "ws.labels")
        d.set(floating, forKey: "ws.floating")
        d.set(layouts, forKey: "ws.layouts")
    }

    func showWorkspace(_ ws: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true, attempts: Int = 3) {
        let timing = TilingTiming("workspace", windows: windows.count)
        defer { timing.finish() }
        let screens = Screen.all()
        guard let here = currentScreen() ?? screens.first else { return }
        let monitor = monitorOf[ws].flatMap { u in screens.first { $0.uuid == u } } ?? here
        let leaving = virtualShown[monitor.uuid]
        if let cur = leaving, cur != ws { previousWorkspace[monitor.uuid] = cur }
        monitorOf[ws] = monitor.uuid
        virtualShown[monitor.uuid] = ws
        autoSwitchAfter = Date().addingTimeInterval(0.6)
        if !takesFocus, !isOnHomeSpace(monitor) { return }
        if !isOnHomeSpace(monitor), let home = homeSpace[monitor.uuid], let info = Spaces.list(display: monitor.uuid),
           let index = info.ids.firstIndex(of: home), let desktop = info.desktops.firstIndex(of: index) {
            guard attempts > 0 else { Log.info("workspaces: couldn't reach the home Space for \(ws)"); return }
            stageHomeSpace(ws, replacing: leaving, on: monitor, home: home)
            CGWarpMouseCursorPosition(monitor.center)
            guard let steps = goToSpace(desktop + 1) else { Log.info("workspaces: can't switch Spaces for \(ws)"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 0.15 * Double(steps)) { [weak self] in
                self?.showWorkspace(ws, focusing: preferred, attempts: attempts - 1)
            }
            return
        }
        let previous = shown[monitor.uuid]
        let changed = previous != ws
        model.show(ws, on: monitor.uuid)
        Log.debug("workspaces: showing \(ws) on \(monitor.ns.localizedName)")
        if changed, takesFocus, let previous { beginSlide(from: previous, to: ws, on: monitor) }
        refresh()
        timing.checkpoint("refresh")
        if changed, !quietWorkspaceHUD, config.enablesLayoutHUD, config.enablesLayoutHUDOnSpaceChange {
            let text = labels[ws].map { "\(ws) · \($0)" } ?? ws
            let layout = state(workspace: ws).layout
            DispatchQueue.main.async { [weak self] in
                guard self?.shown[monitor.uuid] == ws else { return }
                HUD.shared.show(text, layout: layout, on: monitor.ns)
            }
        }
        timing.checkpoint("hud")
        guard takesFocus else {
            onChange?()
            return
        }
        let candidates = [preferred?.id, lastFocused[ws]].compactMap { $0 } + order + Array(visible)
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == ws }), let w = windows[id] {
            focus(w)
        } else {
            parkFocus()
            if config.mouseFollowsFocus { CGWarpMouseCursorPosition(monitor.center) }
            CursorRefresh.soon()
        }
        timing.checkpoint("focus")
        onChange?()
        timing.checkpoint("notify")
    }

    func stageHomeSpace(_ ws: String, replacing old: String?, on s: Screen, home: UInt64) {
        guard config.virtualWorkspaces, isVirtual(ws) else { return }
        let timing = TilingTiming("stage-home", windows: windows.count)
        defer { timing.finish() }
        let screens = Screen.all()
        func onHome(_ id: CGWindowID) -> Bool { scanner.desktop.spaces[id]?.contains(home) == true }
        if let old, old != ws, isVirtual(old) {
            for id in order where workspaceOf[id] == old && onHome(id) { park(id, screens: screens) }
        }
        let arriving = order.filter { id in
            guard workspaceOf[id] == ws, let w = windows[id], !w.fullscreen, onHome(id),
                  !w.minimized,
                  NSRunningApplication(processIdentifier: w.pid)?.isHidden != true else { return false }
            return true
        }
        for id in arriving where floatsFreely(id) { unpark(floating: id, screens: screens) }
        let ids = arriving.filter { windows[$0]?.isFloating == false }
        let st = state(workspace: ws)
        guard tilingEnabled, !ids.isEmpty, let slots = layoutTargets(ids, st, on: s) else { return }
        var moves: [Animator.Move] = []
        for id in ids {
            guard let w = windows[id], let target = slots[id] else { continue }
            targets[id] = target
            if !(animator.destination(id) ?? w.cachedFrame).approxEqual(target) { moves.append(.init(window: w, to: target, bounds: s.visible)) }
        }
        animator.animate(moves, duration: 0)
        Log.debug("workspaces: staged \(ws) on the home Space (\(arriving.count) windows, parked \(old ?? "none"))")
    }

    func moveFocusedWindow(to ws: String, follow: Bool) {
        guard let w = focusedWindow(), workspaceOf[w.id] != ws else { return }
        moveWindow(w, toWorkspace: ws, follow: follow)
    }

}
