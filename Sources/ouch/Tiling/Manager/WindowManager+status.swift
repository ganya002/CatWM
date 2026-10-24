import AppKit

extension WindowManager {
    func status() -> Status {
        let screens = Screen.all()
        let managed = visible.compactMap { windows[$0] }
        return Status(trusted: Permission.accessibility.isGranted, keybindsActive: Hotkeys.shared.isActive,
                      running: isStarted,
                      tilingEnabled: tilingEnabled,
                      launchAtLogin: LoginItem.isEnabled, loginNeedsApproval: LoginItem.needsApproval,
                      inputMonitoring: Permission.inputMonitoring.isGranted,
                      tiled: managed.filter { !$0.isFloating }.count, floating: managed.filter(\.isFloating).count,
                      screens: isStarted ? screens.map { screen in
                          ScreenStatus(uuid: screen.uuid, name: screen.nsScreen.localizedName,
                                       layout: state(for: screen).layout,
                                       workspace: isVirtual(shown[screen.uuid]) ? (shown[screen.uuid] ?? "") : "")
                      } : [])
    }

    func setLayout(_ layout: Layout, screen uuid: String) {
        guard let screen = Screen.all().first(where: { $0.uuid == uuid }) else { return }
        setLayout(layout, on: screen)
    }

    func setLayout(_ layout: Layout, on screen: Screen) {
        let screenState = state(for: screen)
        tilingRecovery.zoomed[workspaceKey(for: screen)] = nil
        screenState.layout = layout
        screenState.zoomed = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { HUD.shared.show(layout.title, layout: layout, on: screen.nsScreen) }
    }

