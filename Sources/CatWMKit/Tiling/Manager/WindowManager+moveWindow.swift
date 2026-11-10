import AppKit

extension WindowManager {
    package func moveWindow(_ window: Window, toWorkspace workspace: String, follow: Bool) {
        guard config.virtualWorkspaces else { return }
        moveNativeWindow(window, to: workspace, follow: follow)
    }

    package func assignWindow(_ window: Window, toWorkspace workspace: String, from: String?, follow: Bool,
                              handOffFocus: Bool) {
        let from = from == workspace ? nil : from
        if windows[window.id] == nil {
            windows[window.id] = window
            order.append(window.id)
            watch(window)
        }
        model.assign(window.id, to: workspace)
        lastFocused[workspace] = window.id
        if let from, lastFocused[from] == window.id { lastFocused[from] = nil }
        corrections[window.id] = nil
        if follow, isShown(workspace) {
            refresh()
            focus(window, warp: false)
        } else if follow {
            showWorkspace(workspace, focusing: window)
        } else {
            autoSwitchAfter = Date().addingTimeInterval(0.6)
            refresh()
            guard handOffFocus, let from, isShown(from) else { return }
            let remaining = order.filter { workspaceOf[$0] == from && visible.contains($0) }
            if let next = (model.mostRecent(of: remaining) ?? remaining.first).flatMap({ windows[$0] }) {
                focus(next)
            } else if let screen = backend.screens().first(where: { $0.uuid == monitorOf[from] }) {
                parkFocus(on: screen)
            } else {
                parkFocus()
            }
        }
    }

    package func windowsOnOtherDesktops() -> [Window] {
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
        let screens = backend.screens()
        let desktops = Set(screens.flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        let homes = Set(backend.screens().map { backend.currentSpace(display: $0.uuid) })
        var offDesktop: [pid_t: Set<CGWindowID>] = [:]
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list
        where (info[kCGWindowLayer as String] as? Int) == 0 && (info[kCGWindowIsOnscreen as String] as? Bool) != true {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  !nativeMoves.isMoving(CGWindowID(number)) else { continue }
            let membership = Spaces.of(window: CGWindowID(number))
            guard membership.count == 1, let space = membership.first, desktops.contains(space),
                  !homes.contains(space) else { continue }
            offDesktop[pid_t(pid), default: []].insert(CGWindowID(number))
        }
        return offDesktop
    }

    private func offDesktopWindows(of app: NSRunningApplication, ids: Set<CGWindowID>, deadline: Date) -> [Window] {
        let element = axApp(app.processIdentifier, timeout: 0.1)
        let known = windows.values.filter { $0.pid == app.processIdentifier && ids.contains($0.id) }.map(\.element)
        let candidates = (known.count < ids.count ? element.elements(kAXWindowsAttribute) : []) + known
        defer { known.forEach { AXUIElementSetMessagingTimeout($0, Window.messagingTimeout) } }
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
                ?? Window(id: id, element: candidate, pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                          backend: backend)
            if window.naturalFrame.isNull {
                readDirectActionFacts(window)
                window.autoFloating = shouldFloat(window)
            }
            result.append(window)
        }
        return result
    }

    package func readDirectActionFacts(_ window: Window) {
        window.naturalFrame = window.frame
        window.title = window.element.string(kAXTitleAttribute)
        window.resizable = window.element.isSettable(kAXSizeAttribute)
    }

    package func bringWindowHere(_ window: Window) {
        guard let screen = currentScreen(), isOnHomeSpace(screen),
              let workspace = virtualShown[screen.uuid] else { return }
        moveWindow(window, toWorkspace: workspace, follow: false)
    }
}
