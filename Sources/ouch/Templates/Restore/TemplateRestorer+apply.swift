import AppKit

extension TemplateRestorer {
    func apply() async throws {
        let screens = Screen.all()
        guard !screens.isEmpty else { throw WindowManager.TemplateError.notReady }
        let mainID = NSScreen.screens.first?.displayID
        let mapping = template.displayMap(available: screens.map { ($0.uuid, $0.id == mainID) })
        let pairs = template.windows.compactMap { saved -> (WorkspaceTemplate.SavedWindow, Window)? in
            matched[saved.id].map { (saved, $0) }
        }
        var exitedFullscreen = false
        for (_, window) in pairs {
            manager.animator.cancel(window.id)
            if window.isNativeFullscreen {
                window.element.set("AXFullScreen", kCFBooleanFalse)
                exitedFullscreen = true
            }
            window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        if exitedFullscreen { try await Task.sleep(for: .seconds(1)) }
        try Task.checkCancellation()
        manager.syncWorkspaces(screens: screens, present: manager.present)
        var configured = Set<String>()
        for display in template.displays.sorted(by: { $0.isMain && !$1.isMain }) {
            guard let target = mapping[display.id], let screen = screens.first(where: { $0.uuid == target }),
                  configured.insert(target).inserted else { continue }
            let state = manager.state(for: screen)
            state.layout = Layout(rawValue: display.layout) ?? .tall
            state.ratio = min(0.9, max(0.1, display.ratio))
            state.mainCount = max(1, display.mainCount)
            state.zoomed = nil
        }
        var restored: [CGWindowID] = []
        for (saved, window) in pairs {
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
            manager.snapNextPlacement.insert(window.id)
            window.setFrame(frame)
            if saved.zoomed { manager.state(for: screen).zoomed = window.id }
            restored.append(window.id)
            if !window.frame.approxEqual(frame, tolerance: 8) && (saved.floating || !template.tilingEnabled) {
                failures.insert(saved.appName)
            }
        }
        let restoredIDs = Set(restored)
        manager.order = restored + manager.order.filter { !restoredIDs.contains($0) }
        manager.tilingEnabled = template.tilingEnabled
        manager.restoringTemplate = false
        manager.refresh(instant: true)
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()
        for (saved, window) in pairs {
            if saved.minimized {
                if !window.element.set(kAXMinimizedAttribute, kCFBooleanTrue) { failures.insert(saved.appName) }
            } else if saved.fullscreen {
                if !window.element.set("AXFullScreen", kCFBooleanTrue) { failures.insert(saved.appName) }
            }
        }
        if let (_, window) = pairs.first(where: { $0.0.focused && !$0.0.minimized }) { manager.focus(window, warp: false) }
    }
}
