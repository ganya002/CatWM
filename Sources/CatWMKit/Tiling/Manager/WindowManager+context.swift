import AppKit

package struct TilingContext {
    package let window: Window?
    package let screen: Screen
    package let state: ScreenState
    package let ids: [CGWindowID]
}

extension WindowManager {
    package func context() -> TilingContext? {
        guard let screen = currentScreen() else { return nil }
        return TilingContext(window: focusedWindow(), screen: screen, state: state(for: screen), ids: tiled(on: screen))
    }

    package func cycleFocus(_ delta: Int) {
        guard let current = context(), !current.ids.isEmpty else { return }
        let ids = current.ids
        let i = current.window.flatMap { ids.firstIndex(of: $0.id) } ?? (delta > 0 ? -1 : 0)
        let next = ids[((i + delta) % ids.count + ids.count) % ids.count]
        if let window = windows[next] { focus(window) }
    }

    package func cycleSwap(_ delta: Int) {
        guard let current = context(), let window = current.window,
              let i = current.ids.firstIndex(of: window.id), current.ids.count > 1 else { return }
        let ids = current.ids
        swapOrder(window.id, ids[((i + delta) % ids.count + ids.count) % ids.count])
        refresh()
    }

    package func swapWithMain() {
        guard let current = context(), let window = current.window,
              current.ids.count > 1, current.ids.contains(window.id) else { return }
        swapOrder(window.id, current.ids[0] == window.id ? current.ids[1] : current.ids[0])
        refresh()
        focus(window)
    }

    package func focusMain() {
        guard let current = context(), let id = current.ids.first, let window = windows[id] else { return }
        focus(window)
    }

    package func changeMainCount(_ delta: Int) {
        guard let current = context() else { return }
        current.state.mainCount = max(1, min(10, current.state.mainCount + delta))
        corrections = [:]
        refresh()
    }

    package func adjustRatio(_ arg: String) {
        guard let current = context() else { return }
        let parts = arg.lowercased().split(separator: " ")
        var ratio = current.state.ratio
        if parts.first == "exact", parts.count > 1, let value = Double(parts[1]) {
            ratio = CGFloat(value)
        } else {
            let delta = Double(arg.replacingOccurrences(of: "+", with: "")).map { CGFloat($0) }
                ?? config.windowResizeStep
            ratio += delta
        }
        ratio = min(0.9, max(0.1, ratio))
        if let stubborn = windowRefusingRatio(ratio, from: current.state.ratio, ids: current.ids,
                                              on: current.screen, current.state) {
            warnTooSmall(stubborn, on: current.screen)
            return
        }
        current.state.ratio = ratio
        corrections = [:]
        dividerState.ratioChange = (current.screen.uuid, Date() + (config.animate ? config.animationDuration : 0) + 0.6)
        refresh()
    }

    package func toggleFloating() {
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

    package func toggleZoom() {
        guard let current = context(), let window = current.window else { return }
        if floatsFreely(window.id) { return toggleFloatZoom(window) }
        guard current.ids.contains(window.id) else { return }
        tilingRecovery.zoomed[workspaceKey(for: current.screen)] = nil
        current.state.zoomed = current.state.zoomed == window.id ? nil : window.id
        refresh()
        focus(window, warp: false)
    }

    package func toggleFloatZoom(_ window: Window) {
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

    package func toggleNativeFullscreen() {
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

    package func cycleLayout(_ delta: Int) {
        guard let current = context(), !config.layouts.isEmpty else { return }
        let layouts = config.layouts
        let layout = current.state.layout
        let i = layouts.firstIndex(of: layout) ?? layout.mirrored.flatMap { layouts.firstIndex(of: $0) }
            ?? (delta > 0 ? -1 : 0)
        setLayout(layouts[((i + delta) % layouts.count + layouts.count) % layouts.count], on: current.screen)
    }

    package func closeWindow(_ id: CGWindowID) -> Bool {
        guard let window = windows[id] else { return false }
        closeAndSort.lastClose = Date()
        markClosedTab(id)
        scanner.run(window.pid) { window.close() }
        return true
    }

    package func minimize(_ window: Window) {
        scanner.run(window.pid) { window.element.set(kAXMinimizedAttribute, kCFBooleanTrue) }
    }
}
