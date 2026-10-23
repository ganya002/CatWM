import AppKit
@testable import ouch
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OUCH_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct DesktopCoverPanelTests {
    private func screen() throws -> Screen {
        _ = NSApplication.shared
        return try #require(Screen.all().first)
    }

    @Test func aPreparedPanelStaysHiddenAndReturnsToThePool() throws {
        let screen = try screen()
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let space = Spaces.current(display: screen.uuid)
        DesktopMenuBarCover.prewarm(on: screen)
        let first = DesktopMenuBarCover.panel(on: screen)
        let id = first.windowNumber
        #expect(!first.isVisible && !first.canBecomeKey && !first.canBecomeMain)
        DesktopMenuBarCover.recycle(first)
        let second = DesktopMenuBarCover.panel(on: screen)
        #expect(second === first && second.windowNumber == id)
        DesktopMenuBarCover.recycle(second)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
        #expect(Spaces.current(display: screen.uuid) == space)
    }

    @Test func recyclingClearsThePreviousImage() throws {
        let panel = DesktopMenuBarCover.panel(on: try screen())
        let view = try #require(panel.contentView as? NSImageView)
        view.image = NSImage(size: CGSize(width: 10, height: 10))
        DesktopMenuBarCover.recycle(panel)
        #expect(view.image == nil && !panel.isVisible)
    }

    @Test func thePoolKeepsOnePanelWhenTwoCoversReturn() throws {
        let screen = try screen()
        let first = DesktopMenuBarCover.panel(on: screen)
        let second = DesktopMenuBarCover.panel(on: screen)
        #expect(first !== second)
        DesktopMenuBarCover.recycle(first)
        DesktopMenuBarCover.recycle(second)
        let retained = DesktopMenuBarCover.panel(on: screen)
        #expect(retained === first)
        DesktopMenuBarCover.recycle(retained)
        DesktopMenuBarCover.recycle(retained)
        let again = DesktopMenuBarCover.panel(on: screen)
        #expect(again === retained)
        DesktopMenuBarCover.recycle(again)
    }

    @Test func reuseAdaptsThePanelAndImageViewToTheDisplay() throws {
        let screen = try screen()
        DesktopMenuBarCover.prewarm(on: screen)
        let narrower = Screen(id: screen.id, uuid: screen.uuid,
            frame: CGRect(origin: screen.frame.origin, size: CGSize(width: screen.frame.width / 2,
                                                                   height: screen.frame.height)),
            visible: screen.visible, isBuiltin: screen.isBuiltin, nsScreen: screen.nsScreen)
        let panel = DesktopMenuBarCover.panel(on: narrower)
        #expect(panel.frame.width == narrower.frame.width)
        #expect(panel.contentView?.frame.width == narrower.frame.width)
        DesktopMenuBarCover.recycle(panel)
        let restored = DesktopMenuBarCover.panel(on: screen)
        #expect(restored === panel && restored.frame.width == screen.frame.width)
        #expect(restored.contentView?.frame.width == screen.frame.width)
        DesktopMenuBarCover.recycle(restored)
    }
}
