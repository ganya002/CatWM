import AppKit

extension WindowManager {
    package func focus(_ window: Window, warp: Bool = true) {
        let request = focusRequests.begin(id: window.id, pid: window.pid, origin: frontmostPID())
        animator.focus(window) { [weak self] in
            guard let self, self.focusRequests.executed(request) else { return }
            self.requestFocusObservation()
        }
        noteFocus(window.id)
        if warp, config.mouseFollowsFocus {
            ignoreMouseUntil = Date().addingTimeInterval(0.3)
            warpPointer(to: navFrame(window).center)
        } else {
            cursorRefresh.soon()
        }
    }

    package func mouseMoved() {
        guard focusFollowsMouseNow else { return }
        focusUnderMouse()
    }

    private var focusFollowsMouseNow: Bool {
        config.focusFollowsMouse && (!config.focusFollowsMouseInModeOnly || surface.inMode)
    }

    package func noteFocus(_ id: CGWindowID) { model.noteFocus(id) }

    private func focusUnderMouse() {
        guard focusFollowsMouseNow, !closeAndSort.sortSession, Date() > ignoreMouseUntil,
              NSEvent.pressedMouseButtons == 0, !desktops.movingToSpace else { return }
        let point = mouseLocation()
        guard let hit = CGWindowInfo.normalWindow(at: point), let window = windows[hit.id], visible.contains(window.id),
              focusedWindow()?.id != window.id else { return }
        Log.debug("ffm: focusing \(window.id) \(window.bundleID ?? "")")
        focus(window, warp: false)
    }

    package func mouseUp() {
        guard tabUI.drag.lifted == nil else { return }
        let point = mouseLocation()
        let joins = tabUI.drag.allowsJoin
        let hovered = joins && drags.count == 1 ? drags.first.flatMap { settledTabHover(for: $0.key, at: point) } : nil
        let previewed = tabUI.drag.finish(drags.first?.key, on: surface).preview
        if let previewed, let id = drags.first?.key, drags.count == 1, !desktops.movingToSpace {
            drags = [:]
            dropIntoStrip(id, group: previewed.group, at: previewed.index)
            return settleParkedTabs()
        }
        guard !drags.isEmpty, !desktops.movingToSpace else {
            drags = [:]
            return settleParkedTabs()
        }
        let finished = drags
        drags = [:]
        let dragged = finished.keys.compactMap { windows[$0] }
        readFrames(dragged) { [weak self] in
            guard let self else { return }
            defer { self.settleParkedTabs() }
            guard NSEvent.pressedMouseButtons & 1 == 0, !self.desktops.movingToSpace else { return }
            self.finishMouseDrag(finished, at: point, hovered: hovered, joins: joins)
        }
    }

    private func finishMouseDrag(_ finished: [CGWindowID: Bool], at point: CGPoint, hovered: CGWindowID?,
                                 joins: Bool) {
        let screens = backend.screens()
        for (id, resized) in finished {
            guard let window = windows[id], let src = screen(of: window, in: screens) else { continue }
            let band = joins && holds(window, at: point) ? tabDropTarget(for: id, at: point) : nil
            if !resized, finished.count == 1, let host = band ?? hovered {
                joinTabs(of: id, onto: host)
                return
            }
            if floatsFreely(id) {
                if let dst = screen(containing: window.cachedFrame, in: screens), dst.uuid != src.uuid,
                   let workspace = shown[dst.uuid] {
                    assignManagedWindow(id, to: workspace)
                }
                continue
            }
            if resized {
                if config.mouseResizesWindows { applyMouseResize(window, on: src) }
                continue
            }
            let dst = screens.first { $0.frame.contains(point) } ?? src
            if config.mouseSwapsWindows,
               let hit = tiled(on: dst).first(where: { $0 != id && targets[$0]?.contains(point) == true }) {
                swapOrder(id, hit)
            } else if dst.uuid != src.uuid {
                assignTabs(of: id, to: shown[dst.uuid])
            }
        }
        corrections = [:]
        refresh()
    }

    private func applyMouseResize(_ window: Window, on screen: Screen) {
        let screenState = state(for: screen)
        let ids = tiled(on: screen)
        let rect = usableRect(screen), frame = window.cachedFrame
        guard !frame.isNull else { return }
        let layout = screenState.layout
        let mains = [.bsp, .twoPane, .twoPaneRight].contains(layout) ? 1 : screenState.mainCount
        guard let idx = ids.firstIndex(of: window.id), ids.count > mains, var axis = layout.ratioAxis else { return }
        if layout == .bsp { axis = (rect.width >= rect.height, true) }
        let isMain = idx < mains
        if layout == .widescreenTall, isMain, mains > 1, idx != mains - 1 { return }
        if layout == .widescreenTallRight, isMain, mains > 1, idx != 0 { return }
        if !isMain, [.threeColumnLeft, .threeColumnRight].contains(layout) { return }
        let gap = windowGap(count: ids.count)
        let total = axis.horizontal ? rect.width : rect.height
        func boundary(_ slot: CGRect) -> CGFloat {
            switch (axis.horizontal, axis.fromStart, isMain) {
            case (true, true, true): slot.maxX - rect.minX + gap
            case (true, true, false): slot.minX - rect.minX
            case (true, false, true): rect.maxX - slot.minX + gap
            case (true, false, false): rect.maxX - slot.maxX
            case (false, _, true): slot.maxY - rect.minY + gap
            case (false, _, false): slot.minY - rect.minY
            }
        }
        if let slot = layoutTargets(ids, screenState, on: screen)?[window.id],
           abs(boundary(slot) - screenState.ratio * (total + gap)) > 3 { return }
        screenState.ratio = min(0.9, max(0.1, boundary(frame) / (total + gap)))
    }
}
