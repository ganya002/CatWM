import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct NativeLayoutPreparationTests {
    @Test @MainActor func aRecoveredLayoutNeedsNoRepositioningBeforeDesktopMotion() async throws {
        guard let screen = Screen.all().first else { return }
        let name = "NativeLayoutPreparationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Window(id: 1, element: AXUIElementCreateApplication(-1), pid: 11, bundleID: "test.app")
        let second = Window(id: 2, element: AXUIElementCreateApplication(-1), pid: 12, bundleID: "test.app")
        let original = WindowManager(config: .parse(defaultText))
        original.config.virtualWorkspaces = true
        original.windows = [1: first, 2: second]
        original.order = [1, 2]
        for id: CGWindowID in [1, 2] { original.model.assign(id, to: "test") }
        original.state(workspace: "test").zoomed = 2
        let frames = try #require(original.layoutTargets([1, 2], original.state(workspace: "test"), on: screen))
        first.remember(try #require(frames[1]))
        second.remember(try #require(frames[2]))
        original.saveTilingRecovery(defaults: defaults)
        let manager = WindowManager(config: .parse(defaultText))
        manager.config.virtualWorkspaces = true
        manager.loadTilingRecovery(defaults: defaults)
        manager.windows = [1: first, 2: second]
        manager.order = [2, 1]
        for id: CGWindowID in [1, 2] { manager.model.assign(id, to: "test") }
        manager.observedApps = [(pid: 11, bundleID: "test.app"), (pid: 12, bundleID: "test.app")]
        manager.restoreTilingRecovery([second, first])
        var writers = 0
        manager.animator = Animator(makeWriter: { writers += 1; return AXWriter(pid: $0) })
        try await manager.prepareNativeLayout(.init(workspace: "test", display: screen.uuid, space: 0),
                                             readFrames: { _ in frames })
        #expect(manager.order == [1, 2])
        #expect(manager.targets[1] == frames[1] && manager.targets[2] == frames[2])
        #expect(writers == 0)
    }

    @Test(arguments: [false, true], [false, true]) @MainActor
    func tabGroupsKeepOneTileAndTheirStripBeforeTheSwitch(activeAppHidden: Bool, autoHide: Bool) async throws {
        guard let screen = Screen.all().first else { return }
        let manager = WindowManager(config: .parse(defaultText))
        manager.config.autoHideTabStrip = autoHide
        let first = Window(id: .max - 50, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        let second = Window(id: .max - 51, element: AXUIElementCreateApplication(-2), pid: -2, bundleID: nil)
        for window in [first, second] {
            manager.windows[window.id] = window
            manager.order.append(window.id)
            manager.model.assign(window.id, to: "test")
            manager.observedApps.append((pid: window.pid, bundleID: nil))
        }
        manager.model.joinTab(second.id, onto: first.id)
        if activeAppHidden { manager.observedApps.removeAll { $0.pid == second.pid } }
        let slots = try #require(manager.layoutTargets([second.id], manager.state(workspace: "test"), on: screen))
        let tile = try #require(slots[second.id])
        let frame = autoHide ? tile : CGRect(x: tile.minX, y: tile.minY + TabGeometry.stripHeight,
                                             width: tile.width, height: tile.height - TabGeometry.stripHeight)
        first.remember(frame)
        second.remember(frame)
        var writers = 0
        manager.animator = Animator(makeWriter: { writers += 1; return AXWriter(pid: $0) })
        try await manager.prepareNativeLayout(.init(workspace: "test", display: screen.uuid, space: 0), readFrames: {
            #expect($0 == (activeAppHidden ? [first.id] : [first.id, second.id]))
            return [first.id: frame, second.id: frame]
        })
        #expect(manager.targets[first.id] == frame)
        #expect(manager.targets[second.id] == (activeAppHidden ? nil : frame))
        #expect(writers == 0)
    }

    @Test @MainActor func windowsOfHiddenAppsGetNoSlotBeforeTheSwitch() async throws {
        guard let screen = Screen.all().first else { return }
        let manager = WindowManager(config: .parse(defaultText))
        manager.config.windowMargins = false
        let shown = Window(id: 1, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        let hidden = Window(id: 2, element: AXUIElementCreateApplication(-2), pid: -2, bundleID: nil)
        for window in [shown, hidden] {
            manager.windows[window.id] = window
            manager.order.append(window.id)
            manager.model.assign(window.id, to: "1")
        }
        manager.observedApps = [(pid: shown.pid, bundleID: nil)]
        try await manager.prepareNativeLayout(.init(workspace: "1", display: screen.uuid, space: 1))
        #expect(manager.targets[hidden.id] == nil)
        let alone = try #require(manager.layoutTargets([shown.id], manager.state(workspace: "1"), on: screen))
        #expect(manager.targets[shown.id] == alone[shown.id])
    }
}
