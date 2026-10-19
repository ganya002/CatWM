import AppKit

extension WindowManager {
    func moveWindow(_ window: Window, toWorkspace workspace: String, follow: Bool) {
        let screens = Screen.all()
        guard config.virtualWorkspaces, isVirtual(workspace), !workspaceMoves.contains(window.id),
              let monitor = monitorOf[workspace].flatMap({ uuid in screens.first { $0.uuid == uuid } })
                ?? currentScreen() ?? screens.first,
              let home = homeSpace[monitor.uuid], let info = Spaces.list(display: monitor.uuid),
              info.desktops.contains(where: { info.ids[$0] == home }), !window.isNativeFullscreen else { return }
        if Spaces.of(window: window.id) == [home] {
            assignWindow(window, toWorkspace: workspace, from: workspaceOf[window.id], display: monitor.uuid,
                         follow: follow)
            return
        }
        let known = windows[window.id] != nil, from = workspaceOf[window.id], frame = window.frame
        workspaceMoves.insert(window.id)
        autoSwitchAfter = Date().addingTimeInterval(0.7)
        if !known { windows[window.id] = window; order.append(window.id) }
        model.assign(window.id, to: workspace)
        monitorOf[workspace] = monitor.uuid
        snapNextPlacement.insert(window.id)
        refresh(instant: true, placing: [window.id])
        animator.afterPendingWrites { [weak self] in
            let displayBatch = WindowServerUpdates.shared.begin()
            let moveStarted = Date()
            func release() {
                let held = Int(Date().timeIntervalSince(moveStarted) * 1000)
                let watchdog = Int(WindowServerUpdates.shared.maximumHold * 1000)
                let note = held > watchdog ? " (watchdog let go at \(watchdog) ms)" : ""
                Log.info("workspaces: import of \(window.id) held the display \(held) ms\(note)")
                displayBatch?.finish()
            }
            let waits = self?.isOnHomeSpace(monitor) ?? false
            Spaces.move(window: window.id, to: home, waitUntilOnScreen: waits) { [weak self] moved in
                guard let self else { release(); return }
                workspaceMoves.remove(window.id)
                guard moved, window.isValid, config.virtualWorkspaces, homeSpace[monitor.uuid] == home else {
                    Log.info("workspaces: direct move of \(window.id) to \(home) failed")
                    HUD.shared.show("macOS couldn't move this window", on: monitor.nsScreen)
                    if known { model.assign(window.id, to: from) } else { forget(window.id) }
                    if window.isValid, !frame.isNull { window.setFrame(frame) }
                    refresh()
                    release()
                    return
                }
                let elapsed = Int(Date().timeIntervalSince(moveStarted) * 1000)
                Log.info("workspaces: moved \(window.id) to home Desktop in \(elapsed) ms")
                if !known { watch(window) }
                release()
                assignWindow(window, toWorkspace: workspace, from: from, display: monitor.uuid, follow: follow)
            }
        }
    }

    func assignWindow(_ window: Window, toWorkspace workspace: String, from: String?, display: String, follow: Bool) {
        if windows[window.id] == nil {
            windows[window.id] = window
            order.append(window.id)
            watch(window)
        }
        monitorOf[workspace] = display
        model.assign(window.id, to: workspace)
        lastFocused[workspace] = window.id
        if let from, lastFocused[from] == window.id { lastFocused[from] = nil }
        corrections[window.id] = nil
        if follow {
            showWorkspace(workspace, focusing: window)
        } else {
            autoSwitchAfter = Date().addingTimeInterval(0.6)
            refresh()
            guard isShown(from) else { return }
            if let next = order.first(where: { workspaceOf[$0] == from && visible.contains($0) })
                .flatMap({ windows[$0] }) {
                focus(next)
            } else {
                parkFocus()
            }
        }
    }

    func windowsOnOtherDesktops() -> [Window] {
        guard config.virtualWorkspaces, isStarted, Spaces.canMoveWindows,
              let screen = currentScreen(), isOnHomeSpace(screen) else { return [] }
        let deadline = Date().addingTimeInterval(0.3)
        let offDesktop = windowsOffDesktop()
        var result: [Window] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            guard let ids = offDesktop[app.processIdentifier] else { continue }
            guard Date() < deadline else { break }
            result += offDesktopWindows(of: app, ids: ids, deadline: deadline)
        }
        return result.sorted { ($0.bundleID ?? "", $0.id) < ($1.bundleID ?? "", $1.id) }
    }

    private func windowsOffDesktop() -> [pid_t: Set<CGWindowID>] {
        let screens = Screen.all()
        let desktops = Set(screens.flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        let homes = Set(homeSpace.values)
        var offDesktop: [pid_t: Set<CGWindowID>] = [:]
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list
        where (info[kCGWindowLayer as String] as? Int) == 0 && (info[kCGWindowIsOnscreen as String] as? Bool) != true {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  !workspaceMoves.contains(CGWindowID(number)) else { continue }
            let membership = Spaces.of(window: CGWindowID(number))
            guard membership.count == 1, let space = membership.first, desktops.contains(space),
                  !homes.contains(space) else { continue }
            offDesktop[pid_t(pid), default: []].insert(CGWindowID(number))
        }
        return offDesktop
    }

    private func offDesktopWindows(of app: NSRunningApplication, ids: Set<CGWindowID>, deadline: Date) -> [Window] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        let known = windows.values.filter { $0.pid == app.processIdentifier && ids.contains($0.id) }.map(\.element)
        let candidates = (known.count < ids.count ? element.elements(kAXWindowsAttribute) : []) + known
        var seen: Set<CGWindowID> = []
        var result: [Window] = []
        for candidate in candidates {
            guard Date() < deadline else { break }
            AXUIElementSetMessagingTimeout(candidate, 0.1)
            guard let id = candidate.windowID, ids.contains(id), seen.insert(id).inserted,
                  candidate.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  !candidate.flag(kAXMinimizedAttribute),
                  !candidate.flag("AXFullScreen") else { continue }
            let window = windows[id]
                ?? Window(id: id, element: candidate, pid: app.processIdentifier, bundleID: app.bundleIdentifier)
            if window.naturalFrame.isNull {
                readDirectActionFacts(window)
                window.autoFloating = shouldFloat(window)
            }
            result.append(window)
        }
        return result
    }

    func readDirectActionFacts(_ window: Window) {
        window.naturalFrame = window.frame
        window.title = window.element.string(kAXTitleAttribute)
        window.resizable = window.element.isSettable(kAXSizeAttribute)
    }

    func bringWindowHere(_ window: Window) {
        guard let screen = currentScreen(), isOnHomeSpace(screen),
              let workspace = virtualShown[screen.uuid] else { return }
        moveWindow(window, toWorkspace: workspace, follow: false)
    }
}
