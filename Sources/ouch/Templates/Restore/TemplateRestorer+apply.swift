import AppKit

private typealias TemplatePair = (WorkspaceTemplate.SavedWindow, Window)

extension TemplateRestorer {
    func apply() async throws {
        var screens = Screen.all()
        guard !screens.isEmpty else { throw WindowManager.TemplateError.notReady }
        let mainID = NSScreen.screens.first?.displayID
        let mapping = template.displayMap(available: screens.map { ($0.uuid, $0.id == mainID) })
        var pairs = template.windows.compactMap { saved -> TemplatePair? in
            matched[saved.id].map { (saved, $0) }
        }
        for (_, window) in pairs { manager.animator.cancel(window.id) }
        let opening = TemplatePlacementPlan.writerBarrier(placed: Set(pairs.map(\.1.pid)),
                                                          busy: manager.animator.activeWriterPids)
        let openingFinished = await placementWritesFinished(pids: opening)
        try Task.checkCancellation()
        guard openingFinished else { throw TemplatePlacementError.busy }

        var restoreHidden: [TemplatePair] = []
        defer { putBackHidden(restoreHidden) }

        let exitingDisplays = unhide(pairs, screens: screens, restoreHidden: &restoreHidden)
        _ = try await settlePlacement(timeout: 3) {
            pairs.allSatisfy { !$0.1.isNativeFullscreen && !$0.1.element.flag(kAXMinimizedAttribute) } &&
                exitingDisplays.allSatisfy { !Spaces.isFullscreen(display: $0) }
        }
        pairs = dropStillHidden(pairs, restoreHidden: &restoreHidden)
        manager.syncWorkspaces(screens: screens, present: manager.present)
        let ready = try await moveToDesktops(pairs, mapping: mapping, screens: screens)
        let readyIDs = Set(ready.map(\.1.id))
        putBackHidden(restoreHidden.filter { !readyIDs.contains($0.1.id) })
        restoreHidden.removeAll { !readyIDs.contains($0.1.id) }
        try Task.checkCancellation()

        screens = Screen.all()
        guard !screens.isEmpty else { throw WindowManager.TemplateError.notReady }
        manager.syncWorkspaces(screens: screens, present: manager.present)
        let preferred = TemplatePlacementPlan.preferredDisplays(template, mapping: mapping)
        applyDisplayLayouts(mapping: mapping, preferred: preferred, screens: screens)
        var frames = register(ready, mapping: mapping, preferred: preferred, screens: screens)
        if template.tilingEnabled { addTiledFrames(&frames, screens: screens) }
        try await place(ready, frames: frames, screens: screens)
        restoreHidden = []
        try await rehide(ready)
        if let (_, window) = ready.first(where: { $0.0.focused && !$0.0.minimized }) {
            manager.focus(window, warp: false)
        }
    }

