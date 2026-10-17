import AppKit

extension TemplateRestorer {
    func apply() async throws {
        var screens = Screen.all()
        guard !screens.isEmpty else { throw WindowManager.TemplateError.notReady }
        let mainID = NSScreen.screens.first?.displayID
        let mapping = template.displayMap(available: screens.map { ($0.uuid, $0.id == mainID) })
        var pairs = template.windows.compactMap { saved -> (WorkspaceTemplate.SavedWindow, Window)? in
            matched[saved.id].map { (saved, $0) }
        }
        for (_, window) in pairs { manager.animator.cancel(window.id) }
        let opening = TemplatePlacementPlan.writerBarrier(placed: Set(pairs.map(\.1.pid)), busy: manager.animator.activeWriterPids)
        let openingFinished = await placementWritesFinished(pids: opening)
        try Task.checkCancellation()
        guard openingFinished else { throw TemplatePlacementError.busy }

        var restoreHidden: [(WorkspaceTemplate.SavedWindow, Window)] = []
        defer { putBackHidden(restoreHidden) }

        var exitingDisplays = Set<String>()
        for (saved, window) in pairs {
            AXUIElementSetMessagingTimeout(window.element, axTimeout)
            var clearedFullscreen = false
            var clearedMinimized = false
            if window.isNativeFullscreen {
                if let screen = manager.screen(containing: window.frame, in: screens),
                   Spaces.of(window: window.id).contains(Spaces.current(display: screen.uuid)) {
                    exitingDisplays.insert(screen.uuid)
                }
                clearedFullscreen = window.element.set("AXFullScreen", kCFBooleanFalse)
            }
            if window.element.bool(kAXMinimizedAttribute) == true {
                clearedMinimized = window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
            }
            if (saved.minimized || saved.fullscreen) && (clearedMinimized || clearedFullscreen) {
                restoreHidden.append((saved, window))
            }
        }
        _ = try await settlePlacement(timeout: 3) {
            pairs.allSatisfy { !$0.1.isNativeFullscreen && $0.1.element.bool(kAXMinimizedAttribute) != true } &&
                exitingDisplays.allSatisfy { !Spaces.isFullscreen(display: $0) }
        }
        pairs = pairs.filter { saved, window in
            guard !window.isNativeFullscreen, window.element.bool(kAXMinimizedAttribute) != true else {
                failures.insert(saved.appName)
                matched[saved.id] = nil
                restoreHidden.removeAll { $0.1.id == window.id }
                return false
            }
            return true
        }
        manager.syncWorkspaces(screens: screens, present: manager.present)
        var desktops: [String: UInt64] = [:]
        for screen in screens { desktops[screen.uuid] = Spaces.current(display: screen.uuid) }
        var ready: [(WorkspaceTemplate.SavedWindow, Window)] = []
        for (saved, window) in pairs {
            try Task.checkCancellation()
            guard let target = mapping[saved.display], let screen = screens.first(where: { $0.uuid == target }),
                  let space = desktops[screen.uuid] else { continue }
            let info = Spaces.list(display: screen.uuid)
            let isDesktop = info?.desktops.contains { info?.ids[$0] == space } ?? true
            guard isDesktop else {
                failures.insert(saved.appName)
                matched[saved.id] = nil
                continue
            }
            switch TemplatePlacementPlan.desktopMove(membership: Spaces.of(window: window.id), destination: space) {
            case .unavailable:
                failures.insert(saved.appName)
                matched[saved.id] = nil
                continue
            case .move:
                guard await moveTemplateWindow(window, to: space) else {
                    failures.insert(saved.appName)
                    matched[saved.id] = nil
                    continue
                }
            case .stay:
                break
            }
            window.placementSuspended = false
            manager.templateHiddenWindows[window.id] = nil
            ready.append((saved, window))
        }
        let readyIDs = Set(ready.map(\.1.id))
        putBackHidden(restoreHidden.filter { !readyIDs.contains($0.1.id) })
        restoreHidden.removeAll { !readyIDs.contains($0.1.id) }
        try Task.checkCancellation()

        screens = Screen.all()
        guard !screens.isEmpty else { throw WindowManager.TemplateError.notReady }
        manager.syncWorkspaces(screens: screens, present: manager.present)
        let preferred = TemplatePlacementPlan.preferredDisplays(template, mapping: mapping)
        for display in template.displays where mapping[display.id].flatMap({ preferred[$0] }) == display.id {
            guard let target = mapping[display.id], let screen = screens.first(where: { $0.uuid == target }) else { continue }
            let state = manager.state(for: screen)
            state.layout = Layout(rawValue: display.layout) ?? .tall
            state.ratio = min(0.9, max(0.1, display.ratio))
            state.mainCount = max(1, display.mainCount)
            state.zoomed = nil
        }
        var frames: [CGWindowID: CGRect] = [:]
        var restored: [CGWindowID] = []
        for (saved, window) in ready {
            guard let target = mapping[saved.display], let screen = screens.first(where: { $0.uuid == target }),
                  let original = template.displays.first(where: { $0.id == saved.display }) else { continue }
            if manager.windows[window.id] == nil {
                manager.windows[window.id] = window
                manager.watch(window)
            }
            let frame = WorkspaceTemplate.restoredFrame(saved.frame, from: original.visible, to: screen.visible)
            window.userFloating = saved.floating
            window.naturalFrame = frame
            manager.model.assign(window.id, to: manager.workspaceKey(for: screen))
            manager.displayOf[window.id] = screen.uuid
            manager.floatFrames[window.id] = nil
            manager.targets[window.id] = nil
            manager.corrections[window.id] = nil
            manager.present.insert(window.id)
            if saved.minimized || saved.fullscreen { manager.present.remove(window.id) }
            if let zoomed = TemplatePlacementPlan.zoomedWindow(
                savedDisplay: saved.display, window: window.id, zoomed: saved.zoomed,
                preferredSavedDisplay: preferred[screen.uuid]) {
                manager.state(for: screen).zoomed = zoomed
            }
            frames[window.id] = frame
            restored.append(window.id)
        }
        let restoredIDs = Set(restored)
        manager.order = restored + manager.order.filter { !restoredIDs.contains($0) }
        manager.visible = manager.present.filter { manager.isShown(manager.workspaceOf[$0]) }
        manager.tilingEnabled = template.tilingEnabled
        if template.tilingEnabled {
            for screen in screens {
                let ids = manager.tiled(on: screen)
                guard let slots = manager.layoutTargets(ids, manager.state(for: screen), on: screen) else { continue }
                for (id, frame) in slots { frames[id] = frame; manager.targets[id] = frame }
            }
        }
        let moves = frames.compactMap { id, frame -> Animator.Move? in
            guard let window = manager.windows[id], let screen = manager.screen(of: window, in: screens) else { return nil }
            return .init(window: window, to: frame, bounds: screen.visible)
        }
        manager.animator.animate(moves, duration: 0)
        let placed = Set(moves.map(\.window.pid))
        let waited = TemplatePlacementPlan.writerBarrier(placed: placed, busy: manager.animator.activeWriterPids)
        let writesFinished = await placementWritesFinished(pids: waited)
        try Task.checkCancellation()
        if writesFinished {
            _ = try await settlePlacement(timeout: 0.8) {
                ready.filter { $0.0.floating || !self.template.tilingEnabled }.allSatisfy { _, window in
                    frames[window.id].map { window.frame.approxEqual($0, tolerance: 8) } ?? true
                }
            }
            for (saved, window) in ready where saved.floating || !template.tilingEnabled {
                if let target = frames[window.id], !window.frame.approxEqual(target, tolerance: 8) { failures.insert(saved.appName) }
            }
            for move in moves { manager.animator.cancel(move.window.id) }
            let drain = TemplatePlacementPlan.writerBarrier(placed: placed, busy: manager.animator.activeWriterPids)
            _ = await placementWritesFinished(pids: drain)
            try Task.checkCancellation()
        } else {
            let moved = Set(moves.map(\.window.id))
            for (saved, window) in ready where moved.contains(window.id) { failures.insert(saved.appName) }
            for move in moves { manager.animator.cancel(move.window.id) }
        }
        for (saved, window) in ready where saved.minimized || saved.fullscreen {
            try Task.checkCancellation()
            window.placementSuspended = true
            let changed = saved.minimized ? window.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
                : window.element.set("AXFullScreen", kCFBooleanTrue)
            manager.templateHiddenWindows[window.id] = Date()
            if !changed { failures.insert(saved.appName) }
        }
        restoreHidden = []
        _ = try await settlePlacement(timeout: 3) {
            ready.allSatisfy { saved, window in
                (!saved.minimized || window.element.bool(kAXMinimizedAttribute) == true) &&
                    (!saved.fullscreen || saved.minimized || window.isNativeFullscreen)
            }
        }
        for (saved, window) in ready where saved.minimized || saved.fullscreen {
            let confirmed = saved.minimized ? window.element.bool(kAXMinimizedAttribute) == true : window.isNativeFullscreen
            if confirmed {
                manager.templateHiddenWindows[window.id] = Date()
            } else {
                window.placementSuspended = false
                manager.templateHiddenWindows[window.id] = nil
                failures.insert(saved.appName)
            }
        }
        if let (_, window) = ready.first(where: { $0.0.focused && !$0.0.minimized }) { manager.focus(window, warp: false) }
    }

