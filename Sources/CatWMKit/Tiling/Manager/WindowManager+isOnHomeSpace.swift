import AppKit

package struct FloatState {
    package var floatFrames: [CGWindowID: CGRect] = [:]
    package var floatZoom: [CGWindowID: CGRect] = [:]
    package var savedOwnerOf: [CGWindowID: String] = [:]
    package var savedFloating: [CGWindowID: Bool] = [:]
}

extension WindowManager {
    package func isOnHomeSpace(_ screen: Screen) -> Bool {
        if config.virtualWorkspaces { return !Spaces.isFullscreen(display: screen.uuid) }
        guard let home = desktops.homeSpace[screen.uuid] else { return true }
        return backend.currentSpace(display: screen.uuid) == home
    }

    package func isParked(_ frame: CGRect, _ screens: [Screen]) -> Bool {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return false }
        let onScreen = screens.reduce(CGFloat(0)) { sum, screen in
            let overlap = screen.frame.intersection(frame)
            return sum + (overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        return onScreen < 400
    }

    private func parkingSpot(size: CGSize, on screen: Screen, _ screens: [Screen]) -> CGPoint {
        let right = CGPoint(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1)
        let left = CGPoint(x: screen.frame.minX - size.width + 1, y: screen.frame.maxY - 1)
        for origin in [right, left] {
            let rect = CGRect(origin: origin, size: size)
            if !screens.contains(where: { $0.uuid != screen.uuid && $0.frame.intersects(rect) }) { return origin }
        }
        return right
    }

    private func monitorScreen(of id: CGWindowID, in screens: [Screen]) -> Screen? {
        workspaceOf[id].flatMap { monitorOf[$0] }.flatMap { uuid in screens.first { $0.uuid == uuid } }
            ?? screens.first
    }

    package func park(_ id: CGWindowID, screens: [Screen]) {
        guard let window = windows[id], isVirtual(workspaceOf[id]) else { return }
        let frame = animator.destination(id) ?? window.cachedFrame
        guard !frame.isNull, !isParked(frame, screens) else { return }
        if let slide, slide.outgoing.contains(id) {
            guard let screen = monitorScreen(of: id, in: screens) else { return }
            let x = slide.forward ? screen.frame.minX - frame.width + 1 : screen.frame.maxX - 1
            let edge = CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
            guard !frame.approxEqual(edge, tolerance: 2), !animator.isMoving(id, to: edge) else { return }
            floats.floatFrames[id] = floatsFreely(id) ? frame : nil
            animator.animate([.init(window: window, to: edge, bounds: screen.visible)],
                             duration: config.animationDuration, curve: config.animationCurve,
                             bounce: config.animationBounce)
            return
        }
        floats.floatFrames[id] = floatsFreely(id) ? frame : nil
        cornerPark(id, screens: screens)
    }

    package func cornerPark(_ id: CGWindowID, screens: [Screen]) {
        guard let window = windows[id], let screen = monitorScreen(of: id, in: screens) else { return }
        let size = (animator.destination(id) ?? window.cachedFrame).size
        let frame = CGRect(origin: parkingSpot(size: size, on: screen, screens), size: size)
        guard !animator.isMoving(id, to: frame) else { return }
        animator.position(window, at: frame)
    }

    package func floatsFreely(_ id: CGWindowID) -> Bool {
        guard let window = windows[id] else { return false }
        if window.isFloating || !tilingEnabled { return true }
        guard let workspace = workspaceOf[id] else { return false }
        return (states[workspace]?.layout ?? config.layouts.first) == .floating
    }

    package func unpark(floating id: CGWindowID, screens: [Screen]) {
        guard let window = windows[id] else { return }
        let frame = animator.destination(id) ?? window.cachedFrame
        guard isParked(frame, screens) else {
            floats.floatFrames[id] = nil
            return
        }
        guard let screen = screen(of: window, in: screens) ?? screens.first else { return }
        var rect = floats.floatFrames.removeValue(forKey: id) ?? targets[id]
            ?? CGRect(x: screen.visible.midX - frame.width / 2, y: screen.visible.midY - frame.height / 2,
                      width: frame.width, height: frame.height)
        rect.origin.x = max(screen.visible.minX, min(rect.origin.x, screen.visible.maxX - rect.width))
        rect.origin.y = max(screen.visible.minY, min(rect.origin.y, screen.visible.maxY - rect.height))
        animator.quiet(id)
        if let from = slideStart(id, to: rect, on: screen) {
            animator.animate([.init(window: window, to: rect, bounds: screen.visible, from: from)],
                             duration: config.animationDuration, curve: config.animationCurve,
                             bounce: config.animationBounce)
            return
        }
        animator.animate([.init(window: window, to: rect, bounds: screen.visible)], duration: 0)
    }

    package func beginSlide(from previous: String, to workspace: String, on screen: Screen) {
        if let old = slide {
            for id in old.outgoing where !visible.contains(id) { cornerPark(id, screens: backend.screens()) }
        }
        slide = nil
        guard config.animate, config.animationDuration >= 0.01 else { return }
        let outgoing = visible.filter { workspaceOf[$0] == previous }
        let arriving = present.filter { workspaceOf[$0] == workspace }
        guard outgoing.count + arriving.count <= Self.maxAnimatedMoves else { return }
        let until = CACurrentMediaTime() + config.animationDuration
        slide = Slide(monitor: screen.uuid, workspace: workspace, outgoing: outgoing,
                      forward: workspaceSort(previous, workspace), until: until)
        DispatchQueue.main.asyncAfter( // style-ok: the slide is a time window for late windows
            deadline: .now() + config.animationDuration + 0.2
        ) { [weak self] in
            guard let self, self.slide?.until == until else { return }
            let screens = backend.screens()
            for id in outgoing where !self.visible.contains(id) { self.cornerPark(id, screens: screens) }
            self.slide = nil
        }
    }

    package func slideStart(_ id: CGWindowID, to target: CGRect, on screen: Screen) -> CGRect? {
        guard let slide, slide.monitor == screen.uuid, slide.workspace == workspaceOf[id],
              CACurrentMediaTime() < slide.until else { return nil }
        let x = slide.forward ? screen.frame.maxX - 1 : screen.frame.minX - target.width + 1
        return CGRect(x: x, y: target.minY, width: target.width, height: target.height)
    }

    package func restoreHiddenWindows(completion: (() -> Void)? = nil) {
        cancelFocusRequest()
        let deliver = {
            if let completion { RunLoop.main.perform(inModes: [.common, .modalPanel]) { completion() } }
        }
        guard config.virtualWorkspaces || !shown.isEmpty else { deliver(); return }
        let screens = backend.screens()
        guard !screens.isEmpty else { deliver(); return }
        saveWorkspaces()
        saveTilingRecovery()
        for (id, window) in windows {
            let frame = animator.destination(id) ?? window.cachedFrame
            animator.cancel(id)
            guard isParked(frame, screens) else { continue }
            guard let screen = screen(of: window, in: screens) ?? screens.first else { continue }
            var rect = floats.floatFrames[id] ?? targets[id]
                ?? CGRect(x: screen.visible.midX - frame.width / 2, y: screen.visible.midY - frame.height / 2,
                          width: frame.width, height: frame.height)
            rect.size.width = min(rect.width, screen.visible.width)
            rect.size.height = min(rect.height, screen.visible.height)
            rect.origin.x = max(screen.visible.minX, min(rect.origin.x, screen.visible.maxX - rect.width))
            rect.origin.y = max(screen.visible.minY, min(rect.origin.y, screen.visible.maxY - rect.height))
            animator.animate([.init(window: window, to: rect, bounds: screen.visible)], duration: 0)
        }
        Log.info("workspaces: queued parked windows for restoration")
        if completion != nil {
            let lock = NSLock()
            var finished = false
            let finish = {
                let first = lock.withLock {
                    guard !finished else { return false }
                    finished = true
                    return true
                }
                guard first else { return }
                deliver()
            }
            let queue = DispatchQueue.global(qos: .userInitiated)
            animator.afterPendingWrites(pids: nil, completionQueue: queue, finish)
            queue.asyncAfter(deadline: .now() + 2, execute: finish) // style-ok: limit for a hung app
        }
    }
}
