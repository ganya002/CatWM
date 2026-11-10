import AppKit

private typealias TemplatePair = (SavedWindow, Window)

extension TemplateRestorer {
    package func apply() async throws {
        var screens = Screen.all()
        guard !screens.isEmpty else { throw WindowManager.TemplateError.notReady }
        let mainID = NSScreen.screens.first?.displayID
        let mapping = template.displayMap(available: screens.map { ($0.uuid, $0.id == mainID) })
        var pairs = template.windows.compactMap { saved -> TemplatePair? in
            matched[saved.id].map { (saved, $0) }
        }
        try await manager.preparePlacement(pairs.map(\.1))

        var restoreHidden: [TemplatePair] = []
        defer { putBackHidden(restoreHidden) }

        let exitingDisplays = unhide(pairs, screens: screens, restoreHidden: &restoreHidden)
        _ = try await settlePlacement(timeout: 3) {
            pairs.allSatisfy { !$0.1.fullscreenUnlessStalled && !$0.1.minimizedUnlessStalled } &&
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
        let displays = template.displays.compactMap { display -> DisplayPlacement? in
            guard let target = mapping[display.id], preferred[target] == display.id,
                  let screen = screens.first(where: { $0.uuid == target }) else { return nil }
            return .init(screen: screen, layout: Layout(rawValue: display.layout) ?? .tall,
                         ratio: display.ratio, mainCount: display.mainCount)
        }
        let placements = ready.compactMap { saved, window -> WindowPlacement? in
            guard let target = mapping[saved.display], let screen = screens.first(where: { $0.uuid == target }),
                  let original = template.displays.first(where: { $0.id == saved.display }) else { return nil }
            let frame = WorkspaceTemplate.restoredFrame(saved.frame, from: original.visible, to: screen.visible)
            return .init(window: window, screen: screen, frame: frame,
                         floating: saved.floating, hidden: saved.minimized || saved.fullscreen,
                         zoomed: saved.zoomed && saved.display == preferred[screen.uuid])
        }
        let frames = manager.registerPlacements(placements, displays: displays,
                                                tiling: template.tilingEnabled, screens: screens)
        let verifying = Set(ready.filter { $0.0.floating || !template.tilingEnabled }.map(\.1.id))
        let failed = try await manager.placeWindows(frames, verifying: verifying, screens: screens)
        for (saved, window) in ready where failed.contains(window.id) { failures.insert(saved.appName) }
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
            manager.placementHolds.resume(window)
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

    private func rehide(_ ready: [TemplatePair]) async throws {
        for (saved, window) in ready where saved.minimized || saved.fullscreen {
            try Task.checkCancellation()
            let changed = manager.hideForPlacement(window, minimized: saved.minimized)
            if !changed { failures.insert(saved.appName) }
        }
        _ = try await settlePlacement(timeout: 3) {
            ready.allSatisfy { saved, window in
                (!saved.minimized || window.minimizedUnlessStalled) &&
                    (!saved.fullscreen || saved.minimized || window.fullscreenUnlessStalled)
            }
        }
        for (saved, window) in ready where saved.minimized || saved.fullscreen {
            let confirmed = saved.minimized
                ? window.minimizedUnlessStalled
                : window.fullscreenUnlessStalled
            if confirmed {
                manager.holdPlacement(window)
            } else {
                manager.placementHolds.resume(window)
                failures.insert(saved.appName)
            }
        }
    }

    private func putBackHidden(_ items: [TemplatePair]) {
        for (saved, window) in items where saved.minimized || saved.fullscreen {
            manager.hideForPlacement(window, minimized: saved.minimized)
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

    private func moveTemplateWindow(_ window: Window, to space: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            Spaces.move(window: window.id, to: space) { continuation.resume(returning: $0) }
        }
    }
}
