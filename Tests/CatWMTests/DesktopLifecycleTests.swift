import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_DESKTOP_LIFECYCLE"] == "1"), .serialized)
struct DesktopLifecycleTests {
    @Test func aPreparedCoverMovesWhileHiddenAndDisplaysAfterCapture() async throws {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let current = Spaces.current(display: screen.uuid)
        let original = Spaces.list(display: screen.uuid)?.ids
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try #require(DesktopMenuBarNative.theme(current) == 1)
        try #require(CGPreflightScreenCaptureAccess())
        DesktopMenuBarCover.shared.prewarm(on: screen)
        let prepared = DesktopMenuBarCover.shared.panel(on: screen)
        DesktopMenuBarCover.shared.recycle(prepared)
        let created = try await DesktopLifecycle.create(on: screen)
        var captured: CatWMPanel?
        do {
            let moved = await poll(0.2, every: 1_000_000) {
                Spaces.of(window: CGWindowID(prepared.windowNumber)) == [created.space]
            }
            #expect(moved && !prepared.isVisible)
            captured = await DesktopMenuBarCover.shared.capture(on: screen, source: current, target: created.space)
            let panel = try #require(captured)
            #expect(panel === prepared && panel.isVisible)
            #expect(Spaces.of(window: CGWindowID(panel.windowNumber)) == [created.space])
            DesktopMenuBarCover.shared.recycle(panel)
            captured = nil
        } catch {
            DesktopMenuBarCover.shared.recycle(captured)
            try await discard(created.space, on: screen)
            throw error
        }
        try await discard(created.space, on: screen)
        #expect(Spaces.current(display: screen.uuid) == current)
        #expect(Spaces.list(display: screen.uuid)?.ids == original)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
    }

    @Test func createsAndRemovesOnEachDisplayWithoutChangingTheActiveDesktop() async throws {
        _ = NSApplication.shared
        let screens = Screen.all()
        #expect(!screens.isEmpty)
        let original = screens.map { Spaces.list(display: $0.uuid)?.ids }
        let originalSpaces = Set(original.compactMap(\.self).joined())
        let current = screens.map { Spaces.current(display: $0.uuid) }
        DesktopUI.prepare()
        #expect(screens.map { Spaces.list(display: $0.uuid)?.ids } == original)
        #expect(screens.map { Spaces.current(display: $0.uuid) } == current)
        for screen in screens {
            let snapshot = try #require(Spaces.snapshot())
            let created = try await DesktopLifecycle.create(on: screen, snapshot: snapshot)
            let space = created.space
            do {
                #expect(created.snapshot.list(display: screen.uuid)?.ids.contains(space) == true)
                let info = try #require(Spaces.list(display: screen.uuid))
                let index = try #require(info.ids.firstIndex(of: space))
                #expect(info.desktops.contains(index))
                #expect(!originalSpaces.contains(space))
                #expect(screens.map { Spaces.current(display: $0.uuid) } == current)
                #expect(screens.allSatisfy { !DesktopUI.isBusy(on: $0) })
            } catch {
                try await discard(space, on: screen)
                throw error
            }
            try await discard(space, on: screen)
            #expect(screens.map { Spaces.list(display: $0.uuid)?.ids } == original)
            #expect(screens.map { Spaces.current(display: $0.uuid) } == current)
        }
    }

    @Test func restoresADetachedMenuBackgroundWithoutChangingTheActiveDesktop() async throws {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let current = Spaces.current(display: screen.uuid)
        let created = try await DesktopLifecycle.create(on: screen)
        var saved: DesktopMenuBar.State?
        do {
            let ready = await DesktopMenuBar.ready(source: current, target: created.space, screen: screen)
            let state = try #require(ready)
            saved = state
            try state.persist()
            let source = try #require(DesktopBridge.state(current))
            let target = try #require(DesktopBridge.state(created.space))
            let context = DesktopGuard.Context(display: screen.uuid, source: current, destination: created.space,
                sourceOptions: source.options, destinationOptions: target.options, menuBar: state)
            #expect(DesktopBridge.detachMenuWindows([state.window], from: created.space))
            let detached = await poll(1) { Spaces.of(window: state.window).isEmpty }
            #expect(detached)
            context.restore()
            let restored = await poll(1) { state.isRestored }
            #expect(restored)
            state.clear()
            #expect(Spaces.current(display: screen.uuid) == current)
        } catch {
            saved?.restore()
            try await discard(created.space, on: screen)
            throw error
        }
        try await discard(created.space, on: screen)
        #expect(Spaces.current(display: screen.uuid) == current)
    }

    @Test func createsADesktopBeforeAnotherDesktop() async throws {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let current = Spaces.current(display: screen.uuid)
        let original = try #require(Spaces.list(display: screen.uuid))
        let successor = original.ids[try #require(original.desktops.last)]
        let created = try await DesktopLifecycle.create(on: screen, before: successor)
        let ids = Spaces.list(display: screen.uuid)?.ids ?? []
        try await discard(created.space, on: screen)
        #expect(ids.firstIndex(of: created.space).map { $0 + 1 } == ids.firstIndex(of: successor))
        #expect(Spaces.list(display: screen.uuid)?.ids == original.ids)
        #expect(Spaces.current(display: screen.uuid) == current)
    }

    @Test func refusesToRemoveTheCurrentDesktop() async throws {
        _ = NSApplication.shared
        for screen in Screen.all() {
            let space = Spaces.current(display: screen.uuid)
            await #expect(throws: DesktopTransitionError.self) {
                try await DesktopLifecycle.remove(space, on: screen)
            }
            #expect(Spaces.current(display: screen.uuid) == space)
        }
    }

    private func discard(_ space: UInt64, on screen: Screen) async throws {
        try await WindowManager(config: .parse(defaultText)).removeDesktop(space, on: screen)
    }
}
