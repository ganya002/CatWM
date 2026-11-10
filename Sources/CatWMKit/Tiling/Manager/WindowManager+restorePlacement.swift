import AppKit

package struct WindowPlacement {
    package let window: Window
    package let screen: Screen
    package let frame: CGRect
    package let floating: Bool
    package let hidden: Bool
    package let zoomed: Bool
}

package struct DisplayPlacement {
    package let screen: Screen
    package let layout: Layout
    package let ratio: CGFloat
    package let mainCount: Int
}

package struct PlacementHolds {
    private var held: [CGWindowID: Date] = [:]

    package mutating func hold(_ window: Window, since: Date = Date()) {
        window.placementSuspended = true
        held[window.id] = since
    }

    package mutating func resume(_ window: Window) {
        held[window.id] = nil
        window.placementSuspended = false
    }

    package mutating func forget(_ id: CGWindowID) { held[id] = nil }

    package mutating func observe(_ window: Window, scanStarted: Date, minimized: Bool, fullscreen: Bool,
                                  restoring: Bool) -> Bool {
        guard let since = held[window.id] else { return true }
        guard !restoring, scanStarted > since, !minimized, !fullscreen else { return false }
        resume(window)
        return true
    }
}

extension WindowManager {
    @MainActor package func preparePlacement(_ windows: [Window]) async throws {
        for window in windows { animator.cancel(window.id) }
        let finished = await animator.waitForPendingWrites(
            pids: Set(windows.map(\.pid)).intersection(animator.activeWriterPids), timeout: 2)
        try Task.checkCancellation()
        guard finished else { throw WindowPlacementError.busy }
    }

    package func holdPlacement(_ window: Window) {
        animator.cancel(window.id)
        placementHolds.hold(window)
    }

    @discardableResult
    package func hideForPlacement(_ window: Window, minimized: Bool) -> Bool {
        holdPlacement(window)
        let changed = minimized ? window.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
            : window.element.set("AXFullScreen", kCFBooleanTrue)
        placementHolds.hold(window)
        return changed
    }

    package func registerPlacements(_ placements: [WindowPlacement], displays: [DisplayPlacement],
                                    tiling: Bool, screens: [Screen]) -> [CGWindowID: CGRect] {
        for display in displays {
            let state = state(for: display.screen)
            state.layout = display.layout
            state.ratio = min(0.9, max(0.1, display.ratio))
            state.mainCount = max(1, display.mainCount)
            state.zoomed = nil
        }
        var frames: [CGWindowID: CGRect] = [:]
        var restored: [CGWindowID] = []
        for placement in placements {
            let window = placement.window
            let id = window.id
            if windows[id] == nil {
                windows[id] = window
                watch(window)
            }
            window.userFloating = .chosen(placement.floating)
            window.naturalFrame = placement.frame
            model.assign(id, to: workspaceKey(for: placement.screen))
            displayOf[id] = placement.screen.uuid
            floats.floatFrames[id] = nil
            targets[id] = nil
            corrections[id] = nil
            if placement.hidden { present.remove(id) } else { present.insert(id) }
            if placement.zoomed { state(for: placement.screen).zoomed = id }
            frames[id] = placement.frame
            restored.append(id)
        }
        let restoredIDs = Set(restored)
        order = restored + order.filter { !restoredIDs.contains($0) }
        visible = present.filter { isShown(workspaceOf[$0]) }
        tilingEnabled = tiling
        if tiling {
            for screen in screens {
                let ids = tiled(on: screen)
                guard let slots = layoutTargets(ids, state(for: screen), on: screen) else { continue }
                for (id, frame) in slots {
                    frames[id] = frame
                    targets[id] = frame
                }
            }
        }
        return frames
    }

    @MainActor package func placeWindows(_ frames: [CGWindowID: CGRect], verifying: Set<CGWindowID>,
                                         screens: [Screen]) async throws -> Set<CGWindowID> {
        let moves = frames.compactMap { id, frame -> Animator.Move? in
            guard let window = windows[id], let screen = screen(of: window, in: screens) else { return nil }
            return .init(window: window, to: frame, bounds: screen.visible)
        }
        defer { for move in moves { animator.cancel(move.window.id) } }
        try Task.checkCancellation()
        let duration = config.animate && config.animationDuration >= 0.01 ? config.animationDuration : 0
        animator.animate(moves, duration: duration, curve: config.animationCurve, bounce: config.animationBounce)
        if duration > 0 {
            _ = await poll(duration + 0.6, every: 20_000_000) {
                moves.allSatisfy { !self.animator.isBusy($0.window.id) }
            }
            try Task.checkCancellation()
        }
        let placed = Set(moves.map(\.window.pid))
        let finished = await animator.waitForPendingWrites(
            pids: placed.intersection(animator.activeWriterPids), timeout: 2)
        try Task.checkCancellation()
        guard finished else {
            for move in moves { animator.cancel(move.window.id) }
            return Set(moves.map(\.window.id))
        }
        func isPlaced(_ id: CGWindowID) -> Bool {
            guard let window = windows[id], let target = frames[id] else { return true }
            return window.frameUnlessStalled.approxEqual(target, tolerance: 8)
        }
        _ = await poll(0.8, every: 20_000_000) { verifying.allSatisfy(isPlaced) }
        try Task.checkCancellation()
        let failures = Set(verifying.filter { !isPlaced($0) })
        for move in moves { animator.cancel(move.window.id) }
        _ = await animator.waitForPendingWrites(
            pids: placed.intersection(animator.activeWriterPids), timeout: 2)
        try Task.checkCancellation()
        return failures
    }
}

package enum WindowPlacementError: LocalizedError {
    case busy
    package var errorDescription: String? { "Windows are still moving. Try opening the template again." }
}
