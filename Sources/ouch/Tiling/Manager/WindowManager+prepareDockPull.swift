import AppKit

extension WindowManager {
    func prepareDockPull(at point: CGPoint) -> (() -> Void)? {
        let deadline = Date().addingTimeInterval(0.15)
        guard isStarted, config.virtualWorkspaces, !sortSession, dockArea.contains(point), Spaces.canMoveWindows,
              let display = Screen.all().first(where: { $0.frame.contains(point) }),
              isOnHomeSpace(display), let workspace = virtualShown[display.uuid],
              let app = dockApplication(at: point) else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.03)
        let candidates = [appElement.element(kAXFocusedWindowAttribute), appElement.element(kAXMainWindowAttribute)]
            .compactMap(\.self)
            + focusOrder.compactMap { windows[$0] }.filter { $0.pid == app.processIdentifier }.map(\.element)
            + appElement.elements(kAXWindowsAttribute)
        let desktops = Set(Screen.all().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        var seen: Set<CGWindowID> = []
        for candidate in candidates {
            guard Date() < deadline else { return nil }
            AXUIElementSetMessagingTimeout(candidate, 0.03)
            guard let id = candidate.windowID, seen.insert(id).inserted else { continue }
            guard candidate.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
            let membership = Spaces.of(window: id)
            guard membership.count == 1, let source = membership.first,
                  desktops.contains(source), source != Spaces.current(display: display.uuid),
                  !workspaceMoves.contains(id), !candidate.flag(kAXMinimizedAttribute),
                  !candidate.flag("AXFullScreen") else { return nil }
            let window = windows[id]
                ?? Window(id: id, element: candidate, pid: app.processIdentifier, bundleID: app.bundleIdentifier)
            return { [weak self] in
                guard let self, config.virtualWorkspaces, virtualShown[display.uuid] == workspace,
                      isOnHomeSpace(display), window.isValid else { return }
                if window.naturalFrame.isNull {
                    readDirectActionFacts(window)
                    window.autoFloating = shouldFloat(window)
                }
                cancelFocusRequest()
                Hotkeys.shared.setSubmap("")
                moveWindow(window, toWorkspace: workspace, follow: true)
            }
        }
        return nil
    }

    private func dockApplication(at point: CGPoint) -> NSRunningApplication? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
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
        return app
    }

    func followFocus() {
        guard isStarted, !restoringTemplate, let window = reportedFocusedWindow() else { return }
        if let pending = pendingFocus {
            guard pending.id == window.id else { return }
            if pending.executed { pendingFocus = nil }
        }
        noteFocus(window.id)
        guard !sortSession else { return }
        guard config.virtualWorkspaces, let workspace = workspaceOf[window.id], isVirtual(workspace) else { return }
        if isShown(workspace) { lastFocused[workspace] = window.id; return }
        guard Date() > autoSwitchAfter else { return }
        guard isParked(window.cachedFrame, Screen.all()) else { scheduleRefresh(); return }
        if config.stayOnWorkspaceAfterClose, Date().timeIntervalSince(lastClose) < 1.0 {
            Log.debug("workspaces: ignoring focus on \(workspace) right after a close")
            refocusCurrentWorkspace()
            return
        }
        Log.info("workspaces: \(window.bundleID ?? "a window") on workspace \(workspace) was focused; switching")
        showWorkspace(workspace, focusing: window)
    }

    func refocusCurrentWorkspace() {
        guard let screen = currentScreen(), let cur = virtualShown[screen.uuid] else { return parkFocus() }
        let candidates = [lastFocused[cur]].compactMap(\.self) + order
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == cur }),
           let window = windows[id] {
            focus(window)
        } else {
            parkFocus()
        }
    }

    func prepareFocusSink() {
        guard focusSink == nil else { return }
        focusSink = {
            let sink = FocusSinkWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
            sink.isOpaque = false
            sink.backgroundColor = .clear
            sink.alphaValue = 0.01
            sink.ignoresMouseEvents = true
            sink.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
            return sink
        }()
    }

    func parkFocus() {
        cancelFocusRequest()
        prepareFocusSink()
        guard let sink = focusSink else { return }
        if sink.isKeyWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
            animator.focusSink(CGWindowID(sink.windowNumber))
            return
        }
        if let primary = NSScreen.screens.first { sink.setFrameOrigin(NSPoint(x: 0, y: primary.frame.maxY - 1)) }
        sink.orderFrontRegardless()
        sink.makeKey()
        animator.focusSink(CGWindowID(sink.windowNumber))
    }

    func parkFocus(on screen: Screen) {
        parkFocus()
        guard !screen.frame.contains(mouseLocation()) else { return }
        CGWarpMouseCursorPosition(screen.center)
        CursorRefresh.soon()
    }
}
