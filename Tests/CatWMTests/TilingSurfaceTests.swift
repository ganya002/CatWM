import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

private final class RecordingSurface: TilingSurface {
    var hud: [String] = []
    var calls: [String] = []
    var inMode = false
    var showsTabDrop = false

    func start(_: WindowManager) {}
    func apply(_: Config) {}
    func showHUD(_ text: String, layout _: Layout?, on _: NSScreen?) { hud.append(text) }
    func warnHUD(_ text: String, on _: NSScreen?) { hud.append(text) }
    func leaveMode() {}
    var keybindsActive: Bool { false }
    var keysPaused: Bool { false }
    func setKeyTap(enabled _: Bool) {}
    func setKeyBinds(enabled _: Bool) {}
    func stop() {}
    func tilesDidChange(instant _: Bool) {}
    func splitSwapped(on _: String) {}
    func tabsDidChange(instant _: Bool) {}
    func batchTabChanges(_ changes: () -> Void) { changes() }
    func restackTabStrips() {}
    var revealedTabGroup: Int? { nil }
    func previewTabDrop(_: Window, at _: CGPoint) -> Bool { false }
    func endTabPreview(of _: CGWindowID) -> (group: Int, index: Int)? {
        calls.append("endTabPreview")
        return nil
    }
    func showTabDropHint(over _: CGRect, adding _: Window) {}
    func hideTabDropHint() { calls.append("hideTabDropHint") }
    func followTabStrip(_: Int, at _: CGVector, lowest _: CGFloat) {}
    func endTabStripFollow() {}
    var watchesTitles: Bool { false }
    func titleChanged(_: Window) {}
    func windowForgotten(_: CGWindowID) {}
    func abandonOverview() {}
    func toggleOverview() {}
    func undoOverview() {}
    func refreshed(_: [Screen]) {}
    func openSwitcher(backward _: Bool) {}
    func focusChanged() {}
    func toggleFocusEffect(_: FocusEffect) {}
    var loginItem: (enabled: Bool, needsApproval: Bool) { (false, false) }
    func preview(_: String, _: String) -> Bool { false }
}

@Suite struct TilingSurfaceTests {
    @Test @MainActor func theEngineRunsHeadlessByDefault() {
        #expect(WindowManager(config: .parse(defaultText)).surface is HeadlessSurface)
    }

    @Test @MainActor func toggleTilingShowsItsStateOnTheSurface() {
        let manager = WindowManager(config: .parse(defaultText))
        let surface = RecordingSurface()
        manager.surface = surface
        manager.toggleTiling()
        manager.toggleTiling()
        #expect(surface.hud == ["Tiling off", "Tiling on"])
    }

    @Test @MainActor func dispatchReadsTheModeFromTheSurface() {
        let manager = WindowManager(config: .parse(defaultText))
        let surface = RecordingSurface()
        manager.surface = surface
        var modes: [Bool] = []
        manager.onDispatch = { _, _, inMode in modes.append(inMode) }
        manager.dispatch("no-such-dispatcher", "")
        surface.inMode = true
        manager.dispatch("no-such-dispatcher", "")
        manager.dispatch("no-such-dispatcher", "", inMode: false)
        #expect(modes == [false, true, false])
    }

    @Test @MainActor func escapeCancelsAShownTabDrop() {
        let manager = WindowManager(config: .parse(defaultText))
        let surface = RecordingSurface()
        manager.surface = surface
        manager.drags[7] = false
        #expect(!manager.cancelTabDrop())
        surface.showsTabDrop = true
        #expect(manager.cancelTabDrop())
        #expect(surface.calls == ["endTabPreview", "hideTabDropHint"])
        #expect(!manager.tabUI.drag.allowsJoin)
    }
}

@Suite struct TabDragLifecycleTests {
    @Test func aCancelledDragCleansThePreviewAndANewDragCanJoin() {
        let drag = TabDrag()
        let surface = RecordingSurface()
        #expect(drag.beginLifted(7))
        #expect(drag.cancelDrop(on: surface) == 7)
        #expect(drag.cancelDrop(on: surface) == nil)
        #expect(surface.calls == ["endTabPreview", "hideTabDropHint"])
        #expect(!drag.finish(7, on: surface).allowsJoin)
        #expect(drag.lifted == nil)
        #expect(drag.beginLifted(8))
        #expect(drag.finish(8, on: surface).allowsJoin)
    }

    @Test func finishingADragDiscardsItsPendingHover() {
        let drag = TabDrag()
        var pending: DispatchWorkItem?
        var hints = 0
        drag.beginLifted(7)
        drag.track(9, schedule: { pending = $0 }, changed: { hints += 1 })
        drag.finish(7, on: HeadlessSurface())
        pending?.perform()
        #expect(hints == 0)
        #expect(drag.hover == nil)
    }
}
