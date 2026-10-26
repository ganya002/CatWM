import AppKit

extension WindowManager {
    func status() -> Status {
        let screens = backend.screens()
        let managed = visible.compactMap { windows[$0] }
        return Status(trusted: Permission.accessibility.isGranted, keybindsActive: surface.keybindsActive,
                      running: isStarted,
                      tilingEnabled: tilingEnabled,
                      launchAtLogin: LoginItem.shared.isEnabled, loginNeedsApproval: LoginItem.shared.needsApproval,
                      inputMonitoring: Permission.inputMonitoring.isGranted,
                      tiled: managed.filter { !$0.isFloating }.count, floating: managed.filter(\.isFloating).count,
                      screens: isStarted ? screens.map { screen in
                          ScreenStatus(uuid: screen.uuid, name: screen.name,
                                       workspace: isVirtual(shown[screen.uuid]) ? (shown[screen.uuid] ?? "") : "")
                      } : [])
    }

    func dumpLines() -> [String] {
        var lines = [
            "state: trusted=\(Permission.accessibility.isGranted) keybinds=\(surface.keybindsActive) "
                + "tiling=\(tilingEnabled) focused=\(focusedWindow()?.id ?? 0)"
        ]
        let screens = backend.screens()
        for screen in screens {
            let screenState = state(for: screen)
            lines.append(
                "  screen \(screen.name) workspace=\(shown[screen.uuid] ?? "?") "
                    + "home=\(isOnHomeSpace(screen)) columns=\(stripLine(screenState)) "
                    + "offset=\(screenState.strip.offset) usable=\(usableRect(screen))"
            )
            for id in tiled(on: screen) {
                guard let window = windows[id] else { continue }
                let matches = targets[id].map {
                    window.frame.approxEqual($0, tolerance: 2)
                        || isParked($0, screens) && isParked(window.frame, screens)
                } ?? false
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
        if let firstWorkspace, firstWorkspace == secondWorkspace { states[firstWorkspace]?.strip.swap(first, second) }
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
        if let refusal = scopeRefusal(dispatcher) {
            Log.info(refusal)
            return
        }
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
}

extension WindowManager {
    struct ScreenStatus: Equatable {
        var uuid: String
        var name: String
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
