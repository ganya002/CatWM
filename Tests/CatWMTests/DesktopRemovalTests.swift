import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite(.serialized) struct DesktopRemovalTests {
    @Test func anOccupiedDesktopIsNotRetried() async throws {
        guard let screen = Screen.all().first else { return }
        let manager = WindowManager(config: .parse(defaultText))
        var attempts = 0
        do {
            try await manager.removeDesktop(0, on: screen) { _, _ in
                attempts += 1
                throw DesktopTransitionError.occupied
            }
            Issue.record("An occupied Desktop was accepted for removal")
        } catch DesktopTransitionError.occupied { }
        #expect(attempts == 1)
    }

    @Test func aTransientRemovalFailureStillRetries() async throws {
        guard let screen = Screen.all().first else { return }
        let manager = WindowManager(config: .parse(defaultText))
        var attempts = 0
        try await manager.removeDesktop(0, on: screen) { _, _ in
            attempts += 1
            if attempts == 1 { throw DesktopTransitionError.check("Temporary WindowServer failure") }
        }
        #expect(attempts == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_INACTIVE_DESKTOP"] == "1"))
    func anInvisibleOccupantDoesNotBlockRequestsForRepeatedRemovalAttempts() async throws {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let before = try #require(Spaces.list(display: screen.uuid))
        let source = Spaces.current(display: screen.uuid)
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try #require(CGDisplayIsAsleep(CGMainDisplayID()) == 0 && DesktopBridge.isIdle(display: screen.uuid))
        let panel = NSPanel(contentRect: CGRect(x: -5000, y: -5000, width: 160, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.level = .normal
        panel.orderFrontRegardless()
        let helper = CGWindowID(panel.windowNumber)
        guard let space = DesktopBridge.create() else { panel.close(); Issue.record("Cannot create a Desktop"); return }
        var failure: Error?
        do {
            try #require(NativeSpaceMove.move(window: helper, to: space))
            let held = await poll(1, every: 1_000_000) { Spaces.of(window: helper) == [space] }
            try #require(held)
            let start = ProcessInfo.processInfo.systemUptime
            do {
                try await WindowManager(config: .parse(defaultText)).removeDesktop(space, on: screen)
                Issue.record("The occupied Desktop was removed")
            } catch DesktopTransitionError.occupied { }
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            print("occupied inactive Desktop: rejection \(elapsed) ms; helper \(helper)")
            #expect(elapsed < 150)
            #expect(Spaces.list(display: screen.uuid)?.ids.contains(space) == true)
        } catch { failure = error }
        panel.close()
        let empty = await poll(1, every: 1_000_000) {
            !CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements]).contains {
                Spaces.of(window: $0.id) == [space]
            }
        }
        if empty, Spaces.current(display: screen.uuid) != space {
            _ = DesktopBridge.remove(space)
            let removed = await poll(1) { Spaces.list(display: screen.uuid)?.ids.contains(space) == false }
            #expect(removed)
        } else {
            Issue.record("The test Desktop became active or occupied; it was retained")
        }
        #expect(Spaces.list(display: screen.uuid)?.ids == before.ids)
        #expect(Spaces.current(display: screen.uuid) == source)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
        if let failure { throw failure }
    }
}
