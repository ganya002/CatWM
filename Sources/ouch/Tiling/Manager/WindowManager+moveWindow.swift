import AppKit

extension WindowManager {
    func moveWindow(_ w: Window, toWorkspace ws: String, follow: Bool) {
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
        model.assign(w.id, to: ws)
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

    func assignWindow(_ w: Window, toWorkspace ws: String, from: String?, display: String, follow: Bool) {
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

}
