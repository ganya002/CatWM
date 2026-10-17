import AppKit

extension WindowManager {
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
        guard isStarted, !restoringTemplate, let w = reportedFocusedWindow() else { return }
        if let p = pendingFocus {
            guard p.id == w.id else { return }
            pendingFocus = nil
        }
        noteFocus(w.id)
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

    func refocusCurrentWorkspace() {
        guard let s = currentScreen(), let cur = virtualShown[s.uuid] else { return parkFocus() }
        let candidates = [lastFocused[cur]].compactMap { $0 } + order
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == cur }), let w = windows[id] {
            focus(w)
        } else {
            parkFocus()
        }
    }

    func parkFocus() {
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
