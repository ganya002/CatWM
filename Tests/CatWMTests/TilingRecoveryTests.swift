import AppKit
@testable import CatWM
import Testing

@Suite struct TilingRecoveryTests {
    private func identity(_ id: CGWindowID, pid: pid_t? = nil, bundleID: String = "test.app")
        -> TilingRecovery.Identity {
        .init(id: id, pid: pid ?? pid_t(id + 10), bundleID: bundleID)
    }

    @Test func asynchronousDiscoveryKeepsTheOriginalWindowOrder() {
        let first = identity(1), second = identity(2)
        let saved = TilingRecovery(order: [first, second])
        #expect(saved.restoredOrder([2], arriving: [2], windows: [2: second]) == [2])
        #expect(saved.restoredOrder([2, 1], arriving: [1], windows: [1: first, 2: second]) == [1, 2])
    }

    @Test func lateWindowsDoNotUndoUserReorderingOrANewMainWindow() {
        let entries = (1...4).map { identity(CGWindowID($0)) }
        let windows = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let saved = TilingRecovery(order: Array(entries.prefix(3)))
        #expect(saved.restoredOrder([3, 2, 1], arriving: [1], windows: windows) == [1, 3, 2])
        #expect(saved.restoredOrder([4, 2, 1], arriving: [1, 4], windows: windows) == [4, 1, 2])
    }

