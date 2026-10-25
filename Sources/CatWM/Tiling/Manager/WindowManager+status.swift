import AppKit

extension WindowManager {
    func status() -> Status {
        let screens = Screen.all()
        let managed = visible.compactMap { windows[$0] }
        return Status(trusted: Permission.accessibility.isGranted, keybindsActive: surface.keybindsActive,
                      running: isStarted,
                      tilingEnabled: tilingEnabled,
                      launchAtLogin: LoginItem.shared.isEnabled, loginNeedsApproval: LoginItem.shared.needsApproval,
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
        if config.enablesLayoutHUD { surface.showHUD(layout.title, layout: layout, on: screen.nsScreen) }
    }

    func dumpLines() -> [String] {
        var lines = [
            "state: trusted=\(Permission.accessibility.isGranted) keybinds=\(surface.keybindsActive) "
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
        return lines
    }

    func dumpState() {
        dumpLines().forEach { Log.info($0) }
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

    func dispatch(_ dispatcher: String, _ rawArg: String) {
        dispatch(dispatcher, rawArg, inMode: surface.inMode)
    }

    func dispatch(_ dispatcher: String, _ rawArg: String, inMode: Bool) {
        let arg = rawArg.trimmingCharacters(in: .whitespaces)
        if deferFocusCommand(dispatcher, arg: arg, inMode: inMode) { return }
        let timing = TilingTiming("command \(dispatcher)", windows: windows.count)
        defer { timing.finish() }
        defer { onDispatch?(dispatcher, arg, inMode) }
        if let feature = FocusDim.features.first(where: { $0.pointer.dispatcher == dispatcher }) {
            feature.run()
            return
        }
        guard let action = WindowActions.named(dispatcher) else {
            Log.info("unknown dispatcher \(dispatcher)")
            return
        }
        action.run(ActionContext(manager: self, arg: arg))
    }

    func moveWindowCommand(_ arg: String) {
        if arg.lowercased().hasPrefix("mon:") {
            moveToMonitor(String(arg.dropFirst(4)))
        } else if let direction = Direction(arg) {
            moveWindow(direction)
        }
    }

    func setLayoutCommand(_ arg: String) {
        if let layout = Layout(rawValue: arg.lowercased()), let screen = currentScreen() {
            setLayout(layout, on: screen)
        }
    }

    func showWorkspaceCommand(_ arg: String) {
        if config.virtualWorkspaces {
            if let workspace = resolveWorkspace(arg) { showWorkspace(workspace) }
        } else if let number = Int(arg) {
            switchSpace(number)
        }
    }

    func moveToWorkspaceCommand(_ arg: String, follow: Bool) {
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
        default: Log.info("unknown layoutmsg \(cmd)")
        }
    }
}

extension WindowManager {
    struct ScreenStatus: Equatable {
        var uuid: String
        var name: String
        var layout: Layout
        var workspace: String
    }

    struct Status: Equatable {
        var trusted: Bool
        var keybindsActive: Bool
        var running: Bool
        var tilingEnabled: Bool
        var launchAtLogin: Bool
        var loginNeedsApproval: Bool
        var inputMonitoring: Bool
        var tiled: Int
        var floating: Int
        var screens: [ScreenStatus]
    }
}
