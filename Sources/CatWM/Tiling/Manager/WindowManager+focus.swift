import AppKit

extension WindowManager {
    func focus(_ window: Window, warp: Bool = true) {
        let request = UUID()
        focusRequests.pendingFocus = .init(id: window.id, pid: window.pid, origin: frontmostPID(), request: request)
        animator.focus(window) { [weak self] in
            guard let self, self.focusRequests.pendingFocus?.request == request else { return }
            self.focusRequests.pendingFocus?.executed = true
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

    func mouseMoved() {
        guard focusFollowsMouseNow else { return }
        focusUnderMouse()
    }

    private var focusFollowsMouseNow: Bool {
        config.focusFollowsMouse && (!config.focusFollowsMouseInModeOnly || surface.inMode)
    }

    func noteFocus(_ id: CGWindowID) {
        model.noteFocus(id)
        revealInStrip(id)
    }

    private func focusUnderMouse() {
        guard focusFollowsMouseNow, !closeAndSort.sortSession, Date() > ignoreMouseUntil,
              NSEvent.pressedMouseButtons == 0, !desktops.movingToSpace else { return }
        let point = mouseLocation()
        guard let hit = CGWindowInfo.normalWindow(at: point), let window = windows[hit.id], visible.contains(window.id),
              focusedWindow()?.id != window.id else { return }
        Log.debug("ffm: focusing \(window.id) \(window.bundleID ?? "")")
        focus(window, warp: false)
    }

    func mouseUp() {
        surface.hideTabDropHint()
        let point = mouseLocation()
        let joins = !tabUI.tabDropCancelled
        tabUI.tabDropCancelled = false
        let hovered = joins && drags.count == 1 ? drags.first.flatMap { settledTabHover(for: $0.key, at: point) } : nil
        let previewed = drags.first.flatMap { surface.endTabPreview(of: $0.key) }
        trackTabHover(nil)
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
                if config.mouseResizesWindows { resizeColumn(window, on: src) }
                continue
            }
            let dst = screens.first { $0.frame.contains(point) } ?? src
            if config.mouseSwapsWindows,
               let hit = tiled(on: dst).first(where: { $0 != id && targets[$0]?.contains(point) == true }) {
                if let frame = targets[hit], workspaceOf[hit] == workspaceOf[id],
                   point.y < frame.minY + frame.height / 4 || point.y > frame.maxY - frame.height / 4,
                   state(for: dst).strip.place(id, at: hit, below: point.y > frame.midY) {
                    continue
                }
                swapOrder(id, hit)
            } else if dst.uuid != src.uuid {
                assignTabs(of: id, to: shown[dst.uuid])
            }
        }
        corrections = [:]
        refresh()
    }
}
