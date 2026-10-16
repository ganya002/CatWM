// Tiling: status, IPC and the dispatch of keyboard commands (focus, swap, ratio, layout, monitor).
import AppKit

extension WindowManager {
    // MARK: - Status & IPC

    struct Status {
        var trusted: Bool
        var keybindsActive: Bool
        var running: Bool
        var tilingEnabled: Bool
        var launchAtLogin: Bool
        var loginNeedsApproval: Bool
        var inputMonitoring: Bool
        var tiled: Int
        var floating: Int
        var screens: [(uuid: String, name: String, layout: Layout, workspace: String)]
    }

    func status() -> Status {
        let screens = Screen.all()
        let managed = visible.compactMap { windows[$0] }
        return Status(trusted: Permission.accessibility.isGranted, keybindsActive: Hotkeys.shared.isActive, running: isStarted,
                      tilingEnabled: tilingEnabled,
                      launchAtLogin: LoginItem.isEnabled, loginNeedsApproval: LoginItem.needsApproval,
                      inputMonitoring: Permission.inputMonitoring.isGranted,
                      tiled: managed.filter { !$0.isFloating }.count, floating: managed.filter(\.isFloating).count,
                      screens: isStarted ? screens.map { ($0.uuid, $0.ns.localizedName, state(for: $0).layout,
                                                           isVirtual(shown[$0.uuid]) ? (shown[$0.uuid] ?? "") : "") } : [])
    }

    func setLayout(_ l: Layout, screen uuid: String) {
        guard let s = Screen.all().first(where: { $0.uuid == uuid }) else { return }
        let st = state(for: s)
        st.layout = l
        st.zoomed = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { HUD.shared.show(l.title, layout: l, on: s.ns) }
    }

