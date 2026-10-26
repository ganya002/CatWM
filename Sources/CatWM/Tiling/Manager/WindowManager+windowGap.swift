import AppKit

extension WindowManager {
    func windowGap(count: Int) -> CGFloat {
        config.windowMargins && !(config.smartWindowMargins && count == 1) ? config.windowMarginSize : 0
    }

    func tiled(on screen: Screen) -> [CGWindowID] {
        let shares = sharesSpaces
        return order.filter {
            visible.contains($0) && windows[$0]?.isFloating == false && workspaceOf[$0] == shown[screen.uuid]
                && !model.tabs.isBehind($0)
                && (!shares || (displayOf[$0] ?? workspaceOf[$0].flatMap { monitorOf[$0] }) == screen.uuid)
        }
    }

    func usableRect(_ screen: Screen) -> CGRect {
        var rect = screen.visible
        if config.ignoreMenuBar {
            rect = CGRect(x: rect.minX, y: screen.frame.minY, width: rect.width, height: rect.maxY - screen.frame.minY)
        }
        if let height = menuBarHeights[screen.uuid]?.height(on: screen.visible),
           screen.frame.minY + height > rect.minY {
            let top = screen.frame.minY + height
            rect = CGRect(x: rect.minX, y: top, width: rect.width, height: rect.maxY - top)
        }
        if config.disablePaddingOnBuiltinDisplay && screen.isBuiltin { return rect }
        return Self.padded(rect, left: config.paddingLeft, right: config.paddingRight,
                           top: config.paddingTop, bottom: config.paddingBottom)
    }

    static func padded(_ rect: CGRect, left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> CGRect {
        func fit(_ start: CGFloat, _ end: CGFloat, in length: CGFloat) -> (CGFloat, CGFloat) {
            let start = max(0, start), end = max(0, end), total = start + end, room = length / 2
            guard total > room, total > 0 else { return (start, end) }
            return (start * room / total, end * room / total)
        }
        let (left, right) = fit(left, right, in: rect.width), (top, bottom) = fit(top, bottom, in: rect.height)
        return CGRect(x: rect.minX + left, y: rect.minY + top,
                      width: rect.width - left - right, height: rect.height - top - bottom)
    }

    func state(for screen: Screen) -> ScreenState {
        state(workspace: workspaceKey(for: screen))
    }

    func workspaceKey(for screen: Screen) -> String {
        shown[screen.uuid]
            ?? Self.spaceWorkspace(display: screen.uuid, space: backend.currentSpace(display: screen.uuid))
    }

    func state(workspace key: String) -> ScreenState {
        if let existing = states[key] { return existing }
        let created = ScreenState()
        states[key] = created
        return created
    }

    func screen(containing rect: CGRect) -> Screen? { screen(containing: rect, in: backend.screens()) }

    func screen(containing rect: CGRect, in screens: [Screen]) -> Screen? {
        guard !rect.isNull else { return screens.first }
        return screens.max { first, second in
            let firstOverlap = first.frame.intersection(rect), secondOverlap = second.frame.intersection(rect)
            return (firstOverlap.isNull ? 0 : firstOverlap.width * firstOverlap.height)
                < (secondOverlap.isNull ? 0 : secondOverlap.width * secondOverlap.height)
        }
    }

    func screen(of window: Window) -> Screen? { screen(of: window, in: backend.screens()) }

    func screen(of window: Window, in screens: [Screen]) -> Screen? {
        if sharesSpaces {
            if !window.isFloating, let uuid = displayOf[window.id],
               let match = screens.first(where: { $0.uuid == uuid }) { return match }
        } else if config.virtualWorkspaces || !window.isFloating,
           let uuid = workspaceOf[window.id].flatMap({ monitorOf[$0] }),
           let match = screens.first(where: { $0.uuid == uuid }) { return match }
        return screen(containing: animator.destination(window.id) ?? window.cachedFrame, in: screens)
    }

    func currentScreen() -> Screen? {
        let screens = backend.screens()
        if let window = focusedWindow(), let match = screen(of: window, in: screens) { return match }
        let point = mouseLocation()
        return screens.first { $0.frame.contains(point) } ?? screens.first
    }

    func focusedWindowState() -> (floating: Bool, fullscreen: Bool)? {
        guard let window = focusedWindow() else { return nil }
        if floatsFreely(window.id) { return (window.isFloating, floats.floatZoom[window.id] != nil) }
        let zoomed = screen(of: window).map { state(for: $0).zoomed == window.id } ?? false
        return (window.isFloating, zoomed)
    }

    func focusedWindow() -> Window? {
        if let pending = focusRequests.pendingFocus {
            let pid = frontmostPID()
            if pid == pending.pid || pid == pending.origin, let window = windows[pending.id],
               visible.contains(pending.id) { return window }
            cancelFocusRequest()
        }
        return reportedFocusedWindow()
    }

    func reportedFocusedWindow() -> Window? {
        guard let pid = frontmostPID(),
              let report = focusRequests.reportedFocus, report.pid == pid,
              let id = report.id else { return nil }
        return windows[id]
    }

    func navFrame(_ window: Window) -> CGRect {
        (!window.isFloating && tilingEnabled ? targets[window.id] : nil)
            ?? animator.destination(window.id) ?? window.cachedFrame
    }
}
