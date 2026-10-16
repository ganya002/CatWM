// Tiling: focus tracking, focus-follows-mouse and mouse drag/resize of tiled windows.
import AppKit

extension WindowManager {
    // MARK: - Focus & mouse

    /// Every focus change Ouch makes goes through here, so the focus history is always up to date.
    /// `warp: false` keeps the pointer where it is (focus follows mouse, a grab in progress).
    func focus(_ w: Window, warp: Bool = true) {
        w.focus()
        noteFocus(w.id) // now, not when macOS gets round to telling us: quick key presses read it next
        pendingFocus = (w.id, Date().addingTimeInterval(0.5))
        if warp, config.mouseFollowsFocus {
            ignoreMouseUntil = Date().addingTimeInterval(0.3)
            CGWarpMouseCursorPosition(navFrame(w).center)
        }
        CursorRefresh.soon() // the newly focused app sets its cursor only on a move
    }

    /// Focus follows mouse fires once the pointer rests for a moment, so sweeping across several
    /// windows doesn't raise each one, and the window under the final position always gets focus.
    func mouseMoved() {
        guard focusFollowsMouseNow else { return }
        ffmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.focusUnderMouse() }
        ffmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    /// Focus follows mouse is on, and, with the mode-only option, window mode is on too.
    private var focusFollowsMouseNow: Bool {
        config.focusFollowsMouse && (!config.focusFollowsMouseInModeOnly || !Hotkeys.shared.submap.isEmpty)
    }

    /// Records `id` as the most recently focused window.
    func noteFocus(_ id: CGWindowID) { model.noteFocus(id) }

    private func focusUnderMouse() {
        guard focusFollowsMouseNow, !sortSession, Date() > ignoreMouseUntil, NSEvent.pressedMouseButtons == 0, !movingToSpace else { return }
        let p = mouseLocation()
        guard let hit = CGWindowInfo.normalWindow(at: p), let w = windows[hit.id], visible.contains(w.id),
              focusedWindow()?.id != w.id else { return }
        Log.debug("ffm: focusing \(w.id) \(w.bundleID ?? "")")
        focus(w, warp: false)
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
                // Otherwise the next workspace switch parks it back on the display it came from.
                if let dst = screen(containing: w.frame, in: screens), dst.uuid != src.uuid, let ws = shown[dst.uuid] { model.assign(id, to: ws) }
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
                model.assign(id, to: shown[dst.uuid])
            }
        }
        corrections = [:]
        refresh()
    }

    /// Turn a mouse resize of a tiled window into a new main-pane ratio.
    private func applyMouseResize(_ w: Window, on s: Screen) {
        let st = state(for: s)
        let ids = tiled(on: s)
        let r = usableRect(s), f = w.frame
        guard !f.isNull else { return } // unknown geometry: a null rect's infinite origin would set the ratio to an extreme
        let mains = [.bsp, .twoPane, .twoPaneRight].contains(st.layout) ? 1 : st.mainCount
        guard let idx = ids.firstIndex(of: w.id), ids.count > mains, var axis = st.layout.ratioAxis else { return }
        if st.layout == .bsp { axis = (r.width >= r.height, true) }
        let isMain = idx < mains
        if st.layout == .widescreenTall, isMain, mains > 1, idx != mains - 1 { return }
        if st.layout == .widescreenTallRight, isMain, mains > 1, idx != 0 { return }
        if !isMain, [.threeColumnLeft, .threeColumnRight].contains(st.layout) { return }
        let gap = windowGap(count: ids.count)
        let total = axis.horizontal ? r.width : r.height
        // Distance of the main/secondary edge from the main pane's outer side, as `f` puts it.
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
        // Only a window whose slot sits on the split can move it (not e.g. a deeper BSP tile).
        if let slot = layoutTargets(ids, st, on: s)?[w.id], abs(boundary(slot) - st.ratio * (total + gap)) > 3 { return }
        st.ratio = min(0.9, max(0.1, boundary(f) / (total + gap)))
    }
}
