import AppKit

extension WindowManager {

    func focus(_ w: Window) {
        w.focus()
        noteFocus(w.id)
        pendingFocus = (w.id, Date().addingTimeInterval(0.5))
        if config.mouseFollowsFocus {
            ignoreMouseUntil = Date().addingTimeInterval(0.3)
            CGWarpMouseCursorPosition(navFrame(w).center)
        }
        CursorRefresh.soon()
    }

    func mouseMoved() {
        guard focusFollowsMouseNow else { return }
        ffmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.focusUnderMouse() }
        ffmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private var focusFollowsMouseNow: Bool {
        config.focusFollowsMouse && (!config.focusFollowsMouseInModeOnly || !Hotkeys.shared.submap.isEmpty)
    }

    func noteFocus(_ id: CGWindowID) {
        focusClock += 1
        focusStamps[id] = focusClock
    }

    private func focusUnderMouse() {
        guard focusFollowsMouseNow, !sortSession, Date() > ignoreMouseUntil, NSEvent.pressedMouseButtons == 0, !movingToSpace else { return }
        let p = mouseLocation()
        guard let hit = CGWindowInfo.normalWindow(at: p), let w = windows[hit.id], visible.contains(w.id),
              focusedWindow()?.id != w.id else { return }
        Log.debug("ffm: focusing \(w.id) \(w.bundleID ?? "")")
        w.focus()
    }

    func mouseUp() {
        guard !drags.isEmpty, !movingToSpace else { drags = [:]; return }
        let finished = drags
        drags = [:]
        let screens = Screen.all()
        let p = mouseLocation()
        for (id, resized) in finished {
            guard let w = windows[id], let src = screen(of: w, in: screens) else { continue }
            if floatsFreely(id) {
                if let dst = screen(containing: w.frame, in: screens), dst.uuid != src.uuid, let ws = shown[dst.uuid] { workspaceOf[id] = ws }
                continue
            }
            if resized {
                if config.mouseResizesWindows { applyMouseResize(w, on: src) }
                continue
            }
            let dst = screens.first { $0.frame.contains(p) } ?? src
            if config.mouseSwapsWindows,
               let hit = tiled(on: dst).first(where: { $0 != id && targets[$0]?.contains(p) == true }) {
                swapOrder(id, hit)
            } else if dst.uuid != src.uuid {
                workspaceOf[id] = shown[dst.uuid]
            }
        }
        corrections = [:]
        refresh()
    }

    private func applyMouseResize(_ w: Window, on s: Screen) {
        let st = state(for: s)
        let ids = tiled(on: s)
        let r = usableRect(s), f = w.frame
        guard !f.isNull else { return }
        let mains = [.bsp, .twoPane, .twoPaneRight].contains(st.layout) ? 1 : st.mainCount
        guard let idx = ids.firstIndex(of: w.id), ids.count > mains, var axis = st.layout.ratioAxis else { return }
        if st.layout == .bsp { axis = (r.width >= r.height, true) }
        let isMain = idx < mains
        if st.layout == .widescreenTall, isMain, mains > 1, idx != mains - 1 { return }
        if st.layout == .widescreenTallRight, isMain, mains > 1, idx != 0 { return }
        if !isMain, [.threeColumnLeft, .threeColumnRight].contains(st.layout) { return }
        let gap = config.windowMargins ? config.windowMarginSize : 0
        let total = axis.horizontal ? r.width : r.height
        func boundary(_ f: CGRect) -> CGFloat {
            switch (axis.horizontal, axis.fromStart, isMain) {
            case (true, true, true): f.maxX - r.minX + gap
            case (true, true, false): f.minX - r.minX
            case (true, false, true): r.maxX - f.minX + gap
            case (true, false, false): r.maxX - f.maxX
            case (false, _, true): f.maxY - r.minY + gap
            case (false, _, false): f.minY - r.minY
            }
        }
        if let (slots, _) = rawSlots(ids, on: s, st, ratio: st.ratio), slots.indices.contains(idx),
           abs(boundary(slots[idx]) - st.ratio * (total + gap)) > 3 { return }
        st.ratio = min(0.9, max(0.1, boundary(f) / (total + gap)))
    }
}
