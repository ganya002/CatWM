import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct ContainedInstanceTests {
    @Test func onlyAScopeWithADisplayIsContained() {
        #expect(WindowScope(pids: [5], display: "ABC").isContained)
        #expect(!WindowScope(pids: [5]).isContained)
    }

    @Test func aFrameIsPulledInsideTheBoundsAndShrunkToFit() {
        let bounds = NSRect(x: 100, y: 50, width: 800, height: 600)
        #expect(CatWMPanel.contained(NSRect(x: 5000, y: 5000, width: 200, height: 100), in: bounds)
            == NSRect(x: 700, y: 550, width: 200, height: 100))
        #expect(CatWMPanel.contained(NSRect(x: -9, y: -9, width: 200, height: 100), in: bounds)
            == NSRect(x: 100, y: 50, width: 200, height: 100))
        #expect(CatWMPanel.contained(NSRect(x: 300, y: 300, width: 50, height: 50), in: bounds)
            == NSRect(x: 300, y: 300, width: 50, height: 50))
        #expect(CatWMPanel.contained(NSRect(x: 0, y: 0, width: 2000, height: 900), in: bounds) == bounds)
    }

    @Test func aScopeDisplayIsTheOnlyScreenThatDrawingSees() throws {
        let main = try #require(NSScreen.screens.first)
        let uuid = try #require(main.displayUUID)
        #expect(NSScreen.userScreens(display: uuid) == [main])
        #expect(NSScreen.userScreens(display: "NO-SUCH-DISPLAY").isEmpty)
        #expect(!NSScreen.userScreens(display: nil).isEmpty)
    }

    @Test func aContainedPanelStaysOnItsDisplayWhateverTheCallerAsks() throws {
        let main = try #require(NSScreen.screens.first)
        let panel = CatWMPanel(role: .hud, frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        panel.containedDisplay = try #require(main.displayUUID)
        panel.setFrame(NSRect(x: 90_000, y: 90_000, width: 200, height: 80), display: false)
        #expect(main.frame.contains(panel.frame))
        panel.setFrameOrigin(NSPoint(x: -90_000, y: -90_000))
        #expect(main.frame.contains(panel.frame))
        panel.setFrameTopLeftPoint(NSPoint(x: 90_000, y: 90_000))
        #expect(main.frame.contains(panel.frame))
    }

    @Test func aContainedPanelWhoseDisplayIsGoneNeverShows() {
        let panel = CatWMPanel(role: .hud, frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        panel.containedDisplay = "NO-SUCH-DISPLAY"
        panel.orderFront(nil)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.order(.above, relativeTo: 0)
        #expect(!panel.isVisible)
    }

    @Test func aScopedInstanceShowsNoPermissionPrompt() {
        let guide = PermissionGuide()
        guide.show(.accessibility, scoped: true)
        #expect(guide.kind == nil)
    }
}
