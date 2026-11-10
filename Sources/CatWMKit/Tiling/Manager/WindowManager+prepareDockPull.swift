import AppKit

extension WindowManager {
    package func prepareDockPull(at point: CGPoint) -> (() -> Void)? {
        let deadline = Date().addingTimeInterval(0.15)
        guard isStarted, config.virtualWorkspaces, !closeAndSort.sortSession, dockArea.contains(point),
              Spaces.canMoveWindows,
              let display = backend.screens().first(where: { $0.frame.contains(point) }),
              isOnHomeSpace(display), let workspace = virtualShown[display.uuid],
              let app = dockApplication(at: point),
              !AXStalls.shared.isStalled(app.processIdentifier) else { return nil }
        let appElement = axApp(app.processIdentifier, timeout: 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
            != .cannotComplete else { return nil }
        let known = focusOrder.compactMap { windows[$0] }.filter { $0.pid == app.processIdentifier }.map(\.element)
        defer { known.forEach { AXUIElementSetMessagingTimeout($0, Window.messagingTimeout) } }
        let focusedWindow = focused.flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeDowncast($0, to: AXUIElement.self) : nil
        }
        let candidates = [focusedWindow, appElement.element(kAXMainWindowAttribute)]
            .compactMap(\.self) + known + appElement.elements(kAXWindowsAttribute)
        let desktops = Set(backend.screens().flatMap { screen -> [UInt64] in
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
                  desktops.contains(source), source != backend.currentSpace(display: display.uuid),
                  !nativeMoves.isMoving(id), !candidate.flag(kAXMinimizedAttribute),
                  !candidate.flag("AXFullScreen") else { return nil }
            let window = windows[id]
                ?? Window(id: id, element: candidate, pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                          backend: backend)
            return { [weak self] in
                guard let self, config.virtualWorkspaces, virtualShown[display.uuid] == workspace,
                      isOnHomeSpace(display), window.isValid else { return }
                if window.naturalFrame.isNull {
                    readDirectActionFacts(window)
                    window.autoFloating = shouldFloat(window)
                }
                cancelFocusRequest()
                surface.leaveMode()
                moveWindow(window, toWorkspace: workspace, follow: true)
            }
        }
        return nil
    }

    private func dockApplication(at point: CGPoint) -> NSRunningApplication? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let dockElement = axApp(dock.processIdentifier, timeout: 0.03)
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

    package func followFocus() {
        guard isStarted, !restoringTemplate, let window = reportedFocusedWindow() else { return }
        guard focusRequests.confirm(window.id) else { return }
        noteFocus(window.id)
        guard !closeAndSort.sortSession else { return }
        guard config.virtualWorkspaces, let workspace = workspaceOf[window.id], isVirtual(workspace) else { return }
        if isShown(workspace) { lastFocused[workspace] = window.id; return }
        guard Date() > autoSwitchAfter else { return }
        guard isParked(window.cachedFrame, backend.screens()) else { scheduleRefresh(); return }
        if config.stayOnWorkspaceAfterClose, Date().timeIntervalSince(closeAndSort.lastClose) < 1.0 {
            Log.debug("workspaces: ignoring focus on \(workspace) right after a close")
            refocusCurrentWorkspace()
            return
        }
        Log.info("workspaces: \(window.bundleID ?? "a window") on workspace \(workspace) was focused; switching")
        showWorkspace(workspace, focusing: window)
    }

    package func refocusCurrentWorkspace() {
        guard let screen = currentScreen(), let cur = virtualShown[screen.uuid] else { return parkFocus() }
        let candidates = [lastFocused[cur]].compactMap(\.self) + order
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == cur }),
           let window = windows[id] {
            focus(window)
        } else {
            parkFocus()
        }
    }

    package func prepareFocusSink() {
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

    package func parkFocus() {
        guard input.pointerAndFocus else { return }
        cancelFocusRequest()
        prepareFocusSink()
        guard let sink = focusSink else { return }
        if sink.isKeyWindow, frontmostPID() == getpid() {
            animator.focusSink(CGWindowID(sink.windowNumber))
            return
        }
        if let primary = NSScreen.screens.first { sink.setFrameOrigin(NSPoint(x: 0, y: primary.frame.maxY - 1)) }
        sink.orderFrontRegardless()
        sink.makeKey()
        animator.focusSink(CGWindowID(sink.windowNumber))
    }

    package func parkFocus(on screen: Screen) {
        parkFocus()
        guard !screen.frame.contains(mouseLocation()) else { return }
        warpPointer(to: screen.center)
    }
}
