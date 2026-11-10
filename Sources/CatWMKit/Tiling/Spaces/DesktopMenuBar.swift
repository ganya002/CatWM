import AppKit

package enum DesktopMenuBar {
    private static let freshKey = "ws.freshDesktops"
    @MainActor private static var fresh: Set<String> {
        get { Set(Instance.defaults.stringArray(forKey: freshKey) ?? []) }
        set { Instance.defaults.set(Array(newValue), forKey: freshKey) }
    }

    @MainActor package static func created(_ space: UInt64, in snapshot: Spaces.Snapshot) {
        guard let uuid = uuid(of: space, in: snapshot) else { return }
        fresh = live(fresh, in: snapshot).union([uuid])
    }

    @MainActor package static func removed() {
        guard let snapshot = Spaces.snapshot() else { return }
        fresh = live(fresh, in: snapshot)
    }

    private static func spaces(in snapshot: Spaces.Snapshot) -> [[String: Any]] {
        snapshot.displays.flatMap { $0["Spaces"] as? [[String: Any]] ?? [] }
    }

    private static func live(_ uuids: Set<String>, in snapshot: Spaces.Snapshot) -> Set<String> {
        uuids.intersection(spaces(in: snapshot).compactMap { $0["uuid"] as? String })
    }

    package struct State: Codable {
        package let window: CGWindowID
        package let space: UInt64
        package let uuid: String
        package let theme: Int32

        package var isRestored: Bool { Spaces.of(window: window) == [space] }

        package func persist() throws {
            guard let path = DesktopMenuBar.journal else {
                throw DesktopTransitionError.check("Cannot save Desktop recovery information")
            }
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: path, options: .atomic)
        }

        package func restore() {
            guard DesktopMenuBar.uuid(of: space) == uuid,
                  let info = DesktopMenuBarNative.info(window), DesktopMenuBar.isUnderbelly(info) else {
                clear(); return
            }
            if isRestored { clear(); return }
            guard Spaces.of(window: window).isEmpty else { return }
            let replacement = DesktopMenuBarNative.windows(
                on: space, levels: [CGWindowLevelForKey(.desktopIconWindow) + 1]).contains {
                $0.id != window && DesktopMenuBar.isUnderbelly($0)
            }
            if replacement { clear(); return }
            _ = DesktopBridge.attachMenuWindows([window], to: space)
            if isRestored { clear() }
        }

        package func clear() {
            guard let path = DesktopMenuBar.journal,
                  let saved = try? Data(contentsOf: path),
                  let state = try? JSONDecoder().decode(State.self, from: saved),
                  state.window == window, state.uuid == uuid else { return }
            try? FileManager.default.removeItem(at: path)
        }
    }

    package static var journal: URL? { Instance.cacheFolder.appendingPathComponent("desktop-menu-restore.json") }

    package static func recover() {
        guard let path = journal, let data = try? Data(contentsOf: path),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        state.restore()
        DesktopMenuBarNative.alpha(state.space, -1)
    }

    @MainActor package static func needsPreparation(source: UInt64, target: UInt64) -> Bool {
        DesktopMenuBarNative.theme(source) == 1 && DesktopMenuBarNative.theme(target) == 0
            && isFresh(target)
    }

    @MainActor package static func isFresh(_ space: UInt64) -> Bool { uuid(of: space).map(fresh.contains) == true }

    @MainActor package static func shown(_ space: UInt64) {
        if let uuid = uuid(of: space) { fresh.remove(uuid) }
    }

    @MainActor package static func ready(source: UInt64, target: UInt64, screen: Screen) async -> State? {
        var background: DesktopMenuBarNative.WindowInfo?
        let ready = await poll(0.1, every: 250_000) {
            let windows = DesktopMenuBarNative.windows(on: target, levels: [
                CGWindowLevelForKey(.desktopIconWindow) + 1, CGWindowLevelForKey(.desktopWindow) - 1
            ])
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

    @MainActor package static func settle(_ state: State?, on screen: Screen, while current: () -> Bool) async throws {
        guard current(), let state, Spaces.current(display: screen.uuid) == state.space else { return }
        fresh.remove(state.uuid)
        if DesktopMenuBarNative.theme(state.space) == state.theme { return }
        let started = ProcessInfo.processInfo.systemUptime
        let ready = await poll(1, every: 4_000_000, while: current) {
            DesktopMenuBarNative.theme(state.space) == state.theme
        }
        guard current() else { return }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
        Log.info("native workspaces: menu bar appearance on Desktop \(state.space) "
            + (ready ? "settled in \(elapsed) ms" : "did not settle"))
        try await DesktopMotion(screen: screen.nsScreen).frames(2)
    }

    package static func isUnderbelly(_ info: DesktopMenuBarNative.WindowInfo) -> Bool {
        info.owner == 0 && info.level == CGWindowLevelForKey(.desktopIconWindow) + 1
    }

    private static func uuid(of space: UInt64, in snapshot: Spaces.Snapshot? = Spaces.snapshot()) -> String? {
        snapshot.flatMap { spaces(in: $0).first { $0["ManagedSpaceID"] as? UInt64 == space }?["uuid"] as? String }
    }
}

@MainActor package final class DesktopMenuBarLease {
    package let state: DesktopMenuBar.State
    private var panel: CatWMPanel?
    private var finished = false

    package init(state: DesktopMenuBar.State, panel: CatWMPanel?) {
        self.state = state
        self.panel = panel
    }

    package func finish() async {
        state.restore()
        let restored = await poll(0.2, every: 1_000_000) { self.state.isRestored }
        if restored { state.clear() }
        restore()
    }

    package func restore() {
        guard !finished else { return }
        finished = true
        let batch = WindowServerUpdates.shared.begin()
        defer { batch?.finish() }
        if let panel { DesktopMenuBarNative.orderOut(CGWindowID(panel.windowNumber)) }
        panel?.orderOut(nil)
        state.restore()
        DesktopMenuBarNative.alpha(state.space, -1)
        DesktopMenuBarCover.shared.recycle(panel)
        panel = nil
    }
}
