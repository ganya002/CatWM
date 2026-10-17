import AppKit

extension WindowManager {
    func windowGap(count: Int) -> CGFloat {
        config.windowMargins && !(config.smartWindowMargins && count == 1) ? config.windowMarginSize : 0
    }

    func rawSlots(_ ids: [CGWindowID], on s: Screen, _ st: ScreenState, ratio: CGFloat) -> ([CGRect], CGFloat)? {
        let gap = windowGap(count: ids.count)
        guard let raw = st.layout.frames(count: ids.count, in: usableRect(s).insetBy(dx: -gap / 2, dy: -gap / 2),
                                         ratio: ratio, mainCount: st.mainCount) else { return nil }
        let slots = raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).pixelAligned }
        guard slots.allSatisfy({ [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) }) else { return nil }
        return (slots, gap)
    }

    func windowRefusingRatio(_ ratio: CGFloat, from old: CGFloat, ids: [CGWindowID], on s: Screen, _ st: ScreenState) -> CGWindowID? {
        guard ids.contains(where: { minSizes[$0] != nil }),
              let (before, _) = rawSlots(ids, on: s, st, ratio: old),
              let (after, _) = rawSlots(ids, on: s, st, ratio: ratio) else { return nil }
        return zip(ids, zip(before, after)).first { id, slots in
            guard let m = minSizes[id] else { return false }
            let (b, a) = slots
            return (m.width > a.width + 1 && a.width < b.width - 1) || (m.height > a.height + 1 && a.height < b.height - 1)
        }?.0
    }

    func warnTooSmall(_ id: CGWindowID, on s: Screen?) {
        let name = windows[id].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? "This window"
        HUD.shared.warn("\(name) can't get any smaller", on: s?.ns)
    }

    func tiled(on s: Screen) -> [CGWindowID] {
        order.filter { visible.contains($0) && windows[$0]?.isFloating == false && workspaceOf[$0] == shown[s.uuid] }
    }

    func usableRect(_ s: Screen) -> CGRect {
        var r = s.visible
        if config.ignoreMenuBar { r = CGRect(x: r.minX, y: s.frame.minY, width: r.width, height: r.maxY - s.frame.minY) }
        if config.disablePaddingOnBuiltinDisplay && s.isBuiltin { return r }
        return CGRect(x: r.minX + config.paddingLeft, y: r.minY + config.paddingTop,
                      width: r.width - config.paddingLeft - config.paddingRight,
                      height: r.height - config.paddingTop - config.paddingBottom)
    }

    func state(for s: Screen) -> ScreenState {
        state(workspace: workspaceKey(for: s))
    }

    func workspaceKey(for s: Screen) -> String {
        shown[s.uuid] ?? Self.spaceWorkspace(display: s.uuid, space: Spaces.current(display: s.uuid))
    }

    func state(workspace key: String) -> ScreenState {
        if let st = states[key] { return st }
        let st = ScreenState(layout: config.layouts.first ?? .tall)
        states[key] = st
        return st
    }

    func screen(containing r: CGRect, in screens: [Screen] = Screen.all()) -> Screen? {
        guard !r.isNull else { return screens.first }
        return screens.max { a, b in
            let ia = a.frame.intersection(r), ib = b.frame.intersection(r)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }
    }

    func screen(of w: Window, in screens: [Screen] = Screen.all()) -> Screen? {
        if config.virtualWorkspaces || !w.isFloating, let u = workspaceOf[w.id].flatMap({ monitorOf[$0] }),
           let s = screens.first(where: { $0.uuid == u }) { return s }
        return screen(containing: animator.destination(w.id) ?? w.cachedFrame, in: screens)
    }

    func currentScreen() -> Screen? {
        let screens = Screen.all()
        if let w = focusedWindow(), let s = screen(of: w, in: screens) { return s }
        let p = mouseLocation()
        return screens.first { $0.frame.contains(p) } ?? screens.first
    }

    func focusedWindowState() -> (floating: Bool, fullscreen: Bool)? {
        guard let w = focusedWindow() else { return nil }
        let zoomed = screen(of: w).map { state(for: $0).zoomed == w.id } ?? false
        return (w.isFloating, zoomed)
    }

    func focusedWindow() -> Window? {
        if let p = pendingFocus {
            let pid = frontmostPID()
            if pid == p.pid || pid == p.origin, let w = windows[p.id], visible.contains(p.id) { return w }
            cancelFocusRequest()
        }
        return reportedFocusedWindow()
    }

    func reportedFocusedWindow() -> Window? {
        guard let pid = frontmostPID(),
              let report = reportedFocus, report.pid == pid,
              let id = report.id else { return nil }
        return windows[id]
    }

    func navFrame(_ w: Window) -> CGRect {
        (!w.isFloating && tilingEnabled ? targets[w.id] : nil) ?? animator.destination(w.id) ?? w.cachedFrame
    }

    func navItem(_ w: Window, in screens: [Screen]) -> FocusNavigation.Item {
        .init(id: w.id, frame: navFrame(w), screen: screen(of: w, in: screens)?.uuid)
    }

    func neighbor(of w: Window, _ dir: Direction, among candidates: [Window]) -> Window? {
        let screens = Screen.all()
        let id = FocusNavigation.neighbor(of: navItem(w, in: screens), dir,
                                          among: candidates.map { navItem($0, in: screens) }, stamps: focusStamps)
        return id.flatMap { windows[$0] }
    }

}
