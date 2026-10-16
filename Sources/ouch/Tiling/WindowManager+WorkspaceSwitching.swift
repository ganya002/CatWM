// Tiling: saves/loads workspaces, shows a workspace, moves windows between workspaces, Dock pulls.
import AppKit

extension WindowManager {

    // MARK: - Saving and loading workspaces

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
        // "layout ratio mainCount" per workspace, so a restart (or an update) keeps each one's arrangement.
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

    // MARK: - Showing a workspace

    /// Hyprland's `workspace`: shows it on its display (a new one opens on the focused display)
    /// and focuses the window you last used there.
    func showWorkspace(_ ws: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true, attempts: Int = 3) {
        let screens = Screen.all()
        guard let here = currentScreen() ?? screens.first else { return }
        let monitor = monitorOf[ws].flatMap { u in screens.first { $0.uuid == u } } ?? here
        let leaving = virtualShown[monitor.uuid]
        if let cur = leaving, cur != ws { previousWorkspace[monitor.uuid] = cur }
        monitorOf[ws] = monitor.uuid
        virtualShown[monitor.uuid] = ws
        autoSwitchAfter = Date().addingTimeInterval(0.6)
        // Away from the home Space, a workspace can't be shown without going there; a quiet show just records it.
        if !takesFocus, !isOnHomeSpace(monitor) { return }
        // On another macOS Space? Go to the home Space first, then show the workspace there.
        if !isOnHomeSpace(monitor), let home = homeSpace[monitor.uuid], let info = Spaces.list(display: monitor.uuid),
           let index = info.ids.firstIndex(of: home), let desktop = info.desktops.firstIndex(of: index) {
            guard attempts > 0 else { Log.info("workspaces: couldn't reach the home Space for \(ws)"); return }
            stageHomeSpace(ws, replacing: leaving, on: monitor, home: home)
            CGWarpMouseCursorPosition(monitor.center) // space switching acts on the display under the pointer
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
        // Quiet shows (a sort, restoring a layout) snap; a switch the user asked for slides.
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

    /// Before going back to the home Space from another macOS Space, sets the home Space up to show `ws`
    /// while it is still out of sight: the workspace that was showing there parks, and `ws` takes its tiles.
    /// Otherwise the Space slide shows the old workspace first, and only then swaps to `ws`.
    private func stageHomeSpace(_ ws: String, replacing old: String?, on s: Screen, home: UInt64) {
        guard config.virtualWorkspaces, isVirtual(ws) else { return }
        let screens = Screen.all()
        func onHome(_ id: CGWindowID) -> Bool { Spaces.of(window: id).contains(home) }
        if let old, old != ws, isVirtual(old) {
            for id in order where workspaceOf[id] == old && onHome(id) { park(id, screens: screens) }
        }
        // The windows a refresh would find there: not minimized, and their app not hidden.
        let arriving = order.filter { id in
            guard workspaceOf[id] == ws, let w = windows[id], !w.isNativeFullscreen, onHome(id),
                  w.element.bool(kAXMinimizedAttribute) != true,
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
            if !w.frame.approxEqual(target) { moves.append(.init(window: w, to: target, bounds: s.visible)) }
        }
        animator.animate(moves, duration: 0)
        Log.debug("workspaces: staged \(ws) on the home Space (\(arriving.count) windows, parked \(old ?? "none"))")
    }

    // MARK: - Moving windows between workspaces

    /// Hyprland's `movetoworkspace` (follow) and `movetoworkspacesilent`.
    func moveFocusedWindow(to ws: String, follow: Bool) {
        guard let w = focusedWindow(), workspaceOf[w.id] != ws else { return }
        moveWindow(w, toWorkspace: ws, follow: follow)
    }

    /// Move the real window first; only commit Ouch's assignment after WindowServer confirms it.
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
        // Put the window in its tile while it is still on its old Desktop, out of sight. It then
        // arrives in its tile, instead of at its old frame on top of the other tiles. The other
        // tiles keep their frames for now, and make room with the usual animation once it is here.
        if !known { windows[w.id] = w; order.append(w.id) }
        model.assign(w.id, to: ws)
        monitorOf[ws] = monitor.uuid
        snapNextPlacement.insert(w.id)
        refresh(instant: true, placing: [w.id])
        animator.afterPendingWrites { [weak self] in
            // Hold the display through the Space move only, so the animation after it is not frozen.
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
                    if known { model.assign(w.id, to: from) } else { forget(w.id) }
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
        model.assign(w.id, to: ws)
        lastFocused[ws] = w.id
        if let from, lastFocused[from] == w.id { lastFocused[from] = nil }
        corrections[w.id] = nil
        if follow {
            showWorkspace(ws, focusing: w)
        } else {
            autoSwitchAfter = Date().addingTimeInterval(0.6)
            refresh()
            guard isShown(from) else { return } // importing a background window keeps the current focus
            if let next = order.first(where: { workspaceOf[$0] == from && visible.contains($0) }).flatMap({ windows[$0] }) {
                focus(next)
            } else {
                parkFocus()
            }
        }
    }

    // MARK: - Windows on other desktops and Dock pulls

    /// Menu candidates from every Desktop. Discovery never activates the app or raises its windows.
    /// The window server names the candidate windows first, so only their apps get AX queries.
    /// An overall deadline keeps one slow app from stalling the menu.
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
        // Windows on another Desktop are off screen; the window list still has them with their pid.
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
            // Some apps omit inactive-Desktop windows from AXWindows. Keep using the AX
            // handles Ouch discovered earlier while those Desktops were visible.
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

    /// Pull an inactive Desktop's window into the workspace showing here, keeping this Desktop active.
    func bringWindowHere(_ w: Window) {
        guard let s = currentScreen(), isOnHomeSpace(s), let ws = virtualShown[s.uuid] else { return }
        moveWindow(w, toWorkspace: ws, follow: false)
    }

    /// Capture the destination before the Dock gets a chance to activate another Desktop.
    /// Only intercept an app's ordinary click when its preferred window is on a native Desktop.
    func prepareDockPull(at point: CGPoint) -> (() -> Void)? {
        let deadline = Date().addingTimeInterval(0.15)
        // Most clicks are nowhere near the Dock: let them through before any screen, Space or AX query.
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
        // The focused/main window wins over other windows of the same app, just like the Dock.
        let candidates = [appElement.element(kAXFocusedWindowAttribute), appElement.element(kAXMainWindowAttribute)].compactMap { $0 }
            + focusOrder.compactMap { windows[$0] }.filter { $0.pid == app.processIdentifier }.map(\.element)
            + appElement.elements(kAXWindowsAttribute)
        let desktops = Set(Screen.all().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        var seen: Set<CGWindowID> = []
        for el in candidates {
            guard Date() < deadline else { return nil } // never stall the mouse tap on an unresponsive app
            AXUIElementSetMessagingTimeout(el, 0.03)
            guard let id = el.windowID, seen.insert(id).inserted else { continue }
            guard el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
            // If the window the Dock would select is already on an Ouch home Desktop,
            // minimized, sticky, or fullscreen, let the Dock handle it normally.
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

    // MARK: - Following focus

    /// If the focused window lives on a hidden workspace (⌘-Tab, Dock, a link opening a window),
    /// switch to it. Also remembers each workspace's last focused window.
    func followFocus() {
        guard isStarted, let w = reportedFocusedWindow() else { return }
        if let p = pendingFocus {
            // Until macOS catches up with a focus we asked for, its reports are stale.
            guard p.id == w.id else { return }
            pendingFocus = nil
        }
        noteFocus(w.id)
        guard !sortSession else { return }
        guard config.virtualWorkspaces, let ws = workspaceOf[w.id], isVirtual(ws) else { return }
        if isShown(ws) { lastFocused[ws] = w.id; return }
        guard Date() > autoSwitchAfter else { return }
        // Only a window we actually parked means "go to its workspace". One you can already see
        // (e.g. on another macOS Desktop, not yet re-filed) just needs a refresh.
        guard isParked(w.frame, Screen.all()) else { scheduleRefresh(); return }
        if config.stayOnWorkspaceAfterClose, Date().timeIntervalSince(lastClose) < 1.0 {
            // A window just closed and macOS handed focus to one on another workspace: stay put.
            Log.debug("workspaces: ignoring focus on \(ws) right after a close")
            refocusCurrentWorkspace()
            return
        }
        Log.info("workspaces: \(w.bundleID ?? "a window") on workspace \(ws) was focused; switching")
        showWorkspace(ws, focusing: w)
    }

    /// Focuses the last-used window on the workspace showing on the current display, or parks focus.
    private func refocusCurrentWorkspace() {
        guard let s = currentScreen(), let cur = virtualShown[s.uuid] else { return parkFocus() }
        let candidates = [lastFocused[cur]].compactMap { $0 } + order
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == cur }), let w = windows[id] {
            focus(w)
        } else {
            parkFocus()
        }
    }

    /// With nothing to focus, take keyboard focus ourselves so typing doesn't land in a window
    /// that's parked off-screen.
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
