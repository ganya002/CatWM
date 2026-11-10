import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite @MainActor struct WindowPlacementTests {
    @Test func registrationAndPlacementRestoreFramesOrderAndZoom() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let first = fake.addWindow()
        let second = fake.addWindow()
        let manager = fake.makeManager()
        #expect(await fake.settle(manager))
        manager.restoringTemplate = true
        defer { manager.finishTemplateRestore() }
        let window = try #require(manager.windows[first])
        let frame = CGRect(x: 80, y: 90, width: 600, height: 500)
        let frames = manager.registerPlacements([
            .init(window: window, screen: screen, frame: frame, floating: true, hidden: false, zoomed: true)
        ], displays: [.init(screen: screen, layout: .wide, ratio: 0.7, mainCount: 2)],
           tiling: false, screens: [screen])
        #expect(manager.order == [first, second])
        #expect(manager.visible.contains(first))
        #expect(window.isFloating)
        #expect(!manager.tilingEnabled)
        #expect(manager.state(for: screen).layout == .wide)
        #expect(manager.state(for: screen).zoomed == first)
        #expect(manager.workspaceOf[first] == manager.workspaceKey(for: screen))
        let failed = try await manager.placeWindows(frames, verifying: [first], screens: [screen])
        #expect(failed.isEmpty)
        #expect(fake.frame(of: first) == frame)
    }

    @Test func hiddenRegistrationKeepsZoomButDoesNotShowTheWindow() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let id = fake.addWindow()
        let manager = fake.makeManager()
        #expect(await fake.settle(manager))
        let window = try #require(manager.windows[id])
        _ = manager.registerPlacements([
            .init(window: window, screen: screen, frame: window.cachedFrame,
                  floating: false, hidden: true, zoomed: true)
        ], displays: [], tiling: true, screens: [screen])
        #expect(!manager.present.contains(id))
        #expect(!manager.visible.contains(id))
        #expect(manager.state(for: screen).zoomed == id)
    }

    @Test func aHoldReleasesOnlyAfterANewerUnhiddenObservation() {
        let window = Window(id: 1, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        let held = Date(timeIntervalSince1970: 50_000)
        var holds = PlacementHolds()
        holds.hold(window, since: held)
        #expect(window.placementSuspended)
        for (date, minimized, fullscreen, restoring) in [
            (held.addingTimeInterval(-1), false, false, false),
            (held, false, false, false),
            (held.addingTimeInterval(1), true, false, false),
            (held.addingTimeInterval(1), false, true, false),
            (held.addingTimeInterval(1), false, false, true)
        ] {
            let released = holds.observe(window, scanStarted: date, minimized: minimized,
                                         fullscreen: fullscreen, restoring: restoring)
            #expect(!released)
            #expect(window.placementSuspended)
        }
        let released = holds.observe(window, scanStarted: held.addingTimeInterval(1),
                                     minimized: false, fullscreen: false, restoring: false)
        #expect(released)
        #expect(!window.placementSuspended)
    }

    @Test func aCancelledPlacementDoesNotWriteFrames() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let id = fake.addWindow()
        let manager = fake.makeManager()
        #expect(await fake.settle(manager))
        fake.clearWrites()
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await manager.placeWindows([id: CGRect(x: 0, y: 0, width: 400, height: 300)],
                                                   verifying: [id], screens: [screen])
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(fake.writes.isEmpty)
        #expect(manager.animator.destination(id) == nil)
    }
}
