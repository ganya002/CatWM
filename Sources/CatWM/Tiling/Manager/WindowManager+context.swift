import AppKit

struct TilingContext {
    let window: Window?
    let screen: Screen
    let state: ScreenState
    let ids: [CGWindowID]
}

extension WindowManager {
    func context() -> TilingContext? {
        guard let screen = currentScreen() else { return nil }
        return TilingContext(window: focusedWindow(), screen: screen, state: state(for: screen), ids: tiled(on: screen))
    }

    func cycleFocus(_ delta: Int) {
        guard let current = context(), !current.ids.isEmpty else { return }
        let ids = current.ids
        let i = current.window.flatMap { ids.firstIndex(of: $0.id) } ?? (delta > 0 ? -1 : 0)
        let next = ids[((i + delta) % ids.count + ids.count) % ids.count]
        if let window = windows[next] { focus(window) }
    }

    func cycleSwap(_ delta: Int) {
        guard let current = context(), let window = current.window,
              let i = current.ids.firstIndex(of: window.id), current.ids.count > 1 else { return }
        let ids = current.ids
        swapOrder(window.id, ids[((i + delta) % ids.count + ids.count) % ids.count])
        refresh()
    }

    func toggleFloating() {
        guard let window = focusedWindow() else { return }
        window.userFloating = .chosen(!window.isFloating)
        floats.floatZoom[window.id] = nil
        if window.isFloating {
            targets[window.id] = nil
        } else {
            if let screen = screen(containing: window.cachedFrame) {
                assignManagedWindow(window.id, to: shown[screen.uuid])
            }
            corrections[window.id] = nil
        }
        refresh()
    }

    func toggleZoom() {
        guard let current = context(), let window = current.window else { return }
        if floatsFreely(window.id) { return toggleFloatZoom(window) }
        guard current.ids.contains(window.id) else { return }
        tilingRecovery.zoomed[workspaceKey(for: current.screen)] = nil
        current.state.zoomed = current.state.zoomed == window.id ? nil : window.id
        refresh()
        focus(window, warp: false)
    }

    func toggleFloatZoom(_ window: Window) {
        guard let screen = screen(of: window) else { return }
        let fill = usableRect(screen).pixelAligned
        let frame = animator.destination(window.id) ?? window.cachedFrame
        let target: CGRect
        if let saved = floats.floatZoom.removeValue(forKey: window.id), frame.approxEqual(fill) {
            target = saved
        } else {
            floats.floatZoom[window.id] = frame
            target = fill
        }
        animator.animate([.init(window: window, to: target, bounds: screen.visible)],
                         duration: config.animate ? config.animationDuration : 0,
                         curve: config.animationCurve, bounce: config.animationBounce)
        focus(window, warp: false)
    }

    func toggleNativeFullscreen() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let known = focusedWindow()?.element
        scanner.run(pid) { [weak self] in
            guard let element = known ?? axApp(pid).element(kAXFocusedWindowAttribute) else { return }
            let isOn = element.flag("AXFullScreen")
            let done: Bool
            if element.isSettable("AXFullScreen") {
                done = element.set("AXFullScreen", isOn ? kCFBooleanFalse : kCFBooleanTrue)
            } else if let button = element.element("AXFullScreenButton") ?? element.element(kAXZoomButtonAttribute) {
                done = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            } else {
                done = false
            }
            let id = element.windowID
            DispatchQueue.main.async {
                self?.finishNativeFullscreen(id, app: app.bundleIdentifier, wasOn: isOn, done: done)
            }
        }
    }

    private func finishNativeFullscreen(_ id: CGWindowID?, app: String?, wasOn isOn: Bool, done: Bool) {
        Log.info(
            "native fullscreen \(isOn ? "off" : "on") for \(id.map(String.init) ?? "?") \(app ?? ""): "
                + (done ? "ok" : "refused")
        )
        guard done else { return }
        if let id, !isOn {
            for screen in backend.screens() where state(for: screen).zoomed == id { state(for: screen).zoomed = nil }
        }
        scheduleRefresh(after: 0.8)
    }

    func closeWindow(_ id: CGWindowID) -> Bool {
        guard let window = windows[id] else { return false }
        closeAndSort.lastClose = Date()
        markClosedTab(id)
        scanner.run(window.pid) { window.close() }
        return true
    }

    func minimize(_ window: Window) {
        scanner.run(window.pid) { window.element.set(kAXMinimizedAttribute, kCFBooleanTrue) }
    }
}
