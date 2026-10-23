import AppKit

extension WindowManager {
    private static let tilingRecoveryKey = "ws.tilingRecovery"

    private var recoveryIdentities: [CGWindowID: TilingRecovery.Identity] {
        windows.mapValues { .init(id: $0.id, pid: $0.pid, bundleID: $0.bundleID) }
    }

    func loadTilingRecovery(defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: Self.tilingRecoveryKey),
              let saved = try? JSONDecoder().decode(TilingRecovery.self, from: data) else { return }
        tilingRecovery = saved.validated
        lastSavedTilingRecovery = tilingRecovery
        for (display, bar) in tilingRecovery.menuBars where menuBarHeights[display] == nil {
            menuBarHeights[display] = MenuBarFloor(height: bar.height, visible: bar.visible)
        }
    }

    func restoreTilingRecovery(_ fresh: [Window]) {
        guard config.virtualWorkspaces, !restoringTemplate else { return }
        let arriving = Set(fresh.map(\.id))
        guard !arriving.isEmpty else { return }
        let identities = recoveryIdentities
        order = tilingRecovery.restoredOrder(order, arriving: arriving, windows: identities)
        let eligible = Set(fresh.filter { !$0.isFloating && !$0.minimized && !$0.fullscreen }.map(\.id))
        let zooms = tilingRecovery.restoredZooms(arriving: arriving, windows: identities,
                                                workspaces: workspaceOf, eligible: eligible)
        for (workspace, id) in zooms where isVirtual(workspace) && !isPending(workspace) {
            let state = state(workspace: workspace)
            if state.zoomed == nil { state.zoomed = id }
        }
    }

    func saveTilingRecovery(defaults: UserDefaults = .standard) {
        guard config.virtualWorkspaces, !restoringTemplate else { return }
        let identities = recoveryIdentities
        let zooms = states.compactMapValues(\.zoomed).filter { workspace, id in
            guard isVirtual(workspace), !isPending(workspace), workspaceOf[id] == workspace,
                  let window = windows[id] else { return false }
            return !window.isFloating && !window.fullscreen && !window.minimized
        }
        let available = scanner.lastScan == 0 ? nil : Dictionary(
            scanner.desktop.allWindows.map { ($0.id, $0.pid) }, uniquingKeysWith: { first, _ in first })
        let bars = menuBarHeights.mapValues { TilingRecovery.MenuBar(height: $0.height, visible: $0.visible) }
        let saved = tilingRecovery.capturing(order: order, windows: identities, zooms: zooms, available: available,
                                             menuBars: bars)
        tilingRecovery = saved
        guard saved != lastSavedTilingRecovery, let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.tilingRecoveryKey)
        lastSavedTilingRecovery = saved
    }
}
