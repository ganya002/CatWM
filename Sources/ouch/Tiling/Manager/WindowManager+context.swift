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

    func moveFocus(_ direction: Direction) {
        guard let window = focusedWindow() else {
            if let current = context(), let first = current.ids.first.flatMap({ windows[$0] }) { focus(first) }
            return
        }
        let candidates = order.filter(visible.contains).compactMap { windows[$0] }
        let screens = Screen.all()
        let home = screen(of: window, in: screens)
        if let home, state(for: home).zoomed == window.id {
            cycleFocus(direction == .left || direction == .upward ? -1 : 1)
            return
        }
        let target = FocusNavigation.target(from: navItem(window, in: screens), direction,
                                            among: candidates.map { navItem($0, in: screens) }, stamps: focusStamps)
        if let next = target.flatMap({ windows[$0] }) { focus(next) }
    }

    func moveWindow(_ direction: Direction) {
        guard let window = focusedWindow(), !window.isFloating else { return }
        let candidates = order.filter(visible.contains).compactMap { windows[$0] }.filter { !$0.isFloating }
        if let next = neighbor(of: window, direction, among: candidates) {
            if let from = screen(of: window), let into = screen(of: next), from.uuid != into.uuid {
                assignManagedWindow(window.id, to: shown[into.uuid])
            } else {
                swapOrder(window.id, next.id)
            }
        } else if let src = screen(of: window), let dst = screen(from: src, spec: arg(direction), in: Screen.all()) {
            assignManagedWindow(window.id, to: shown[dst.uuid])
        } else { return }
        refresh()
        focus(window)
    }

    func arg(_ direction: Direction) -> String {
        switch direction {
        case .left: "l"
        case .right: "r"
        case .upward: "u"
        case .down: "d"
        }
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

    func swapWithMain() {
        guard let current = context(), let window = current.window,
              current.ids.count > 1, current.ids.contains(window.id) else { return }
        swapOrder(window.id, current.ids[0] == window.id ? current.ids[1] : current.ids[0])
        refresh()
        focus(window)
    }

    func focusMain() {
        guard let current = context(), let id = current.ids.first, let window = windows[id] else { return }
        focus(window)
    }

    func changeMainCount(_ delta: Int) {
        guard let current = context() else { return }
        current.state.mainCount = max(1, min(10, current.state.mainCount + delta))
        corrections = [:]
        refresh()
    }

    func adjustRatio(_ arg: String) {
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
        ratioChange = (current.screen.uuid, Date() + (config.animate ? config.animationDuration : 0) + 0.6)
        refresh()
    }

    func toggleFloating() {
        guard let window = focusedWindow() else { return }
        window.userFloating = .chosen(!window.isFloating)
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
        guard let current = context(), let window = current.window, current.ids.contains(window.id) else { return }
        current.state.zoomed = current.state.zoomed == window.id ? nil : window.id
        refresh()
        focus(window, warp: false)
    }

    func toggleNativeFullscreen() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let element = focusedWindow()?.element
                ?? axApp(app.processIdentifier).element(kAXFocusedWindowAttribute) else { return }
        let isOn = element.flag("AXFullScreen")
        let done: Bool
        if element.isSettable("AXFullScreen") {
            done = element.set("AXFullScreen", isOn ? kCFBooleanFalse : kCFBooleanTrue)
        } else if let button = element.element("AXFullScreenButton") ?? element.element(kAXZoomButtonAttribute) {
            done = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        } else {
            done = false
        }
        let windowName = element.windowID.map(String.init) ?? "?"
        Log.info(
            "native fullscreen \(isOn ? "off" : "on") for \(windowName) \(app.bundleIdentifier ?? ""): "
                + (done ? "ok" : "refused")
        )
        guard done else { return }
        if let id = element.windowID, !isOn {
            for screen in Screen.all() where state(for: screen).zoomed == id { state(for: screen).zoomed = nil }
        }
        scheduleRefresh(after: 0.8)
    }

    func cycleLayout(_ delta: Int) {
        guard let current = context(), !config.layouts.isEmpty else { return }
        let layouts = config.layouts
        let layout = current.state.layout
        let i = layouts.firstIndex(of: layout) ?? layout.mirrored.flatMap { layouts.firstIndex(of: $0) }
            ?? (delta > 0 ? -1 : 0)
        setLayout(layouts[((i + delta) % layouts.count + layouts.count) % layouts.count], on: current.screen)
    }
}
