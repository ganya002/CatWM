import AppKit

extension WindowManager {
    func context() -> (w: Window?, s: Screen, st: ScreenState, ids: [CGWindowID])? {
        guard let s = currentScreen() else { return nil }
        return (focusedWindow(), s, state(for: s), tiled(on: s))
    }

    func moveFocus(_ d: Direction) {
        guard let w = focusedWindow() else {
            if let c = context(), let first = c.ids.first.flatMap({ windows[$0] }) { focus(first) }
            return
        }
        let candidates = order.filter(visible.contains).compactMap { windows[$0] }
        let screens = Screen.all()
        let home = screen(of: w, in: screens)
        if let home, state(for: home).zoomed == w.id { cycleFocus(d == .left || d == .up ? -1 : 1); return }
        let to = FocusNavigation.target(from: navItem(w, in: screens), d,
                                        among: candidates.map { navItem($0, in: screens) }, stamps: focusStamps)
        if let n = to.flatMap({ windows[$0] }) { focus(n) }
    }

    func moveWindow(_ d: Direction) {
        guard let w = focusedWindow(), !w.isFloating else { return }
        let candidates = order.filter(visible.contains).compactMap { windows[$0] }.filter { !$0.isFloating }
        if let n = neighbor(of: w, d, among: candidates) {
            if let a = screen(of: w), let b = screen(of: n), a.uuid != b.uuid {
                model.assign(w.id, to: shown[b.uuid])
            } else {
                swapOrder(w.id, n.id)
            }
        } else if let src = screen(of: w), let dst = screen(from: src, spec: arg(d), in: Screen.all()) {
            model.assign(w.id, to: shown[dst.uuid])
        } else { return }
        refresh()
        focus(w)
    }

    func arg(_ d: Direction) -> String {
        switch d { case .left: "l"; case .right: "r"; case .up: "u"; case .down: "d" }
    }

    func cycleFocus(_ delta: Int) {
        guard let c = context(), !c.ids.isEmpty else { return }
        let i = c.w.flatMap { c.ids.firstIndex(of: $0.id) } ?? (delta > 0 ? -1 : 0)
        let next = c.ids[((i + delta) % c.ids.count + c.ids.count) % c.ids.count]
        if let w = windows[next] { focus(w) }
    }

    func cycleSwap(_ delta: Int) {
        guard let c = context(), let w = c.w, let i = c.ids.firstIndex(of: w.id), c.ids.count > 1 else { return }
        swapOrder(w.id, c.ids[((i + delta) % c.ids.count + c.ids.count) % c.ids.count])
        refresh()
    }

    func swapWithMain() {
        guard let c = context(), let w = c.w, c.ids.count > 1, c.ids.contains(w.id) else { return }
        swapOrder(w.id, c.ids[0] == w.id ? c.ids[1] : c.ids[0])
        refresh()
        focus(w)
    }

    func focusMain() {
        guard let c = context(), let id = c.ids.first, let w = windows[id] else { return }
        focus(w)
    }

    func changeMainCount(_ delta: Int) {
        guard let c = context() else { return }
        c.st.mainCount = max(1, min(10, c.st.mainCount + delta))
        corrections = [:]
        refresh()
    }

    func adjustRatio(_ arg: String) {
        guard let c = context() else { return }
        let parts = arg.lowercased().split(separator: " ")
        var ratio = c.st.ratio
        if parts.first == "exact", parts.count > 1, let v = Double(parts[1]) {
            ratio = CGFloat(v)
        } else {
            let delta = Double(arg.replacingOccurrences(of: "+", with: "")).map { CGFloat($0) } ?? config.windowResizeStep
            ratio += delta
        }
        ratio = min(0.9, max(0.1, ratio))
        if let stubborn = windowRefusingRatio(ratio, from: c.st.ratio, ids: c.ids, on: c.s, c.st) {
            warnTooSmall(stubborn, on: c.s)
            return
        }
        c.st.ratio = ratio
        corrections = [:]
        ratioChange = (c.s.uuid, Date() + (config.animate ? config.animationDuration : 0) + 0.6)
        refresh()
    }

    func toggleFloating() {
        guard let w = focusedWindow() else { return }
        w.userFloating = !w.isFloating
        if w.isFloating {
            targets[w.id] = nil
        } else {
            if let s = screen(containing: w.frame) { model.assign(w.id, to: shown[s.uuid]) }
            corrections[w.id] = nil
        }
        refresh()
    }

    func toggleZoom() {
        guard let c = context(), let w = c.w, c.ids.contains(w.id) else { return }
        c.st.zoomed = c.st.zoomed == w.id ? nil : w.id
        refresh()
        focus(w, warp: false)
    }

    func toggleNativeFullscreen() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el = focusedWindow()?.element
                ?? axApp(app.processIdentifier).element(kAXFocusedWindowAttribute) else { return }
        let on = el.bool("AXFullScreen") ?? false
        let done: Bool
        if el.isSettable("AXFullScreen") {
            done = el.set("AXFullScreen", on ? kCFBooleanFalse : kCFBooleanTrue)
        } else if let button = el.element("AXFullScreenButton") ?? el.element(kAXZoomButtonAttribute) {
            done = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        } else {
            done = false
        }
        Log.info("native fullscreen \(on ? "off" : "on") for \(el.windowID.map(String.init) ?? "?") \(app.bundleIdentifier ?? ""): \(done ? "ok" : "refused")")
        guard done else { return }
        if let id = el.windowID, !on { for s in Screen.all() where state(for: s).zoomed == id { state(for: s).zoomed = nil } }
        scheduleRefresh(after: 0.8)
    }

    func cycleLayout(_ delta: Int) {
        guard let c = context(), !config.layouts.isEmpty else { return }
        let i = config.layouts.firstIndex(of: c.st.layout) ?? (delta > 0 ? -1 : 0)
        setLayout(config.layouts[((i + delta) % config.layouts.count + config.layouts.count) % config.layouts.count], on: c.s)
    }

}