    private func putBackHidden(_ items: [(WorkspaceTemplate.SavedWindow, Window)]) {
        for (_, window) in items { manager.animator.cancel(window.id) }
        for (saved, window) in items where saved.minimized || saved.fullscreen {
            window.placementSuspended = true
            if saved.minimized {
                _ = window.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
            } else {
                _ = window.element.set("AXFullScreen", kCFBooleanTrue)
            }
            manager.templateHiddenWindows[window.id] = Date()
        }
    }

    private func settlePlacement(timeout: TimeInterval, check: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            try Task.checkCancellation()
            if check() { return true }
            if Date() >= deadline { return false }
            try await Task.sleep(for: .milliseconds(60))
        }
    }

    private func placementWritesFinished(pids: Set<pid_t>) async -> Bool {
        let finished = PlacementSignal()
        manager.animator.afterPendingWrites(pids: pids) { finished.complete(true) }
        let deadline = Date().addingTimeInterval(2)
        while true {
            if finished.isComplete { return finished.claim(true) }
            if Task.isCancelled || Date() >= deadline { return finished.claim(false) }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func moveTemplateWindow(_ window: Window, to space: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            Spaces.move(window: window.id, to: space) { continuation.resume(returning: $0) }
        }
    }
}

private final class PlacementSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?

    func complete(_ success: Bool) {
        lock.lock()
        if value == nil { value = success }
        lock.unlock()
    }

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value != nil
    }

    func claim(_ fallback: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let result = value ?? fallback
        value = result
        return result
    }
}

enum TemplatePlacementError: LocalizedError {
    case busy

    var errorDescription: String? { "Windows are still moving. Try opening the template again." }
}
