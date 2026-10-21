import AppKit

enum DesktopMenuBar {
    @MainActor private static var fresh: Set<UInt64> = []
    @MainActor static func created(_ space: UInt64) { fresh.insert(space) }
    @MainActor static func removed(_ space: UInt64) { fresh.remove(space) }

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
    }

    @MainActor static func needsPreparation(source: UInt64, target: UInt64) -> Bool {
        fresh.contains(target) && DesktopMenuBarNative.theme(source) == 1 && DesktopMenuBarNative.theme(target) == 0
    }

    @MainActor static func ready(source: UInt64, target: UInt64, screen: Screen) async -> State? {
        let started = ProcessInfo.processInfo.systemUptime
        var background: DesktopMenuBarNative.WindowInfo?
        var observed: [DesktopMenuBarNative.WindowInfo] = []
        let ready = await poll(0.1, every: 1_000_000) {
            let windows = DesktopMenuBarNative.windows(on: target)
            observed = windows
            background = windows.first {
                isUnderbelly($0) && $0.frame.minY == screen.frame.minY
                    && $0.frame.width == screen.frame.width && Spaces.of(window: $0.id) == [target]
            }
            let wallpaper = windows.contains { $0.level == CGWindowLevelForKey(.desktopWindow) - 1 }
            return background != nil && wallpaper
        }
        Log.info("desktop probe: ready \(ready) in \((ProcessInfo.processInfo.systemUptime - started) * 1_000) "
            + "windows \(observed.map { "\($0.id):\($0.level):\($0.owner):\($0.frame)" })")
        guard ready, let background, let uuid = uuid(of: target),
              let theme = DesktopMenuBarNative.theme(source) else { return nil }
        return State(window: background.id, space: target, uuid: uuid, theme: theme)
    }

    @MainActor static func settle(_ state: State?, on screen: Screen) async throws {
        guard let state, Spaces.current(display: screen.uuid) == state.space else { return }
        let ready = await poll(1, every: 4_000_000) { DesktopMenuBarNative.theme(state.space) == state.theme }
        if !ready { Log.info("native workspaces: menu bar appearance did not settle on Desktop \(state.space)") }
        try await DesktopMotion(screen: screen.nsScreen).frames(2)
        fresh.remove(state.space)
    }

    static func isUnderbelly(_ info: DesktopMenuBarNative.WindowInfo) -> Bool {
        info.owner == 0 && info.level == CGWindowLevelForKey(.desktopIconWindow) + 1
    }

    private static func uuid(of space: UInt64) -> String? {
        Spaces.snapshot()?.displays.lazy.compactMap { $0["Spaces"] as? [[String: Any]] }.joined()
            .first { $0["ManagedSpaceID"] as? UInt64 == space }?["uuid"] as? String
    }
}