    @Test(arguments: [false, true])
    func aReusedWindowIDDoesNotRestoreAnotherOwnersState(changedBundle: Bool) {
        let first = identity(1), second = identity(2)
        let reused = identity(1, pid: changedBundle ? first.pid : 99,
                              bundleID: changedBundle ? "different.app" : "test.app")
        let saved = TilingRecovery(order: [first, second], zoomed: ["left": first])
        #expect(saved.restoredOrder([2, 1], arriving: [1], windows: [1: reused, 2: second]) == [2, 1])
        #expect(saved.restoredZooms(arriving: [1], windows: [1: reused],
                                   workspaces: [1: "left"], eligible: [1]).isEmpty)
    }

    @Test func anIncompleteStartupDoesNotEraseUndiscoveredWindowState() {
        let first = identity(1), second = identity(2)
        let saved = TilingRecovery(order: [first, second], zoomed: ["left": first])
        let firstPass = saved.capturing(order: [2], windows: [2: second], zooms: [:],
                                        available: [1: first.pid, 2: second.pid])
        #expect(firstPass == saved)
        #expect(saved.capturing(order: [], windows: [:], zooms: [:], available: nil) == saved)
        #expect(saved.capturing(order: [2], windows: [2: second], zooms: [:], available: [1: 0]) == saved)
        let settled = firstPass.capturing(order: [2, 1], windows: [1: first, 2: second], zooms: [:], available: [:])
        #expect(settled.order == [second, first] && settled.zoomed.isEmpty)
    }

    @Test func closedWindowsAndChangedServerOwnersCannotStayPending() {
        let first = identity(1), second = identity(2)
        let saved = TilingRecovery(order: [first, second], zoomed: ["left": first])
        for available: [CGWindowID: pid_t] in [[:], [1: 99]] {
            let found = saved.capturing(order: [2], windows: [2: second], zooms: [:], available: available)
            #expect(found.order == [second] && found.zoomed.isEmpty)
        }
    }

    @Test func fullscreenRestorationRequiresTheSameWorkspaceAndAnEligibleWindow() {
        let window = identity(1)
        let saved = TilingRecovery(order: [window], zoomed: ["left": window])
        #expect(saved.restoredZooms(arriving: [1], windows: [1: window],
                                   workspaces: [1: "left"], eligible: [1]) == ["left": 1])
        #expect(saved.restoredZooms(arriving: [1], windows: [1: window],
                                   workspaces: [1: "right"], eligible: [1]).isEmpty)
        #expect(saved.restoredZooms(arriving: [1], windows: [1: window],
                                   workspaces: [1: "left"], eligible: []).isEmpty)
        #expect(saved.restoredZooms(arriving: [], windows: [1: window],
                                   workspaces: [1: "left"], eligible: [1]).isEmpty)
    }

    @Test func persistedDataRejectsInvalidAndDuplicateIdentities() throws {
        let valid = identity(1)
        let invalid = TilingRecovery(order: [identity(0), valid, identity(1, pid: 99), identity(2, pid: 0)],
                                      zoomed: ["left": identity(1, pid: 99), "": valid])
        let decoded = try JSONDecoder().decode(TilingRecovery.self, from: JSONEncoder().encode(invalid)).validated
        #expect(decoded == TilingRecovery(order: [valid]))
    }

    @Test func recoveryWithoutMenuBarDataRemainsReadable() throws {
        let data = Data("{\"order\":[],\"zoomed\":{}}".utf8)
        #expect(try JSONDecoder().decode(TilingRecovery.self, from: data) == TilingRecovery())
    }

    @Test func invalidMenuBarLimitsCannotChangeTheUsableScreenArea() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let saved = TilingRecovery(menuBars: [
            "valid": .init(height: 38, visible: visible),
            "huge": .init(height: 1000, visible: visible),
            "empty": .init(height: 38, visible: .zero)
        ])
        #expect(saved.validated.menuBars == ["valid": .init(height: 38, visible: visible)])
    }

    @Test @MainActor func aLearnedMenuBarLimitSurvivesOnlyMatchingDisplayGeometry() throws {
        let name = "TilingRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let original = WindowManager()
        original.config.virtualWorkspaces = true
        original.menuBarHeights["display"] = .init(height: 38, visible: visible)
        original.saveTilingRecovery(defaults: defaults)
        let restarted = WindowManager()
        restarted.loadTilingRecovery(defaults: defaults)
        #expect(restarted.menuBarHeights["display"]?.height(on: visible) == 38)
        #expect(restarted.menuBarHeights["display"]?.height(on: visible.insetBy(dx: 0, dy: 10)) == nil)
    }

    @Test @MainActor func aManagerRestartRestoresOrderAndFullscreenBeforePlacement() throws {
        let name = "TilingRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Window(id: 1, element: AXUIElementCreateApplication(-1), pid: 11, bundleID: "test.app")
        let second = Window(id: 2, element: AXUIElementCreateApplication(-1), pid: 12, bundleID: "test.app")
        let original = WindowManager()
        original.config.virtualWorkspaces = true
        original.windows = [1: first, 2: second]
        original.order = [1, 2]
        original.model.assign(1, to: "left")
        original.model.assign(2, to: "left")
        original.state(workspace: "left").zoomed = 2
        original.saveTilingRecovery(defaults: defaults)
        let restarted = WindowManager()
        restarted.config.virtualWorkspaces = true
        restarted.loadTilingRecovery(defaults: defaults)
        restarted.windows = [2: second]
        restarted.order = [2]
        restarted.model.assign(2, to: "left")
        restarted.restoreTilingRecovery([second])
        restarted.saveTilingRecovery(defaults: defaults)
        #expect(restarted.state(workspace: "left").zoomed == 2)
        #expect(restarted.tilingRecovery == original.tilingRecovery)
        restarted.windows[1] = first
        restarted.order.append(1)
        restarted.model.assign(1, to: "left")
        restarted.restoreTilingRecovery([first])
        #expect(restarted.order == [1, 2])
        restarted.forget(2)
        restarted.saveTilingRecovery(defaults: defaults)
        let again = WindowManager()
        again.loadTilingRecovery(defaults: defaults)
        #expect(again.tilingRecovery.order.map(\.id) == [1] && again.tilingRecovery.zoomed.isEmpty)
    }

    @Test @MainActor func anExplicitFullscreenChangeDiscardsPendingRestoration() throws {
        let name = "TilingRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let entry = identity(1)
        let saved = TilingRecovery(order: [entry], zoomed: ["left": entry])
        let manager = WindowManager()
        manager.config.virtualWorkspaces = true
        manager.tilingRecovery = saved
        manager.lastSavedTilingRecovery = saved
        manager.tilingRecovery.zoomed["left"] = nil
        manager.saveTilingRecovery(defaults: defaults)
        let restarted = WindowManager()
        restarted.loadTilingRecovery(defaults: defaults)
        #expect(restarted.tilingRecovery.order == [entry] && restarted.tilingRecovery.zoomed.isEmpty)
    }

    @Test @MainActor func aTemplateRestoreReplacesPendingStartupState() throws {
        let name = "TilingRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let entry = identity(1)
        let manager = WindowManager()
        manager.config.virtualWorkspaces = true
        manager.tilingRecovery = .init(order: [entry], zoomed: ["left": entry])
        manager.lastSavedTilingRecovery = manager.tilingRecovery
        manager.restoringTemplate = true
        #expect(manager.tilingRecovery == TilingRecovery())
        manager.restoringTemplate = false
        manager.saveTilingRecovery(defaults: defaults)
        let restarted = WindowManager()
        restarted.loadTilingRecovery(defaults: defaults)
        #expect(restarted.tilingRecovery == TilingRecovery())
    }
}
