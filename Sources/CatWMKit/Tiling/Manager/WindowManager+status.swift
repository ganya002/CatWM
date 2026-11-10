import AppKit

extension WindowManager {
    package func status() -> Status {
        let screens = backend.screens()
        let managed = visible.compactMap { windows[$0] }
        return Status(trusted: Permission.accessibility.isGranted, keybindsActive: surface.keybindsActive,
                      running: isStarted,
                      tilingEnabled: tilingEnabled,
                      launchAtLogin: surface.loginItem.enabled, loginNeedsApproval: surface.loginItem.needsApproval,
                      inputMonitoring: Permission.inputMonitoring.isGranted,
                      tiled: managed.filter { !$0.isFloating }.count, floating: managed.filter(\.isFloating).count,
                      screens: isStarted ? screens.map { screen in
                          ScreenStatus(uuid: screen.uuid, name: screen.name,
                                       layout: state(for: screen).layout,
                                       workspace: isVirtual(shown[screen.uuid]) ? (shown[screen.uuid] ?? "") : "")
                      } : [])
    }

    package func setLayout(_ layout: Layout, screen uuid: String) {
        guard let screen = backend.screens().first(where: { $0.uuid == uuid }) else { return }
        setLayout(layout, on: screen)
    }

    package func setLayout(_ layout: Layout, on screen: Screen) {
        let screenState = state(for: screen)
        tilingRecovery.zoomed[workspaceKey(for: screen)] = nil
        screenState.layout = layout
        screenState.zoomed = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { surface.showHUD(layout.title, layout: layout, on: screen.nsScreen) }
    }

    package func dumpLines() -> [String] {
        var lines = [
            "state: trusted=\(Permission.accessibility.isGranted) keybinds=\(surface.keybindsActive) "
                + "tiling=\(tilingEnabled) focused=\(focusedWindow()?.id ?? 0)"
        ]
        for screen in backend.screens() {
            let screenState = state(for: screen)
            lines.append(
                "  screen \(screen.name) workspace=\(shown[screen.uuid] ?? "?") "
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

    package func dumpState() {
        dumpLines().forEach { Log.info($0) }
    }

    package func swapOrder(_ first: CGWindowID, _ second: CGWindowID) {
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

    package func dispatch(_ dispatcher: String, _ rawArg: String) {
        dispatch(dispatcher, rawArg, inMode: surface.inMode)
    }

    package func dispatch(_ dispatcher: String, _ rawArg: String, inMode: Bool) {
        if let refusal = scopeRefusal(dispatcher) {
            Log.info(refusal)
            return
        }
        let arg = rawArg.trimmingCharacters(in: .whitespaces)
        if deferFocusCommand(dispatcher, arg: arg, inMode: inMode) { return }
        let timing = TilingTiming("command \(dispatcher)", windows: windows.count)
        defer { timing.finish() }
        defer { onDispatch?(dispatcher, arg, inMode) }
        if let effect = FocusEffect.all.first(where: { $0.dispatcher == dispatcher }) {
            surface.toggleFocusEffect(effect)
            return
        }
        guard let action = WindowActions.named(dispatcher) else {
            Log.info("unknown dispatcher \(dispatcher)")
            return
        }
        action.run(ActionContext(manager: self, arg: arg))
    }

    package func moveWindowCommand(_ arg: String) {
        if arg.lowercased().hasPrefix("mon:") {
            moveToMonitor(String(arg.dropFirst(4)))
        } else if let direction = Direction(arg) {
            moveWindow(direction)
        }
    }

    package func setLayoutCommand(_ arg: String) {
        if let layout = Layout(rawValue: arg.lowercased()), let screen = currentScreen() {
            setLayout(layout, on: screen)
        }
    }

    package func showWorkspaceCommand(_ arg: String) {
        if config.virtualWorkspaces {
            if let workspace = resolveWorkspace(arg) { showWorkspace(workspace) }
        } else if let number = Int(arg) {
            switchSpace(number)
        }
    }

    package func moveToWorkspaceCommand(_ arg: String, follow: Bool) {
        if config.virtualWorkspaces {
            if let workspace = resolveWorkspace(arg) { moveFocusedWindow(to: workspace, follow: follow) }
        } else if let number = Int(arg) {
            moveToSpace(number)
        }
    }

    package func layoutMessage(_ arg: String) {
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
    package struct ScreenStatus: Equatable {
        package var uuid: String
        package var name: String
        package var layout: Layout
        package var workspace: String
    }

    package struct Status: Equatable {
        package var trusted: Bool
        package var keybindsActive: Bool
        package var running: Bool
        package var tilingEnabled: Bool
        package var launchAtLogin: Bool
        package var loginNeedsApproval: Bool
        package var inputMonitoring: Bool
        package var tiled: Int
        package var floating: Int
        package var screens: [ScreenStatus]
    }
}