    func ipc(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 2).map(String.init)
        Log.info("ipc: \(command)")
        switch parts.first {
        case "dispatch" where parts.count >= 2:
            // exec is refused here: any process, sandboxed or not, can post this notification.
            guard parts[1].lowercased() != "exec" else { Log.info("ipc: exec is only allowed from keybinds"); return }
            dispatch(parts[1].lowercased(), parts.count > 2 ? parts[2] : "")
        case "dump": dumpState()
        case "grabtest": grabTest()
        case "poststyle" where parts.count >= 2:
            // Diagnostics: `ouch poststyle 0|1|2` picks how synthetic shortcuts are sent.
            if let n = Int(parts[1]), let style = Hotkeys.PostStyle(rawValue: n) { Hotkeys.postStyle = style }
            Log.info("ipc: post style is now \(Hotkeys.postStyle)")
        case "reload": reload()
        case "modefx": ModeFX.shared.command(Array(parts.dropFirst()).flatMap { $0.split(separator: " ").map(String.init) })
        case "panelfx": PanelMotionDemo.command(Array(parts.dropFirst()))
        case "introlab": IntroLab.shared.open()
        case "intro": Onboarding.shared.playIntro(parts.dropFirst().first.flatMap { IntroScore.Arrangement.named($0) } ?? .standard)
        default: Log.info("ipc: unknown command")
        }
    }

    private func dumpState() {
        var lines = ["state: trusted=\(Permission.accessibility.isGranted) keybinds=\(Hotkeys.shared.isActive) tiling=\(tilingEnabled) focused=\(focusedWindow()?.id ?? 0)"]
        for s in Screen.all() {
            let st = state(for: s)
            lines.append("  screen \(s.ns.localizedName) workspace=\(shown[s.uuid] ?? "?") home=\(isOnHomeSpace(s)) layout=\(st.layout.rawValue) ratio=\(st.ratio) main=\(st.mainCount) usable=\(usableRect(s))")
            for id in tiled(on: s) {
                let w = windows[id]!
                let ok = targets[id].map { w.frame.approxEqual($0, tolerance: 2) } ?? false
                lines.append("    tiled \(id) \(w.bundleID ?? "pid \(w.pid)") target=\(targets[id] ?? .null) actual=\(w.frame) \(ok ? "OK" : "MISMATCH")")
            }
        }
        for id in visible where windows[id]?.isFloating == true {
            lines.append("  floating \(id) \(windows[id]!.bundleID ?? "") \(windows[id]!.frame)")
        }
        for (id, ws) in workspaceOf.sorted(by: { $0.value < $1.value }) where present.contains(id) && !visible.contains(id) {
            lines.append("  parked \(id) \(windows[id]?.bundleID ?? "") workspace=\(ws) frame=\(windows[id]?.frame ?? .null)")
        }
        lines.forEach { Log.info($0) }
    }

    // MARK: - Commands

    func swapOrder(_ a: CGWindowID, _ b: CGWindowID) {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return }
        order.swapAt(i, j)
        (workspaceOf[a], workspaceOf[b]) = (workspaceOf[b], workspaceOf[a])
    }

    func dispatch(_ dispatcher: String, _ rawArg: String) {
        let arg = rawArg.trimmingCharacters(in: .whitespaces)
        let inMode = !Hotkeys.shared.submap.isEmpty
        defer { onDispatch?(dispatcher, arg, inMode) }
        switch dispatcher {
        case "movefocus": if let d = Direction(arg) { moveFocus(d) }
        case "movewindow":
            if arg.lowercased().hasPrefix("mon:") { moveToMonitor(String(arg.dropFirst(4))) }
            else if let d = Direction(arg) { moveWindow(d) }
        case "swapwindow": if let d = Direction(arg) { moveWindow(d) }
        case "cyclenext": cycleFocus(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "swapnext": cycleSwap(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "layoutmsg": layoutMessage(arg)
        case "splitratio": adjustRatio(arg)
        case "togglefloating": toggleFloating()
        case "fullscreen": toggleZoom()
        case "nativefullscreen": toggleNativeFullscreen()
        case "killactive": lastClose = Date(); focusedWindow()?.close()
        case "minimize": focusedWindow()?.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
        case "exec": exec(arg)
        case "focusmonitor": focusMonitor(arg)
        case "movewindowtomonitor": moveToMonitor(arg)
        case "workspace":
            if config.virtualWorkspaces { if let ws = resolveWorkspace(arg) { showWorkspace(ws) } }
            else if let n = Int(arg) { switchSpace(n) }
        case "movetoworkspace", "movetoworkspacesilent":
            if config.virtualWorkspaces {
                if let ws = resolveWorkspace(arg) { moveFocusedWindow(to: ws, follow: dispatcher == "movetoworkspace") }
            } else if let n = Int(arg) { moveToSpace(n) }
        case "cyclelayout": cycleLayout(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "layout", "setlayout": if let l = Layout(rawValue: arg.lowercased()) { setLayout(l) }
        case "toggletiling": toggleTiling()
        case "toggledim": FocusDim.shared.toggleDim()
        case "toggleblur": FocusDim.shared.toggleBlur()
        case "submap": Hotkeys.shared.setSubmap(arg)
        case "sethomespace": makeCurrentSpaceHome()
        case "sort":
            if config.virtualWorkspaces { SortPanel.shared.toggle() }
            else { HUD.shared.show("Sorting needs Ouch workspaces", on: currentScreen()?.ns) }
        case "sort-undo": SortPanel.shared.undoApplied()
        case "retile", "reevaluate": corrections = [:]; refresh()
        case "reload": reload()
        case "exit": NSApp.terminate(nil)
        default: NSLog("Ouch: unknown dispatcher %@", dispatcher)
        }
    }

    private func layoutMessage(_ arg: String) {
        let parts = arg.split(separator: " ").map(String.init)
        guard let cmd = parts.first?.lowercased() else { return }
        switch cmd {
        case "swapwithmaster": swapWithMain()
        case "focusmaster": focusMain()
        case "addmaster": changeMainCount(1)
        case "removemaster": changeMainCount(-1)
        case "cyclenext": cycleFocus(1)
        case "cycleprev": cycleFocus(-1)
        case "swapnext": cycleSwap(1)
        case "swapprev": cycleSwap(-1)
        case "mfact": adjustRatio(parts.dropFirst().joined(separator: " "))
        case "orientationnext": cycleLayout(1)
        case "orientationprev": cycleLayout(-1)
        default: NSLog("Ouch: unknown layoutmsg %@", cmd)
        }
    }

    /// Windows on the focused screen in tiling order, plus the focused window and its screen.
    private func context() -> (w: Window?, s: Screen, st: ScreenState, ids: [CGWindowID])? {
        guard let s = currentScreen() else { return nil }
        return (focusedWindow(), s, state(for: s), tiled(on: s))
    }

    private func moveFocus(_ d: Direction) {
        guard let w = focusedWindow() else {
            if let c = context(), let first = c.ids.first.flatMap({ windows[$0] }) { focus(first) }
            return
        }
        let candidates = order.filter(visible.contains).compactMap { windows[$0] } // tiling order breaks ties
        let screens = Screen.all()
        let home = screen(of: w, in: screens)
        // A zoomed window covers everything else: there's no geometry to navigate, so cycle.
        if let home, state(for: home).zoomed == w.id { cycleFocus(d == .left || d == .up ? -1 : 1); return }
        if let n = neighbor(of: w, d, among: candidates) { focus(n); return }
        let f = navFrame(w)
        let here = candidates.filter { $0.id != w.id && screen(of: $0, in: screens)?.uuid == home?.uuid }
        // At the end of a row or column: wrap round to the far end of it.
        let behind = here.compactMap { o -> (Window, CGFloat)? in
            let r = relation(f, navFrame(o), d)
            return r.overlaps && r.along < -1 ? (o, -r.along) : nil
        }
        if let far = behind.map(\.1).max() {
            let ends = behind.filter { $0.1 >= far - 2 }.map(\.0)
            if let pick = ends.max(by: { (focusStamps[$0.id] ?? 0) < (focusStamps[$1.id] ?? 0) }) { focus(pick) }
            return
        }
        // Windows stacked in the same slot (fullscreen layout, a two-pane stack): cycle through them.
        let hereIDs = Set(here.map(\.id))
        let stack = candidates.filter { $0.id == w.id || (hereIDs.contains($0.id) && navFrame($0).approxEqual(f, tolerance: 2)) }
        guard stack.count > 1, let i = stack.firstIndex(where: { $0.id == w.id }) else { return }
        let delta = d == .left || d == .up ? -1 : 1
        focus(stack[((i + delta) % stack.count + stack.count) % stack.count])
    }

    private func moveWindow(_ d: Direction) {
        guard let w = focusedWindow(), !w.isFloating else { return }
        let candidates = order.filter(visible.contains).compactMap { windows[$0] }.filter { !$0.isFloating }
        if let n = neighbor(of: w, d, among: candidates) {
            if let a = screen(of: w), let b = screen(of: n), a.uuid != b.uuid {
                workspaceOf[w.id] = shown[b.uuid] // across monitors Hyprland moves without swapping
            } else {
                swapOrder(w.id, n.id)
            }
        } else if let src = screen(of: w), let dst = screen(from: src, spec: arg(d), in: Screen.all()) {
            workspaceOf[w.id] = shown[dst.uuid] // nothing that way on this screen: hop to the next monitor
        } else { return }
        refresh()
        focus(w)
    }

    private func arg(_ d: Direction) -> String {
        switch d { case .left: "l"; case .right: "r"; case .up: "u"; case .down: "d" }
    }

    private func cycleFocus(_ delta: Int) {
        guard let c = context(), !c.ids.isEmpty else { return }
        let i = c.w.flatMap { c.ids.firstIndex(of: $0.id) } ?? (delta > 0 ? -1 : 0)
        let next = c.ids[((i + delta) % c.ids.count + c.ids.count) % c.ids.count]
        if let w = windows[next] { focus(w) }
    }

    private func cycleSwap(_ delta: Int) {
        guard let c = context(), let w = c.w, let i = c.ids.firstIndex(of: w.id), c.ids.count > 1 else { return }
        swapOrder(w.id, c.ids[((i + delta) % c.ids.count + c.ids.count) % c.ids.count])
        refresh()
    }

    private func swapWithMain() {
        guard let c = context(), let w = c.w, c.ids.count > 1, c.ids.contains(w.id) else { return }
        swapOrder(w.id, c.ids[0] == w.id ? c.ids[1] : c.ids[0])
        refresh()
        focus(w)
    }

    private func focusMain() {
        guard let c = context(), let id = c.ids.first, let w = windows[id] else { return }
        focus(w)
    }

    private func changeMainCount(_ delta: Int) {
        guard let c = context() else { return }
        c.st.mainCount = max(1, min(10, c.st.mainCount + delta))
        refresh()
    }

    /// "+0.05", "-0.05", "0.05" (relative) or "exact 0.6".
    private func adjustRatio(_ arg: String) {
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
        // A window we already know won't shrink: say so and keep the ratio, so the presses that
        // did nothing don't have to be undone before the other direction works again.
        if let stubborn = windowRefusingRatio(ratio, from: c.st.ratio, ids: c.ids, on: c.s, c.st) {
            warnTooSmall(stubborn, on: c.s)
            return
        }
        c.st.ratio = ratio
        // Otherwise a window may only turn out to have a minimum once it's been asked to shrink.
        ratioChange = (c.s.uuid, Date() + (config.animate ? config.animationDuration : 0) + 0.6)
        refresh()
    }

    private func toggleFloating() {
        guard let w = focusedWindow() else { return }
        w.userFloating = !w.isFloating
        if w.isFloating {
            targets[w.id] = nil
        } else {
            if let s = screen(containing: w.frame) { workspaceOf[w.id] = shown[s.uuid] }
            corrections[w.id] = nil
        }
        refresh()
    }

    /// Hyprland's `fullscreen`: the window covers the whole tiling area until toggled again.
    private func toggleZoom() {
        guard let c = context(), let w = c.w, c.ids.contains(w.id) else { return }
        c.st.zoomed = c.st.zoomed == w.id ? nil : w.id
        refresh()
        w.focus()
    }

    /// macOS's own Full Screen, as the green button does it: the window gets a Space of its own and leaves the
    /// tiling until it comes back. A window already in Full Screen is not tiled, so ask macOS which one is
    /// focused rather than relying on `windows`.
    private func toggleNativeFullscreen() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el = focusedWindow()?.element
                ?? axApp(app.processIdentifier).element(kAXFocusedWindowAttribute) else { return }
        let on = el.bool("AXFullScreen") ?? false
        let done: Bool
        if el.isSettable("AXFullScreen") {
            done = el.set("AXFullScreen", on ? kCFBooleanFalse : kCFBooleanTrue)
        } else if let button = el.element("AXFullScreenButton") ?? el.element(kAXZoomButtonAttribute) {
            // Apps that don't expose the attribute still have the button; pressing it enters or leaves Full Screen.
            done = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        } else {
            done = false
        }
        Log.info("native fullscreen \(on ? "off" : "on") for \(el.windowID.map(String.init) ?? "?") \(app.bundleIdentifier ?? ""): \(done ? "ok" : "refused")")
        guard done else { return }
        if let id = el.windowID, !on { for s in Screen.all() where state(for: s).zoomed == id { state(for: s).zoomed = nil } }
        // The Full Screen transition takes a moment; the other tiles close the gap (or make room) once it's over.
        scheduleRefresh(after: 0.8)
    }

    private func cycleLayout(_ delta: Int) {
        guard let c = context(), !config.layouts.isEmpty else { return }
        let i = config.layouts.firstIndex(of: c.st.layout) ?? (delta > 0 ? -1 : 0)
        setLayout(config.layouts[((i + delta) % config.layouts.count + config.layouts.count) % config.layouts.count])
    }

    private func setLayout(_ l: Layout) {
        guard let c = context() else { return }
        c.st.layout = l
        c.st.zoomed = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { HUD.shared.show(l.title, layout: l, on: c.s.ns) }
    }

    private func exec(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
    }

    private func focusMonitor(_ spec: String) {
        let screens = Screen.all()
        guard let src = currentScreen(), let dst = screen(from: src, spec: spec, in: screens) else { return }
        // Prefer the topmost managed window on that screen, else its main window.
        let p = CGWindowInfo.onScreen().first { info in
            guard visible.contains(info.id), let w = windows[info.id] else { return false }
            return screen(of: w, in: screens)?.uuid == dst.uuid
        }
        if let id = p?.id ?? tiled(on: dst).first, let w = windows[id] {
            focus(w)
        } else {
            CGWarpMouseCursorPosition(dst.center)
            CursorRefresh.soon()
        }
    }

    private func moveToMonitor(_ spec: String) {
        let screens = Screen.all()
        guard let w = focusedWindow(), let src = screen(of: w, in: screens),
              let dst = screen(from: src, spec: spec, in: screens), dst.uuid != src.uuid else { return }
        if w.isFloating {
            let f = w.frame
            var o = CGPoint(x: dst.visible.minX + (f.minX - src.visible.minX), y: dst.visible.minY + (f.minY - src.visible.minY))
            o.x = max(dst.visible.minX, min(o.x, dst.visible.maxX - f.width))
            o.y = max(dst.visible.minY, min(o.y, dst.visible.maxY - f.height))
            animator.animate([.init(window: w, to: CGRect(origin: o, size: f.size), bounds: dst.visible)],
                             duration: config.animate ? config.animationDuration : 0,
                             curve: config.animationCurve, bounce: config.animationBounce)
            workspaceOf[w.id] = shown[dst.uuid]
            scheduleRefresh()
        } else {
            workspaceOf[w.id] = shown[dst.uuid]
            refresh()
        }
        focus(w)
    }
}
