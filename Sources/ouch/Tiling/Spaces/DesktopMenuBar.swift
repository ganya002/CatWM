import AppKit

enum DesktopMenuBar {
    private static let freshKey = "ws.freshDesktops"
    @MainActor private static var fresh: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: freshKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: freshKey) }
    }

    @MainActor static func created(_ space: UInt64, in snapshot: Spaces.Snapshot) {
        guard let uuid = uuid(of: space, in: snapshot) else { return }
        fresh = live(fresh, in: snapshot).union([uuid])
    }

    @MainActor static func removed() {
        guard let snapshot = Spaces.snapshot() else { return }
        fresh = live(fresh, in: snapshot)
    }

    private static func spaces(in snapshot: Spaces.Snapshot) -> [[String: Any]] {
        snapshot.displays.flatMap { $0["Spaces"] as? [[String: Any]] ?? [] }
    }

    private static func live(_ uuids: Set<String>, in snapshot: Spaces.Snapshot) -> Set<String> {
        uuids.intersection(spaces(in: snapshot).compactMap { $0["uuid"] as? String })
    }

    struct State: Codable {
        let window: CGWindowID
        let space: UInt64
        let uuid: String
        let theme: Int32

        var isRestored: Bool { Spaces.of(window: window) == [space] }

        func persist() throws {
            guard let path = DesktopMenuBar.journal else {
                throw DesktopTransitionError.check("Cannot save Desktop recovery information")
            }
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: path, options: .atomic)
        }

        func restore() {
            guard DesktopMenuBar.uuid(of: space) == uuid,
                  let info = DesktopMenuBarNative.info(window), DesktopMenuBar.isUnderbelly(info) else {
                clear(); return
            }
            if isRestored { clear(); return }
            guard Spaces.of(window: window).isEmpty else { return }
            let replacement = DesktopMenuBarNative.windows(on: space).contains {
                $0.id != window && DesktopMenuBar.isUnderbelly($0)
            }
            if replacement { clear(); return }
            _ = DesktopBridge.attachMenuWindows([window], to: space)
            if isRestored { clear() }
        }

        func clear() {
            guard let path = DesktopMenuBar.journal,
                  let saved = try? Data(contentsOf: path),
                  let state = try? JSONDecoder().decode(State.self, from: saved),
                  state.window == window, state.uuid == uuid else { return }
            try? FileManager.default.removeItem(at: path)
        }
    }

    static var journal: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ouch/desktop-menu-restore.json")
    }

    static func recover() {
        guard let path = journal, let data = try? Data(contentsOf: path),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        state.restore()
        DesktopMenuBarNative.alpha(state.space, -1)
    }

    @MainActor static func needsPreparation(source: UInt64, target: UInt64) -> Bool {
        DesktopMenuBarNative.theme(source) == 1 && DesktopMenuBarNative.theme(target) == 0
            && isFresh(target)
    }

    @MainActor static func isFresh(_ space: UInt64) -> Bool { uuid(of: space).map(fresh.contains) == true }

    @MainActor static func shown(_ space: UInt64) {
        if let uuid = uuid(of: space) { fresh.remove(uuid) }
    }

    @MainActor static func ready(source: UInt64, target: UInt64, screen: Screen) async -> State? {
        var background: DesktopMenuBarNative.WindowInfo?
        let ready = await poll(0.1, every: 250_000) {
            let windows = DesktopMenuBarNative.windows(on: target)
            background = windows.first {
                isUnderbelly($0) && $0.frame.minY == screen.frame.minY
                    && $0.frame.width == screen.frame.width && Spaces.of(window: $0.id) == [target]
            }
            let wallpaper = windows.contains { $0.level == CGWindowLevelForKey(.desktopWindow) - 1 }
            return background != nil && wallpaper
        }
        if !ready { Log.info("native workspaces: the menu bar of Desktop \(target) was not ready") }
        guard ready, let background, let uuid = uuid(of: target),
              let theme = DesktopMenuBarNative.theme(source) else { return nil }
        return State(window: background.id, space: target, uuid: uuid, theme: theme)
    }

    @MainActor static func settle(_ state: State?, on screen: Screen) async throws {
        guard let state, Spaces.current(display: screen.uuid) == state.space else { return }
        fresh.remove(state.uuid)
        if DesktopMenuBarNative.theme(state.space) == state.theme { return }
        let started = ProcessInfo.processInfo.systemUptime
        let ready = await poll(1, every: 4_000_000) { DesktopMenuBarNative.theme(state.space) == state.theme }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
        Log.info("native workspaces: menu bar appearance on Desktop \(state.space) "
            + (ready ? "settled in \(elapsed) ms" : "did not settle"))
        try await DesktopMotion(screen: screen.nsScreen).frames(2)
    }

    static func isUnderbelly(_ info: DesktopMenuBarNative.WindowInfo) -> Bool {
        info.owner == 0 && info.level == CGWindowLevelForKey(.desktopIconWindow) + 1
    }

    private static func uuid(of space: UInt64, in snapshot: Spaces.Snapshot? = Spaces.snapshot()) -> String? {
        snapshot.flatMap { spaces(in: $0).first { $0["ManagedSpaceID"] as? UInt64 == space }?["uuid"] as? String }
    }
}