    func ipc(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 2).map(String.init)
        Log.info("ipc: \(command)")
        switch parts.first {
        case "dispatch" where parts.count >= 2:
            guard !["exec", "launch"].contains(parts[1].lowercased()) else {
                Log.info("ipc: \(parts[1].lowercased()) is only allowed from keybinds")
                return
            }
            dispatch(parts[1].lowercased(), parts.count > 2 ? parts[2] : "")
        case "dump": dumpState()
        case "grabtest": grabTest()
        case "poststyle" where parts.count >= 2:
            if let raw = Int(parts[1]), let style = Hotkeys.PostStyle(rawValue: raw) { Hotkeys.postStyle = style }
            Log.info("ipc: post style is now \(Hotkeys.postStyle)")
        case "reload": reload()
        case "modefx":
            ModeFX.shared.command(Array(parts.dropFirst()).flatMap { $0.split(separator: " ").map(String.init) })
        case "panelfx": PanelMotionDemo.command(Array(parts.dropFirst()))
        case "introlab": IntroLab.shared.open()
        case "intro":
            Onboarding.shared.playIntro(
                parts.dropFirst().first.flatMap { IntroScore.Arrangement.named($0) } ?? .standard
            )
        default: Log.info("ipc: unknown command")
        }
    }

    func dumpState() {
        var lines = [
            "state: trusted=\(Permission.accessibility.isGranted) keybinds=\(Hotkeys.shared.isActive) "
                + "tiling=\(tilingEnabled) focused=\(focusedWindow()?.id ?? 0)"
        ]
        for screen in Screen.all() {
            let screenState = state(for: screen)
            lines.append(
                "  screen \(screen.nsScreen.localizedName) workspace=\(shown[screen.uuid] ?? "?") "
                    + "home=\(isOnHomeSpace(screen)) layout=\(screenState.layout.rawValue) "
                    + "ratio=\(screenState.ratio) main=\(screenState.mainCount) usable=\(usableRect(screen))"
            )
            for id in tiled(on: screen) {
                guard let window = windows[id] else { continue }
                let matches = targets[id].map { window.frame.approxEqual($0, tolerance: 2) } ?? false
                lines.append(
                    "    tiled \(id) \(window.bundleID ?? "pid \(window.pid)") target=\(targets[id] ?? .null) "
                        + "actual=\(window.frame) \(matches ? "OK" : "MISMATCH")"
                )
            }
        }
        for group in tabs.groups {
            let members = group.members.map { $0 == group.active ? "[\($0)]" : "\($0)" }
            lines.append("  tabs \(members.joined(separator: " "))")
        }
        for id in visible {
            guard let window = windows[id], window.isFloating else { continue }
            lines.append("  floating \(id) \(window.bundleID ?? "") \(window.frame)")
        }
        let parked = workspaceOf.sorted(by: { $0.value < $1.value })
        for (id, workspace) in parked where present.contains(id) && !visible.contains(id) {
            lines.append(
                "  parked \(id) \(windows[id]?.bundleID ?? "") workspace=\(workspace) "
                    + "frame=\(windows[id]?.frame ?? .null)"
            )
        }
        lines.forEach { Log.info($0) }
    }

    func swapOrder(_ first: CGWindowID, _ second: CGWindowID) {
        guard let i = order.firstIndex(of: first), let j = order.firstIndex(of: second) else { return }
        order.swapAt(i, j)
        let firstWorkspace = workspaceOf[first], secondWorkspace = workspaceOf[second]
        model.swapWorkspaces(first, second)
        if config.virtualWorkspaces, firstWorkspace != secondWorkspace {
            if let name = secondWorkspace, let window = windows[first] {
                moveNativeWindow(window, to: name, follow: false, from: firstWorkspace)
            }
            if let name = firstWorkspace, let window = windows[second] {
                moveNativeWindow(window, to: name, follow: false, from: secondWorkspace)
            }
        }
    }

    func dispatch(_ dispatcher: String, _ rawArg: String, inMode: Bool = !Hotkeys.shared.submap.isEmpty) {
        let arg = rawArg.trimmingCharacters(in: .whitespaces)
        if deferFocusCommand(dispatcher, arg: arg, inMode: inMode) { return }
        let timing = TilingTiming("command \(dispatcher)", windows: windows.count)
        defer { timing.finish() }
        defer { onDispatch?(dispatcher, arg, inMode) }
        if let feature = FocusDim.features.first(where: { $0.pointer.dispatcher == dispatcher }) {
            feature.run()
            return
        }
        switch dispatcher {
        case "movefocus": if let direction = Direction(arg) { moveFocus(direction) }
        case "movewindow": moveWindowCommand(arg)
        case "swapwindow": if let direction = Direction(arg) { moveWindow(direction) }
        case "cyclenext": cycleFocus(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "swapnext": cycleSwap(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "layoutmsg": layoutMessage(arg)
        case "splitratio": adjustRatio(arg)
        case "togglefloating": toggleFloating()
        case "fullscreen": toggleZoom()
        case "nativefullscreen": toggleNativeFullscreen()
        case "killactive": lastClose = Date(); _ = focusedWindow().map { closeWindow($0.id) }
        case "minimize": if let window = focusedWindow() { minimize(window) }
        case "exec": exec(arg)
        case "launch": launchCommand(arg)
        case "focusmonitor": focusMonitor(arg)
        case "movewindowtomonitor": moveToMonitor(arg)
        case "workspace": showWorkspaceCommand(arg)
        case "movetoworkspace", "movetoworkspacesilent":
            moveToWorkspaceCommand(arg, follow: dispatcher == "movetoworkspace")
        case "cyclelayout": cycleLayout(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "layout", "setlayout": setLayoutCommand(arg)
        case "toggletiling": toggleTiling()
        case "retile", "reevaluate": corrections = [:]; refresh()
        case "reload": reload()
        case "exit": NSApp.terminate(nil)
        case "submap": Hotkeys.shared.setSubmap(arg)
        case "sethomespace": makeCurrentSpaceHome()
        case "sort": toggleSortCommand()
        case "sort-undo": SortPanel.shared.undoApplied()
        case "switcher": Switcher.shared.open(backward: arg.lowercased().hasPrefix("prev"))
        case "moveintogroup", "moveoutofgroup", "changegroupactive", "movegroupwindow": tabCommand(dispatcher, arg)
        default: NSLog("Ouch: unknown dispatcher %@", dispatcher)
        }
    }

    private func moveWindowCommand(_ arg: String) {
        if arg.lowercased().hasPrefix("mon:") {
            moveToMonitor(String(arg.dropFirst(4)))
        } else if let direction = Direction(arg) {
            moveWindow(direction)
        }
    }

    private func setLayoutCommand(_ arg: String) {
        if let layout = Layout(rawValue: arg.lowercased()), let screen = currentScreen() {
            setLayout(layout, on: screen)
        }
    }

    private func toggleSortCommand() {
        if config.virtualWorkspaces {
            SortPanel.shared.toggle()
        } else {
            HUD.shared.show("Overview needs CatWM workspaces", on: currentScreen()?.nsScreen)
        }
    }

    private func showWorkspaceCommand(_ arg: String) {
        if config.virtualWorkspaces {
            if let workspace = resolveWorkspace(arg) { showWorkspace(workspace) }
        } else if let number = Int(arg) {
            switchSpace(number)
        }
    }

    private func moveToWorkspaceCommand(_ arg: String, follow: Bool) {
        if config.virtualWorkspaces {
            if let workspace = resolveWorkspace(arg) { moveFocusedWindow(to: workspace, follow: follow) }
        } else if let number = Int(arg) {
            moveToSpace(number)
        }
    }

    func layoutMessage(_ arg: String) {
        let parts = arg.split(separator: " ").map(String.init)
        guard let cmd = parts.first?.lowercased() else { return }
        switch cmd {
        case "swapwithmaster": swapWithMain()
        case "swapsides": swapSides()
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
