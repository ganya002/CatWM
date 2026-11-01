import AppKit

extension WindowManager {
    func statusJSON() -> JSON {
        let current = status()
        return [
            "trusted": .bool(current.trusted), "keybindsActive": .bool(current.keybindsActive),
            "running": .bool(current.running), "tilingEnabled": .bool(current.tilingEnabled),
            "launchAtLogin": .bool(current.launchAtLogin), "loginNeedsApproval": .bool(current.loginNeedsApproval),
            "inputMonitoring": .bool(current.inputMonitoring), "tiled": .int(current.tiled),
            "floating": .int(current.floating), "mode": .string(Hotkeys.shared.submap),
            "workspaces": .string(config.virtualWorkspaces ? "catwm" : "macos"),
            "screens": .array(current.screens.map {
                ["uuid": .string($0.uuid), "name": .string($0.name), "layout": .string($0.layout.rawValue),
                 "workspace": .string($0.workspace)]
            })
        ]
    }

    func windowsJSON() -> JSON {
        let focused = focusedWindow()?.id
        let screens = backend.screens()
        let ranked = order.enumerated().reduce(into: [CGWindowID: Int]()) { $0[$1.element] = $1.offset }
        let known = windows.values.sorted { (ranked[$0.id] ?? .max, $0.id) < (ranked[$1.id] ?? .max, $1.id) }
        return .array(known.map { window in
            [
                "id": .int(Int(window.id)), "pid": .int(Int(window.pid)),
                "app": window.bundleID.map(JSON.string) ?? .null,
                "title": window.title.map(JSON.string) ?? .null,
                "focused": .bool(window.id == focused), "floating": .bool(window.isFloating),
                "minimized": .bool(window.minimized), "fullscreen": .bool(window.fullscreen),
                "visible": .bool(visible.contains(window.id)),
                "workspace": workspaceOf[window.id].map(JSON.string) ?? .null,
                "screen": screen(of: window, in: screens).map { JSON.string($0.uuid) } ?? .null,
                "frame": .rect(window.cachedFrame)
            ]
        })
    }

    func workspacesJSON() -> JSON {
        var members: [String: [CGWindowID]] = [:]
        for id in order where windows[id] != nil {
            if let name = workspaceOf[id] { members[name, default: []].append(id) }
        }
        let names = Set(members.keys).union(shown.values)
            .union(desktops.nativeCatalog.entries.map(\.name)).sorted(by: workspaceSort)
        return .array(names.map { name in
            [
                "name": .string(name), "windows": .array((members[name] ?? []).map { .int(Int($0)) }),
                "screens": .array(shown.filter { $0.value == name }.keys.sorted().map(JSON.string)),
                "native": .bool(!isVirtual(name))
            ]
        })
    }

    func screensJSON() -> JSON {
        let focused = currentScreen()?.uuid
        return .array(backend.screens().map { screen in
            let screenState = state(for: screen)
            return [
                "uuid": .string(screen.uuid), "name": .string(screen.name),
                "frame": .rect(screen.frame), "usable": .rect(usableRect(screen)),
                "layout": .string(screenState.layout.rawValue), "ratio": .number(Double(screenState.ratio)),
                "mainCount": .int(screenState.mainCount), "workspace": .string(shown[screen.uuid] ?? ""),
                "focused": .bool(screen.uuid == focused)
            ]
        })
    }
}
