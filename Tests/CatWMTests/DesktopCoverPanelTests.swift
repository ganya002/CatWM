import AppKit
@testable import CatWM
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct DesktopCoverPanelTests {
    private let cover = DesktopMenuBarCover()

    private func screen() throws -> Screen {
        _ = NSApplication.shared
        return try #require(Screen.all().first)
    }

    @Test func aPreparedPanelStaysHiddenAndReturnsToThePool() throws {
        let screen = try screen()
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let space = Spaces.current(display: screen.uuid)
        cover.prewarm(on: screen)
        let first = cover.panel(on: screen)
        let id = first.windowNumber
        #expect(!first.isVisible && !first.canBecomeKey && !first.canBecomeMain)
        cover.recycle(first)
        let second = cover.panel(on: screen)
        #expect(second === first && second.windowNumber == id)
        cover.recycle(second)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
        #expect(Spaces.current(display: screen.uuid) == space)
    }

    @Test func recyclingClearsThePreviousImage() throws {
        let panel = cover.panel(on: try screen())
        let view = try #require(panel.contentView as? NSImageView)
        view.image = NSImage(size: CGSize(width: 10, height: 10))
        cover.recycle(panel)
        #expect(view.image == nil && !panel.isVisible)
    }

    @Test func thePoolKeepsOnePanelWhenTwoCoversReturn() throws {
        let screen = try screen()
        let first = cover.panel(on: screen)
        let second = cover.panel(on: screen)
        #expect(first !== second)
        cover.recycle(first)
        cover.recycle(second)
        let retained = cover.panel(on: screen)
        #expect(retained === first)
        cover.recycle(retained)
        cover.recycle(retained)
        let again = cover.panel(on: screen)
        #expect(again === retained)
        cover.recycle(again)
    }

    @Test func reuseAdaptsThePanelAndImageViewToTheDisplay() throws {
        let screen = try screen()
        cover.prewarm(on: screen)
        let narrower = Screen(id: screen.id, uuid: screen.uuid,
            frame: CGRect(origin: screen.frame.origin, size: CGSize(width: screen.frame.width / 2,
                                                                   height: screen.frame.height)),
            visible: screen.visible, isBuiltin: screen.isBuiltin, nsScreen: screen.nsScreen)
        let panel = cover.panel(on: narrower)
        #expect(panel.frame.width == narrower.frame.width)
        #expect(panel.contentView?.frame.width == narrower.frame.width)
        cover.recycle(panel)
        let restored = cover.panel(on: screen)
        #expect(restored === panel && restored.frame.width == screen.frame.width)
        #expect(restored.contentView?.frame.width == screen.frame.width)
        cover.recycle(restored)
    }
}
