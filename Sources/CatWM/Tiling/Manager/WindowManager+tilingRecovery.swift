import AppKit

extension WindowManager {
    private static let tilingRecoveryKey = "ws.tilingRecovery"
    private static let relaunchWindow: TimeInterval = 60
    private static let powerOffWindow: TimeInterval = 120

    func recoveryIdentity(_ window: Window) -> TilingRecovery.Identity {
        .init(id: window.id, pid: window.pid, bundleID: window.bundleID)
    }

    private var recoveryIdentities: [CGWindowID: TilingRecovery.Identity] { windows.mapValues(recoveryIdentity) }

    var isPoweringOff: Bool { Date().timeIntervalSince(poweringOffAt) < Self.powerOffWindow }

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
        guard !restoringTemplate else { return }
        let arriving = Set(fresh.map(\.id))
        guard !arriving.isEmpty else { return }
        rebindRelaunched(fresh)
        for window in fresh {
            guard let memo = tilingRecovery.memos[recoveryIdentity(window)] else { continue }
            if let chosen = memo.chosen, window.userFloating == .automatic {
                window.userFloating = .chosen(chosen == .floating)
            }
            queueSavedTabs(memo)
        }
        guard config.virtualWorkspaces else { return }
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

    private func rebindRelaunched(_ fresh: [Window]) {
        let now = Date()
        let relaunched = fresh.filter { window in
            let launched = NSRunningApplication(processIdentifier: window.pid)?.launchDate ?? .distantPast
            return now.timeIntervalSince(max(launched, startedAt)) < Self.relaunchWindow
        }
        guard !relaunched.isEmpty else { return }
        let pairs = tilingRecovery.rebind(relaunched.map { window in
            .init(identity: recoveryIdentity(window), title: window.title ?? "", frame: window.cachedFrame)
        })
        guard !pairs.isEmpty else { return }
        savedTabs = savedTabs.map { saved in
            var saved = saved
            saved.members = saved.members.map { member in
                pairs[member.identity].map { .init(id: $0.id, pid: $0.pid, bundleID: $0.bundleID) } ?? member
            }
            return saved
        }
        Log.info("recovery: matched \(pairs.count) relaunched windows to their old places")
    }

    private func queueSavedTabs(_ memo: TilingRecovery.Memo) {
        guard memo.tabs.count > 1,
              !savedTabs.contains(where: { $0.members.contains { memo.tabs.contains($0.identity) } }) else { return }
        let active = memo.tabs.first { tilingRecovery.memos[$0]?.activeTab == true } ?? memo.tabs[0]
        savedTabs.append(SavedTabs(members: memo.tabs.map { .init(id: $0.id, pid: $0.pid, bundleID: $0.bundleID) },
                                   active: active.id))
        savedTabsUntil = max(savedTabsUntil, Date().addingTimeInterval(SavedTabs.wait))
    }

    func saveTilingRecovery(defaults: UserDefaults = .standard) {
        guard !restoringTemplate else { return }
        let identities = recoveryIdentities
        let zooms = states.compactMapValues(\.zoomed).filter { workspace, id in
            guard isVirtual(workspace), !isPending(workspace), workspaceOf[id] == workspace,
                  let window = windows[id] else { return false }
            return !window.isFloating && !window.fullscreen && !window.minimized
        }
        let available = scanner.lastScan == 0 ? nil : Dictionary(
            scanner.desktop.allWindows.map { ($0.id, $0.pid) }, uniquingKeysWith: { first, _ in first })
        let bars = menuBarHeights.mapValues { TilingRecovery.MenuBar(height: $0.height, visible: $0.visible) }
        let poweringOff = isPoweringOff
        let saved = tilingRecovery.capturing(
            order: order, windows: identities, zooms: zooms, available: available, menuBars: bars,
            memos: recoveryMemos(identities), departing: { entry in
                poweringOff || NSRunningApplication(processIdentifier: entry.pid)
                    .map { $0.bundleIdentifier != entry.bundleID || $0.isTerminated } ?? true
            })
        tilingRecovery = saved
        guard saved != lastSavedTilingRecovery, let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.tilingRecoveryKey)
        lastSavedTilingRecovery = saved
    }

    private func recoveryMemos(_ identities: [CGWindowID: TilingRecovery.Identity])
        -> [TilingRecovery.Identity: TilingRecovery.Memo] {
        Dictionary(windows.values.compactMap { window in
            guard let identity = identities[window.id] else { return nil }
            let frame = (targets[window.id] ?? window.cachedFrame).integral
            var memo = TilingRecovery.Memo(title: window.title ?? "", frame: frame)
            if case .chosen(let floating) = window.userFloating { memo.chosen = floating ? .floating : .tiled }
            if !savedTabs.isEmpty {
                memo.tabs = tilingRecovery.memos[identity]?.tabs ?? []
                memo.activeTab = tilingRecovery.memos[identity]?.activeTab ?? false
            } else if let group = tabs.group(of: window.id) {
                memo.tabs = group.members.compactMap { identities[$0] }
                memo.activeTab = group.active == window.id
            }
            return (identity, memo)
        }, uniquingKeysWith: { first, _ in first })
    }
}
