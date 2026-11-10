import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

private final class TitleSurface: TilingSurface {
    var titles: [CGWindowID] = []
    var tabChanges = 0
    var inMode = false
    var showsTabDrop = false
    func start(_: WindowManager) {}
    func apply(_: Config) {}
    func showHUD(_: String, layout _: Layout?, on _: NSScreen?) {}
    func warnHUD(_: String, on _: NSScreen?) {}
    func leaveMode() {}
    var keybindsActive: Bool { false }
    var keysPaused: Bool { false }
    func setKeyTap(enabled _: Bool) {}
    func setKeyBinds(enabled _: Bool) {}
    func stop() {}
    func tilesDidChange(instant _: Bool) {}
    func splitSwapped(on _: String) {}
    func tabsDidChange(instant _: Bool) { tabChanges += 1 }
    func batchTabChanges(_ changes: () -> Void) { changes() }
    func restackTabStrips() {}
    var revealedTabGroup: Int? { nil }
    func previewTabDrop(_: Window, at _: CGPoint) -> Bool { false }
    func endTabPreview(of _: CGWindowID) -> (group: Int, index: Int)? { nil }
    func showTabDropHint(over _: CGRect, adding _: Window) {}
    func hideTabDropHint() {}
    func followTabStrip(_: Int, at _: CGVector, lowest _: CGFloat) {}
    func endTabStripFollow() {}
    var watchesTitles: Bool { false }
    func titleChanged(_ window: Window) { titles.append(window.id) }
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

@Suite(.timeLimit(.minutes(1))) @MainActor struct TabTitleTests {
    @Test func aGroupSurvivesTitleChanges() async throws {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager { _ in }
        let surface = TitleSurface()
        manager.surface = surface
        let host = fake.addWindow(title: "One")
        let tab = fake.addWindow(title: "Two")
        #expect(await fake.settle(manager))
        manager.joinTab(tab, onto: host)
        #expect(await fake.settle(manager))
        let members = try #require(manager.tabs.group(of: host)?.members.sorted())
        #expect(members == [host, tab])
        let frames = [fake.frame(of: host), fake.frame(of: tab)]
        for title in [nil, "", "Two", "Settings", "Two"] as [String?] {
            fake.setTitle(tab, title)
            manager.refresh()
            #expect(await fake.settle(manager))
            #expect(manager.windows[tab]?.title == title, "title \(String(describing: title))")
            #expect(manager.tabs.group(of: host)?.members.sorted() == [host, tab],
                    "group after \(String(describing: title))")
            #expect(manager.windows[tab]?.isFloating == false, "floating after \(String(describing: title))")
            #expect([fake.frame(of: host), fake.frame(of: tab)] == frames, "frames after \(String(describing: title))")
        }
        #expect(surface.titles.contains(tab))
    }
}
