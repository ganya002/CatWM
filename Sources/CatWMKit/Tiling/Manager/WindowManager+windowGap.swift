import AppKit

extension WindowManager {
    package func windowGap(count: Int) -> CGFloat {
        config.windowMargins && !(config.smartWindowMargins && count == 1) ? config.windowMarginSize : 0
    }

    package func rawSlots(
        _ ids: [CGWindowID], on screen: Screen, _ screenState: ScreenState, ratio: CGFloat
    ) -> ([CGRect], CGFloat)? {
        let gap = windowGap(count: ids.count)
        guard let raw = screenState.layout.frames(count: ids.count,
                                                  in: usableRect(screen).insetBy(dx: -gap / 2, dy: -gap / 2),
                                                  ratio: ratio, mainCount: screenState.mainCount) else { return nil }
        let slots = raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).pixelAligned }
        guard slots.allSatisfy({ [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) }) else { return nil }
        return (slots, gap)
    }

    package func windowRefusingRatio(
        _ ratio: CGFloat, from old: CGFloat, ids: [CGWindowID], on screen: Screen, _ screenState: ScreenState
    ) -> CGWindowID? {
        guard ids.contains(where: { minSizes[$0] != nil }),
              let (before, _) = rawSlots(ids, on: screen, screenState, ratio: old),
              let (after, _) = rawSlots(ids, on: screen, screenState, ratio: ratio) else { return nil }
        return zip(ids, zip(before, after)).first { id, slots in
            guard let minimum = minSizes[id] else { return false }
            let (previous, next) = slots
            return (minimum.width > next.width + 1 && next.width < previous.width - 1)
                || (minimum.height > next.height + 1 && next.height < previous.height - 1)
        }?.0
    }

    package func warnTooSmall(_ id: CGWindowID, on screen: Screen?) {
        let name = windows[id].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName }
            ?? "This window"
        surface.warnHUD("\(name) can't get any smaller", on: screen?.nsScreen)
    }

    package func tiled(on screen: Screen) -> [CGWindowID] {
        let shares = sharesSpaces
        return order.filter {
            visible.contains($0) && windows[$0]?.isFloating == false && workspaceOf[$0] == shown[screen.uuid]
                && !model.tabs.isBehind($0)
                && (!shares || (displayOf[$0] ?? workspaceOf[$0].flatMap { monitorOf[$0] }) == screen.uuid)
        }
    }

    package func usableRect(_ screen: Screen) -> CGRect {
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

    package static func padded(_ rect: CGRect, left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> CGRect {
        func fit(_ start: CGFloat, _ end: CGFloat, in length: CGFloat) -> (CGFloat, CGFloat) {
            let start = max(0, start), end = max(0, end), total = start + end, room = length / 2
            guard total > room, total > 0 else { return (start, end) }
            return (start * room / total, end * room / total)
        }
        let (left, right) = fit(left, right, in: rect.width), (top, bottom) = fit(top, bottom, in: rect.height)
        return CGRect(x: rect.minX + left, y: rect.minY + top,
                      width: rect.width - left - right, height: rect.height - top - bottom)
    }

    package func state(for screen: Screen) -> ScreenState {
        state(workspace: workspaceKey(for: screen))
    }

    package func workspaceKey(for screen: Screen) -> String {
        shown[screen.uuid]
            ?? Self.spaceWorkspace(display: screen.uuid, space: backend.currentSpace(display: screen.uuid))
    }

    package func state(workspace key: String) -> ScreenState {
        if let existing = states[key] { return existing }
        let created = ScreenState(layout: config.layouts.first ?? .tall)
        states[key] = created
        return created
    }

    package func screen(containing rect: CGRect) -> Screen? { screen(containing: rect, in: backend.screens()) }

    package func screen(containing rect: CGRect, in screens: [Screen]) -> Screen? {
        guard !rect.isNull else { return screens.first }
        return screens.max { first, second in
            let firstOverlap = first.frame.intersection(rect), secondOverlap = second.frame.intersection(rect)
            return (firstOverlap.isNull ? 0 : firstOverlap.width * firstOverlap.height)
                < (secondOverlap.isNull ? 0 : secondOverlap.width * secondOverlap.height)
        }
    }

    package func screen(of window: Window) -> Screen? { screen(of: window, in: backend.screens()) }

    package func screen(of window: Window, in screens: [Screen]) -> Screen? {
        if sharesSpaces {
            if !window.isFloating, let uuid = displayOf[window.id],
               let match = screens.first(where: { $0.uuid == uuid }) { return match }
        } else if config.virtualWorkspaces || !window.isFloating,
           let uuid = workspaceOf[window.id].flatMap({ monitorOf[$0] }),
           let match = screens.first(where: { $0.uuid == uuid }) { return match }
        return screen(containing: animator.destination(window.id) ?? window.cachedFrame, in: screens)
    }

    package func currentScreen() -> Screen? {
        let screens = backend.screens()
        if let window = focusedWindow(), let match = screen(of: window, in: screens) { return match }
        let point = mouseLocation()
        return screens.first { $0.frame.contains(point) } ?? screens.first
    }

    package func focusedWindowState() -> (floating: Bool, fullscreen: Bool)? {
        guard let window = focusedWindow() else { return nil }
        if floatsFreely(window.id) { return (window.isFloating, floats.floatZoom[window.id] != nil) }
        let zoomed = screen(of: window).map { state(for: $0).zoomed == window.id } ?? false
        return (window.isFloating, zoomed)
    }

    package func focusedWindow() -> Window? {
        switch focusRequests.resolvePending(frontmost: frontmostPID(), available: { id in
            windows[id] != nil && visible.contains(id)
        }) {
        case .none: break
        case .window(let id): return windows[id]
        case .cancelled: animator.cancelFocus()
        }
        return reportedFocusedWindow()
    }

    package func reportedFocusedWindow() -> Window? {
        guard let pid = frontmostPID(),
              let report = focusRequests.reportedFocus, report.pid == pid,
              let id = report.id else { return nil }
        return windows[id]
    }

    package func navFrame(_ window: Window) -> CGRect {
        (!window.isFloating && tilingEnabled ? targets[window.id] : nil)
            ?? animator.destination(window.id) ?? window.cachedFrame
    }
}
