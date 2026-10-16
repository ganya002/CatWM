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
        shown[monitor.uuid] = ws
        Log.debug("workspaces: showing \(ws) on \(monitor.ns.localizedName)")
        if changed, takesFocus, let previous { beginSlide(from: previous, to: ws, on: monitor) }
        refresh()
        if changed, !quietWorkspaceHUD, config.enablesLayoutHUD, config.enablesLayoutHUDOnSpaceChange {
            HUD.shared.show(labels[ws].map { "\(ws) · \($0)" } ?? ws, layout: state(workspace: ws).layout, on: monitor.ns)
        }
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
        onChange?()
    }

    private func stageHomeSpace(_ ws: String, replacing old: String?, on s: Screen, home: UInt64) {
        guard config.virtualWorkspaces, isVirtual(ws) else { return }
        let screens = Screen.all()
        func onHome(_ id: CGWindowID) -> Bool { Spaces.of(window: id).contains(home) }
        if let old, old != ws, isVirtual(old) {
            for id in order where workspaceOf[id] == old && onHome(id) { park(id, screens: screens) }
        }
        let arriving = order.filter { id in
            guard workspaceOf[id] == ws, let w = windows[id], !w.isNativeFullscreen, onHome(id),
                  w.element.bool(kAXMinimizedAttribute) != true,
                  NSRunningApplication(processIdentifier: w.pid)?.isHidden != true else { return false }
            return true
        }
        for id in arriving where floatsFreely(id) { unpark(floating: id, screens: screens) }
        let ids = arriving.filter { windows[$0]?.isFloating == false }
        let st = state(workspace: ws)
        guard tilingEnabled, !ids.isEmpty, let (raw, gap) = rawSlots(ids, on: s, st, ratio: st.ratio) else { return }
        let slots = fitMinimums(raw, mins: ids.map { minSizes[$0] }, gap: gap)
        var moves: [Animator.Move] = []
        for (id, slot) in zip(ids, slots) {
            guard let w = windows[id] else { continue }
            let target = id == st.zoomed ? usableRect(s).pixelAligned : slot
            targets[id] = target
            if !w.frame.approxEqual(target) { moves.append(.init(window: w, to: target, bounds: s.visible)) }
        }
        animator.animate(moves, duration: 0)
        Log.debug("workspaces: staged \(ws) on the home Space (\(arriving.count) windows, parked \(old ?? "none"))")
    }


    func moveFocusedWindow(to ws: String, follow: Bool) {
        guard let w = focusedWindow(), workspaceOf[w.id] != ws else { return }
        moveWindow(w, toWorkspace: ws, follow: follow)
    }

    private func moveWindow(_ w: Window, toWorkspace ws: String, follow: Bool) {
        let screens = Screen.all()
        guard config.virtualWorkspaces, isVirtual(ws), !workspaceMoves.contains(w.id),
              let monitor = monitorOf[ws].flatMap({ uuid in screens.first { $0.uuid == uuid } })
                ?? currentScreen() ?? screens.first,
              let home = homeSpace[monitor.uuid], let info = Spaces.list(display: monitor.uuid),
              info.desktops.contains(where: { info.ids[$0] == home }), !w.isNativeFullscreen else { return }
        if Spaces.of(window: w.id) == [home] {
            assignWindow(w, toWorkspace: ws, from: workspaceOf[w.id], display: monitor.uuid, follow: follow)
            return
        }
        let known = windows[w.id] != nil, from = workspaceOf[w.id], frame = w.frame
        workspaceMoves.insert(w.id)
        autoSwitchAfter = Date().addingTimeInterval(0.7)
        if !known { windows[w.id] = w; order.append(w.id) }
        workspaceOf[w.id] = ws
        monitorOf[ws] = monitor.uuid
        snapNextPlacement.insert(w.id)
        refresh(instant: true, placing: [w.id])
        animator.afterPendingWrites { [weak self] in
            let displayBatch = WindowServerUpdates.shared.begin()
            let moveStarted = Date()
            func release() {
                let held = Int(Date().timeIntervalSince(moveStarted) * 1000)
                let watchdog = Int(WindowServerUpdates.shared.maximumHold * 1000)
                Log.info("workspaces: import of \(w.id) held the display \(held) ms\(held > watchdog ? " (watchdog let go at \(watchdog) ms)" : "")")
                displayBatch?.finish()
            }
            Spaces.move(window: w.id, to: home, waitUntilOnScreen: self?.isOnHomeSpace(monitor) ?? false) { [weak self] moved in
                guard let self else { release(); return }
                workspaceMoves.remove(w.id)
                guard moved, w.isValid, config.virtualWorkspaces, homeSpace[monitor.uuid] == home else {
                    Log.info("workspaces: direct move of \(w.id) to \(home) failed")
                    HUD.shared.show("macOS couldn't move this window", on: monitor.ns)
                    if known { workspaceOf[w.id] = from } else { forget(w.id) }
                    if w.isValid, !frame.isNull { w.setFrame(frame) }
                    refresh()
                    release()
                    return
                }
                Log.info("workspaces: moved \(w.id) to home Desktop in \(Int(Date().timeIntervalSince(moveStarted) * 1000)) ms")
                if !known { watch(w) }
                release()
                assignWindow(w, toWorkspace: ws, from: from, display: monitor.uuid, follow: follow)
            }
        }
    }

    private func assignWindow(_ w: Window, toWorkspace ws: String, from: String?, display: String, follow: Bool) {
        if windows[w.id] == nil {
            windows[w.id] = w
            order.append(w.id)
            watch(w)
        }
        monitorOf[ws] = display
        workspaceOf[w.id] = ws
        lastFocused[ws] = w.id
        if let from, lastFocused[from] == w.id { lastFocused[from] = nil }
        corrections[w.id] = nil
        if follow {
            showWorkspace(ws, focusing: w)
        } else {
            autoSwitchAfter = Date().addingTimeInterval(0.6)
            refresh()
            guard isShown(from) else { return }
            if let next = order.first(where: { workspaceOf[$0] == from && visible.contains($0) }).flatMap({ windows[$0] }) {
                focus(next)
            } else {
                parkFocus()
            }
        }
    }


    func windowsOnOtherDesktops() -> [Window] {
        guard config.virtualWorkspaces, isStarted, Spaces.canMoveWindows,
              let s = currentScreen(), isOnHomeSpace(s) else { return [] }
        let deadline = Date().addingTimeInterval(0.3)
        let screens = Screen.all()
        let desktops = Set(screens.flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        let homes = Set(homeSpace.values)
        var offDesktop: [pid_t: Set<CGWindowID>] = [:]
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for d in list where (d[kCGWindowLayer as String] as? Int) == 0 && (d[kCGWindowIsOnscreen as String] as? Bool) != true {
            guard let n = d[kCGWindowNumber as String] as? Int, let pid = d[kCGWindowOwnerPID as String] as? Int,
                  !workspaceMoves.contains(CGWindowID(n)) else { continue }
            let membership = Spaces.of(window: CGWindowID(n))
            guard membership.count == 1, let space = membership.first, desktops.contains(space), !homes.contains(space) else { continue }
            offDesktop[pid_t(pid), default: []].insert(CGWindowID(n))
        }
        var result: [Window] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            guard let ids = offDesktop[app.processIdentifier] else { continue }
            guard Date() < deadline else { break }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            let known = windows.values.filter { $0.pid == app.processIdentifier && ids.contains($0.id) }.map(\.element)
            let candidates = (known.count < ids.count ? element.elements(kAXWindowsAttribute) : []) + known
            var seen: Set<CGWindowID> = []
            for el in candidates {
                guard Date() < deadline else { break }
                AXUIElementSetMessagingTimeout(el, 0.1)
                guard let id = el.windowID, ids.contains(id), seen.insert(id).inserted,
                      el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      el.bool(kAXMinimizedAttribute) != true, el.bool("AXFullScreen") != true else { continue }
                let w = windows[id] ?? Window(id: id, element: el, pid: app.processIdentifier, bundleID: app.bundleIdentifier)
                if w.naturalFrame.isNull { w.naturalFrame = w.frame; w.autoFloating = shouldFloat(w) }
                result.append(w)
            }
        }
        return result.sorted { ($0.bundleID ?? "", $0.id) < ($1.bundleID ?? "", $1.id) }
    }

    func bringWindowHere(_ w: Window) {
        guard let s = currentScreen(), isOnHomeSpace(s), let ws = virtualShown[s.uuid] else { return }
        moveWindow(w, toWorkspace: ws, follow: false)
    }

    func prepareDockPull(at point: CGPoint) -> (() -> Void)? {
        let deadline = Date().addingTimeInterval(0.15)
        guard isStarted, config.virtualWorkspaces, !sortSession, dockArea.contains(point), Spaces.canMoveWindows,
              let display = Screen.all().first(where: { $0.frame.contains(point) }),
              isOnHomeSpace(display), let ws = virtualShown[display.uuid],
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.03)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.03)
        guard hit.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = hit.value(kAXURLAttribute) as? URL,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
              }), app.processIdentifier != getpid(), !app.isHidden else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.03)
        let candidates = [appElement.element(kAXFocusedWindowAttribute), appElement.element(kAXMainWindowAttribute)].compactMap { $0 }
            + focusOrder.compactMap { windows[$0] }.filter { $0.pid == app.processIdentifier }.map(\.element)
            + appElement.elements(kAXWindowsAttribute)
        let desktops = Set(Screen.all().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        var seen: Set<CGWindowID> = []
        for el in candidates {
            guard Date() < deadline else { return nil }
            AXUIElementSetMessagingTimeout(el, 0.03)
            guard let id = el.windowID, seen.insert(id).inserted else { continue }
            guard el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
            let membership = Spaces.of(window: id)
            guard membership.count == 1, let source = membership.first,
                  desktops.contains(source), !homeSpace.values.contains(source),
                  !workspaceMoves.contains(id), el.bool(kAXMinimizedAttribute) != true,
                  el.bool("AXFullScreen") != true else { return nil }
            let w = windows[id] ?? Window(id: id, element: el, pid: app.processIdentifier, bundleID: app.bundleIdentifier)
            return { [weak self] in
                guard let self, config.virtualWorkspaces, virtualShown[display.uuid] == ws,
                      isOnHomeSpace(display), w.isValid else { return }
                if w.naturalFrame.isNull { w.naturalFrame = w.frame; w.autoFloating = shouldFloat(w) }
                pendingFocus = nil
                Hotkeys.shared.setSubmap("")
                moveWindow(w, toWorkspace: ws, follow: true)
            }
        }
        return nil
    }


    func followFocus() {
        guard isStarted, let w = reportedFocusedWindow() else { return }
        if let p = pendingFocus {
            guard p.id == w.id else { return }
            pendingFocus = nil
        }
        if focusStamps[w.id] != focusClock { noteFocus(w.id) }
        focusOrder.removeAll { $0 == w.id }
        focusOrder.insert(w.id, at: 0)
        if focusOrder.count > 80 { focusOrder.removeLast(focusOrder.count - 80) }
        guard !sortSession else { return }
        guard config.virtualWorkspaces, let ws = workspaceOf[w.id], isVirtual(ws) else { return }
        if isShown(ws) { lastFocused[ws] = w.id; return }
        guard Date() > autoSwitchAfter else { return }
        guard isParked(w.frame, Screen.all()) else { scheduleRefresh(); return }
        if config.stayOnWorkspaceAfterClose, Date().timeIntervalSince(lastClose) < 1.0 {
            Log.debug("workspaces: ignoring focus on \(ws) right after a close")
            refocusCurrentWorkspace()
            return
        }
        Log.info("workspaces: \(w.bundleID ?? "a window") on workspace \(ws) was focused; switching")
        showWorkspace(ws, focusing: w)
    }

    private func refocusCurrentWorkspace() {
        guard let s = currentScreen(), let cur = virtualShown[s.uuid] else { return parkFocus() }
        let candidates = [lastFocused[cur]].compactMap { $0 } + order
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == cur }), let w = windows[id] {
            focus(w)
        } else {
            parkFocus()
        }
    }

    private func parkFocus() {
        let sink = focusSink ?? {
            let w = FocusSinkWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.alphaValue = 0.01
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
            focusSink = w
            return w
        }()
        if let primary = NSScreen.screens.first { sink.setFrameOrigin(NSPoint(x: 0, y: primary.frame.maxY - 1)) }
        sink.orderFrontRegardless()
        sink.makeKey()
        if !WindowServerFocus.focus(pid: getpid(), window: CGWindowID(sink.windowNumber)) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