    private func unhide(_ pairs: [TemplatePair], screens: [Screen],
                        restoreHidden: inout [TemplatePair]) -> Set<String> {
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
            if window.element.flag(kAXMinimizedAttribute) {
                clearedMinimized = window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
            }
            if (saved.minimized || saved.fullscreen) && (clearedMinimized || clearedFullscreen) {
                restoreHidden.append((saved, window))
            }
        }
        return exitingDisplays
    }

    private func dropStillHidden(_ pairs: [TemplatePair], restoreHidden: inout [TemplatePair]) -> [TemplatePair] {
        pairs.filter { saved, window in
            guard !window.isNativeFullscreen, !window.element.flag(kAXMinimizedAttribute) else {
                failures.insert(saved.appName)
                matched[saved.id] = nil
                restoreHidden.removeAll { $0.1.id == window.id }
                return false
            }
            return true
        }
    }

    private func moveToDesktops(_ pairs: [TemplatePair], mapping: [String: String],
                                screens: [Screen]) async throws -> [TemplatePair] {
        var desktops: [String: UInt64] = [:]
        for screen in screens { desktops[screen.uuid] = Spaces.current(display: screen.uuid) }
        var ready: [TemplatePair] = []
        for (saved, window) in pairs {
            try Task.checkCancellation()
            guard let target = mapping[saved.display], let screen = screens.first(where: { $0.uuid == target }),
                  let space = desktops[screen.uuid] else { continue }
            guard await moveToDesktop(window, space: space, display: screen.uuid) else {
                failures.insert(saved.appName)
                matched[saved.id] = nil
                continue
            }
            window.placementSuspended = false
            manager.templateHiddenWindows[window.id] = nil
            ready.append((saved, window))
        }
        return ready
    }

    private func moveToDesktop(_ window: Window, space: UInt64, display: String) async -> Bool {
        let info = Spaces.list(display: display)
        let isDesktop = info?.desktops.contains { info?.ids[$0] == space } ?? true
        guard isDesktop else { return false }
        switch TemplatePlacementPlan.desktopMove(membership: Spaces.of(window: window.id), destination: space) {
        case .unavailable:
            guard initialWindowIDs?.contains(window.id) == false else { return false }
            return await moveTemplateWindow(window, to: space)
        case .move:
            return await moveTemplateWindow(window, to: space)
        case .stay:
            return true
        }
    }

    private func applyDisplayLayouts(mapping: [String: String], preferred: [String: String], screens: [Screen]) {
        for display in template.displays where mapping[display.id].flatMap({ preferred[$0] }) == display.id {
            guard let target = mapping[display.id],
                  let screen = screens.first(where: { $0.uuid == target }) else { continue }
            let state = manager.state(for: screen)
            state.layout = Layout(rawValue: display.layout) ?? .tall
            state.ratio = min(0.9, max(0.1, display.ratio))
            state.mainCount = max(1, display.mainCount)
            state.zoomed = nil
        }
    }

    private func register(_ ready: [TemplatePair], mapping: [String: String], preferred: [String: String],
                          screens: [Screen]) -> [CGWindowID: CGRect] {
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
            window.userFloating = .chosen(saved.floating)
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
        return frames
    }

    private func addTiledFrames(_ frames: inout [CGWindowID: CGRect], screens: [Screen]) {
        for screen in screens {
            let ids = manager.tiled(on: screen)
            guard let slots = manager.layoutTargets(ids, manager.state(for: screen), on: screen) else { continue }
            for (id, frame) in slots {
                frames[id] = frame
                manager.targets[id] = frame
            }
        }
    }

    private func place(_ ready: [TemplatePair], frames: [CGWindowID: CGRect], screens: [Screen]) async throws {
        let moves = frames.compactMap { id, frame -> Animator.Move? in
            guard let window = manager.windows[id],
                  let screen = manager.screen(of: window, in: screens) else { return nil }
            return .init(window: window, to: frame, bounds: screen.visible)
        }
        let config = manager.config
        let duration = config.animate && config.animationDuration >= 0.01 ? config.animationDuration : 0
        manager.animator.animate(moves, duration: duration, curve: config.animationCurve,
                                 bounce: config.animationBounce)
        if duration > 0 {
            _ = try await settlePlacement(timeout: duration + 0.6) {
                moves.allSatisfy { !self.manager.animator.isBusy($0.window.id) }
            }
        }
        let placed = Set(moves.map(\.window.pid))
        let waited = TemplatePlacementPlan.writerBarrier(placed: placed, busy: manager.animator.activeWriterPids)
        let writesFinished = await placementWritesFinished(pids: waited)
        try Task.checkCancellation()
        guard writesFinished else {
            let moved = Set(moves.map(\.window.id))
            for (saved, window) in ready where moved.contains(window.id) { failures.insert(saved.appName) }
            for move in moves { manager.animator.cancel(move.window.id) }
            return
        }
        _ = try await settlePlacement(timeout: 0.8) {
            ready.filter { $0.0.floating || !self.template.tilingEnabled }.allSatisfy { _, window in
                frames[window.id].map { window.frame.approxEqual($0, tolerance: 8) } ?? true
            }
        }
        for (saved, window) in ready where saved.floating || !template.tilingEnabled {
            if let target = frames[window.id], !window.frame.approxEqual(target, tolerance: 8) {
                failures.insert(saved.appName)
            }
        }
        for move in moves { manager.animator.cancel(move.window.id) }
        let drain = TemplatePlacementPlan.writerBarrier(placed: placed, busy: manager.animator.activeWriterPids)
        _ = await placementWritesFinished(pids: drain)
        try Task.checkCancellation()
    }

    private func rehide(_ ready: [TemplatePair]) async throws {
        for (saved, window) in ready where saved.minimized || saved.fullscreen {
            try Task.checkCancellation()
            window.placementSuspended = true
            let changed = saved.minimized ? window.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
                : window.element.set("AXFullScreen", kCFBooleanTrue)
            manager.templateHiddenWindows[window.id] = Date()
            if !changed { failures.insert(saved.appName) }
        }
        _ = try await settlePlacement(timeout: 3) {
            ready.allSatisfy { saved, window in
                (!saved.minimized || window.element.flag(kAXMinimizedAttribute)) &&
                    (!saved.fullscreen || saved.minimized || window.isNativeFullscreen)
            }
        }
        for (saved, window) in ready where saved.minimized || saved.fullscreen {
            let confirmed = saved.minimized
                ? window.element.flag(kAXMinimizedAttribute)
                : window.isNativeFullscreen
            if confirmed {
                manager.templateHiddenWindows[window.id] = Date()
            } else {
                window.placementSuspended = false
                manager.templateHiddenWindows[window.id] = nil
                failures.insert(saved.appName)
            }
        }
    }

    private func putBackHidden(_ items: [TemplatePair]) {
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
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func placementWritesFinished(pids: Set<pid_t>) async -> Bool {
        let finished = PlacementSignal()
        manager.animator.afterPendingWrites(pids: pids) { finished.complete(true) }
        let deadline = Date().addingTimeInterval(2)
        while true {
            if finished.isComplete { return finished.claim(true) }
            if Task.isCancelled || Date() >= deadline { return finished.claim(false) }
            try? await Task.sleep(for: .milliseconds(10))
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
    private var settled = false
    private var value = false

    func complete(_ success: Bool) {
        lock.lock()
        if !settled {
            settled = true
            value = success
        }
        lock.unlock()
    }

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled
    }

    func claim(_ fallback: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !settled {
            settled = true
            value = fallback
        }
        return value
    }
}

enum TemplatePlacementError: LocalizedError {
    case busy

    var errorDescription: String? { "Windows are still moving. Try opening the template again." }
}
