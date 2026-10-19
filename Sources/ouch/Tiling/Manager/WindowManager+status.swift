import AppKit

extension WindowManager {
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
        setLayout(l, on: s)
    }

    func setLayout(_ l: Layout, on s: Screen) {
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
            guard parts[1].lowercased() != "exec" else { Log.info("ipc: exec is only allowed from keybinds"); return }
            dispatch(parts[1].lowercased(), parts.count > 2 ? parts[2] : "")
        case "dump": dumpState()
        case "grabtest": grabTest()
        case "poststyle" where parts.count >= 2:
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

    func dumpState() {
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

    func swapOrder(_ a: CGWindowID, _ b: CGWindowID) {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return }
        order.swapAt(i, j)
        model.swapWorkspaces(a, b)
    }

    func dispatch(_ dispatcher: String, _ rawArg: String, inMode originalMode: Bool? = nil) {
        let arg = rawArg.trimmingCharacters(in: .whitespaces)
        let inMode = originalMode ?? !Hotkeys.shared.submap.isEmpty
        if deferFocusCommand(dispatcher, arg: arg, inMode: inMode) { return }
        let timing = TilingTiming("command \(dispatcher)", windows: windows.count)
        defer { timing.finish() }
        defer { onDispatch?(dispatcher, arg, inMode) }
        if let feature = FocusDim.features.first(where: { $0.pointer.dispatcher == dispatcher }) {
            feature.run()
            return
        }
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
        case "layout", "setlayout": if let l = Layout(rawValue: arg.lowercased()), let s = currentScreen() { setLayout(l, on: s) }
        case "toggletiling": toggleTiling()
        case "retile", "reevaluate": corrections = [:]; refresh()
        case "reload": reload()
        case "exit": NSApp.terminate(nil)
        case "submap": Hotkeys.shared.setSubmap(arg)
        case "sethomespace": makeCurrentSpaceHome()
        case "sort":
            if config.virtualWorkspaces { SortPanel.shared.toggle() }
            else { HUD.shared.show("Overview needs Ouch workspaces", on: currentScreen()?.ns) }
        case "sort-undo": SortPanel.shared.undoApplied()
        default: NSLog("Ouch: unknown dispatcher %@", dispatcher)
        }
    }

    func layoutMessage(_ arg: String) {
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

}
