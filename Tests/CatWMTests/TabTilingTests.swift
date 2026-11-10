import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct TabTilingTests {
    @MainActor private func manager(on screen: Screen, windows ids: [CGWindowID]) -> WindowManager {
        let manager = WindowManager(config: .parse(defaultText))
        manager.config.windowMargins = false
        manager.shown[screen.uuid] = "1"
        for id in ids {
            let window = Window(id: id, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
            manager.windows[id] = window
            manager.order.append(id)
            manager.model.assign(id, to: "1")
            manager.visible.insert(id)
        }
        return manager
    }

    @Test @MainActor func tabsShareOneTileBelowTheirStrip() throws {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2, 3])
        manager.model.joinTab(3, onto: 1)
        #expect(manager.tiled(on: screen) == [3, 2])
        #expect(manager.tabStack(behind: 3) == [1])
        #expect(manager.tabStack(behind: 2).isEmpty)
        let slots = try #require(manager.layoutTargets([3, 2], manager.state(for: screen), on: screen))
        let slot = try #require(slots[3])
        let tile = manager.belowTabStrip(slot, for: 3)
        #expect(tile.minY == slot.minY + TabGeometry.stripHeight)
        #expect(tile.maxY == slot.maxY && tile.width == slot.width)
        #expect(manager.belowTabStrip(slot, for: 2) == slot)
    }

    @Test @MainActor func anAutoHiddenGroupFillsItsWholeSlot() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2])
        manager.model.joinTab(2, onto: 1)
        let slot = CGRect(x: 0, y: 40, width: 800, height: 600)
        #expect(manager.belowTabStrip(slot, for: 2).minY == slot.minY + TabGeometry.stripHeight)
        manager.config.autoHideTabStrip = true
        #expect(manager.belowTabStrip(slot, for: 1) == slot)
        #expect(manager.belowTabStrip(slot, for: 2) == slot)
    }

    @Test @MainActor func aDroppedGroupJoinsAsAWhole() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2, 3])
        manager.model.joinTab(2, onto: 1)
        manager.joinTabs(of: 2, onto: 3)
        #expect(manager.tabs.group(of: 3)?.members.sorted() == [1, 2, 3])
        #expect(manager.tabs.group(of: 3)?.active == 2)
    }

    @Test @MainActor func aLiftedTabJoinsAWindowOnlyAfterAHoverOverItsBody() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2, 3, 4])
        manager.model.joinTab(2, onto: 1)
        manager.model.joinTab(4, onto: 1)
        let slot = CGRect(x: screen.visible.minX + 600, y: screen.visible.minY + 40, width: 500, height: 500)
        let body = CGPoint(x: slot.midX, y: slot.midY)
        manager.targets[3] = slot
        manager.tabUI.drag.beginLifted(2)
        manager.tabUI.drag.track(3, schedule: { $0.perform() }, changed: {})
        manager.dropTab(2, at: body)
        #expect(manager.tabs.group(of: 3)?.members.contains(2) == true)
        #expect(manager.tabs.group(of: 1)?.members == [1, 4])
        manager.tabUI.drag.beginLifted(4)
        manager.tabUI.drag.track(3, schedule: { _ in }, changed: {})
        manager.dropTab(4, at: body)
        #expect(manager.tabs.group(of: 3)?.members.contains(4) == false)
    }

    @Test @MainActor func aLiftedTabHeldOverItsOwnGroupStaysInIt() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2, 3])
        manager.model.joinTab(2, onto: 1)
        manager.model.joinTab(3, onto: 1)
        let slot = CGRect(x: screen.visible.minX + 600, y: screen.visible.minY + 40, width: 500, height: 500)
        manager.targets[1] = slot
        manager.tabUI.drag.beginLifted(2)
        manager.tabUI.drag.track(1, schedule: { $0.perform() }, changed: {})
        #expect(manager.settledTabHover(for: 2, at: CGPoint(x: slot.midX, y: slot.midY)) == 1)
        manager.dropTab(2, at: CGPoint(x: slot.midX, y: slot.midY))
        #expect(manager.tabs.group(of: 1)?.members.sorted() == [1, 2, 3])
        manager.tabUI.drag.track(1, schedule: { $0.perform() }, changed: {})
        #expect(manager.settledTabHover(for: 2, at: CGPoint(x: slot.midX, y: slot.midY)) == 1)
        #expect(manager.settledTabHover(for: 1, at: CGPoint(x: slot.midX, y: slot.midY)) == nil)
    }

    @Test @MainActor func aHiddenTabStaysPutWhileTheActiveTabCoversIt() throws {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2])
        let tab = try #require(manager.windows[2])
        let slot = CGRect(x: 100, y: 68, width: 500, height: 600)
        #expect(!manager.covered(tab, by: slot))
        tab.remember(slot)
        #expect(manager.covered(tab, by: CGRect(x: 100, y: 38, width: 500, height: 630)))
        #expect(!manager.covered(tab, by: CGRect(x: 100, y: 98, width: 500, height: 570)))
        #expect(!manager.covered(tab, by: CGRect(x: 700, y: 68, width: 500, height: 600)))
    }

    @Test @MainActor func escapeOnlyActsWhileADropShows() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2])
        #expect(!manager.cancelTabDrop())
        manager.drags[2] = false
        #expect(!manager.cancelTabDrop())
        manager.drags = [:]
        manager.tabUI.drag.beginLifted(2)
        #expect(!manager.cancelTabDrop())
        #expect(manager.tabUI.drag.allowsJoin)
    }

    @Test @MainActor func aCancelledDropLeavesTheLiftedTabOutOfAnyGroup() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2, 3])
        manager.model.joinTab(2, onto: 1)
        let slot = CGRect(x: screen.visible.minX + 600, y: screen.visible.minY + 40, width: 500, height: 500)
        manager.targets[3] = slot
        manager.tabUI.drag.beginLifted(2)
        manager.tabUI.drag.track(3, schedule: { $0.perform() }, changed: {})
        _ = manager.tabUI.drag.cancelDrop(on: manager.surface)
        manager.dropTab(2, at: CGPoint(x: slot.midX, y: slot.minY + 10))
        #expect(manager.tabs.group(of: 2) == nil)
        #expect(manager.tabs.group(of: 3) == nil)
        #expect(manager.tabUI.drag.allowsJoin)
    }

    @Test @MainActor func aGroupNeedsRoomForItsLargestTabAndItsStrip() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2])
        manager.minSizes[1] = CGSize(width: 500, height: 300)
        manager.minSizes[2] = CGSize(width: 400, height: 420)
        manager.model.joinTab(2, onto: 1)
        #expect(manager.slotMinimum(2) == CGSize(width: 500, height: 420 + TabGeometry.stripHeight))
    }

    @Test @MainActor func droppingOnTheTopOfATileAddsATab() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2])
        let slot = CGRect(x: screen.visible.minX, y: screen.visible.minY + 40, width: 600, height: 500)
        manager.targets[1] = slot
        #expect(manager.tabDropTarget(for: 2, at: CGPoint(x: slot.midX, y: slot.minY + 10)) == 1)
        #expect(manager.tabDropTarget(for: 2, at: CGPoint(x: slot.midX, y: slot.midY)) == nil)
        #expect(manager.tabDropTarget(for: 1, at: CGPoint(x: slot.midX, y: slot.minY + 10)) == nil)
        manager.model.joinTab(2, onto: 1)
        manager.targets[2] = slot
        #expect(manager.tabDropTarget(for: 2, at: CGPoint(x: slot.midX, y: slot.minY + 10)) == nil)
    }

    @Test @MainActor func aTabMovesOnePlaceAndStopsAtTheEnds() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2, 3])
        manager.model.joinTab(2, onto: 1)
        manager.model.joinTab(3, onto: 2)
        manager.moveTab(3, by: -1)
        #expect(manager.tabs.group(of: 1)?.members == [1, 3, 2])
        manager.moveTab(3, by: -1)
        manager.moveTab(3, by: -1)
        #expect(manager.tabs.group(of: 1)?.members == [3, 1, 2])
        manager.moveTab(2, by: 1)
        #expect(manager.tabs.group(of: 1)?.members == [3, 1, 2])
        #expect(manager.tabs.group(of: 1)?.active == 3)
    }

    @Test @MainActor func focusingAHiddenTabShowsIt() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2])
        manager.model.joinTab(2, onto: 1)
        manager.followTabFocus(1)
        #expect(manager.tabs.group(of: 1)?.active == 1)
        #expect(manager.tiled(on: screen) == [1])
    }

    @Test @MainActor func aFloatingTabLeavesItsGroup() {
        guard let screen = Screen.all().first else { return }
        let manager = manager(on: screen, windows: [1, 2, 3])
        manager.model.joinTab(2, onto: 1)
        manager.model.joinTab(3, onto: 1)
        manager.windows[3]?.userFloating = .chosen(true)
        manager.settleTabs()
        #expect(manager.tabs.group(of: 1)?.members == [1, 2])
        #expect(manager.tabs.group(of: 1)?.active == 1)
    }
}
