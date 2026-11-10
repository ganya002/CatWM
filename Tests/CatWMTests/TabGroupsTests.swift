@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct TabGroupsTests {
    @Test func joiningMakesTheNewWindowTheActiveTabNextToItsHost() {
        var tabs = TabGroups()
        tabs.join(2, onto: 1)
        tabs.join(3, onto: 1)
        #expect(tabs.group(of: 1)?.members == [1, 3, 2])
        #expect(tabs.group(of: 1)?.active == 3)
        #expect(tabs.isBehind(1) && tabs.isBehind(2) && !tabs.isBehind(3))
        #expect(tabs.groups.count == 1)
    }

    @Test func removingTheActiveTabHandsItToTheNextOneAndALastTabDissolves() {
        var tabs = TabGroups()
        tabs.join(2, onto: 1)
        tabs.join(3, onto: 2)
        #expect(tabs.group(of: 1)?.members == [1, 2, 3])
        #expect(tabs.remove(3) == 2)
        #expect(tabs.group(of: 1)?.active == 2)
        tabs.remove(1)
        #expect(tabs.isEmpty)
        #expect(!tabs.isGrouped(2))
    }

    @Test func closingTheActiveTabShowsTheTabOnItsLeftElseOnItsRight() {
        var tabs = TabGroups()
        tabs.join(2, onto: 1)
        tabs.join(3, onto: 2)
        tabs.join(4, onto: 3)
        #expect(tabs.group(of: 1)?.members == [1, 2, 3, 4])
        tabs.activate(3)
        #expect(tabs.heir(of: 3) == 2)
        #expect(tabs.remove(3) == 2)
        tabs.activate(1)
        #expect(tabs.heir(of: 1) == 2)
        #expect(tabs.remove(1) == 2)
    }

    @Test func neighborsWrapAndTabsReorder() {
        var tabs = TabGroups()
        tabs.join(2, onto: 1)
        tabs.join(3, onto: 2)
        #expect(tabs.neighbor(of: 3, offset: 1) == 1)
        #expect(tabs.neighbor(of: 1, offset: -1) == 3)
        tabs.move(1, to: 2)
        #expect(tabs.group(of: 1)?.members == [2, 3, 1])
        #expect(tabs.neighbor(of: 9, offset: 1) == nil)
    }

    @Test func groupsKeepTheirIdentityWhileMembersChange() throws {
        var tabs = TabGroups()
        tabs.join(2, onto: 1)
        let id = try #require(tabs.group(of: 1)?.id)
        tabs.join(3, onto: 1)
        tabs.remove(1)
        #expect(tabs.group(of: 3)?.id == id)
        tabs.join(5, onto: 4)
        #expect(tabs.group(of: 5)?.id != id)
    }

    @Test func theActiveTabHoldsTheTileOfItsGroup() {
        var model = WorkspaceModel()
        model.order = [1, 2, 3]
        model.joinTab(3, onto: 1)
        #expect(model.order == [3, 1, 2])
        model.activateTab(1)
        #expect(model.order == [1, 3, 2])
        model.leaveTab(1)
        #expect(model.order == [3, 1, 2])
        #expect(!model.tabs.isGrouped(3))
    }

    @Test func savedTabsComeBackInTheirOrderWithTheirActiveTab() throws {
        let saved = SavedTabs(members: [.init(id: 4, pid: 10), .init(id: 2, pid: 10), .init(id: 7, pid: 11)], active: 2)
        #expect(SavedTabs(saved.line) == saved)
        #expect(SavedTabs("4@10 > 4") == nil)
        #expect(SavedTabs("nonsense") == nil)
        var model = WorkspaceModel()
        model.order = [9, 4, 2, 7]
        model.restoreTabs([4, 2, 7], active: 2)
        let group = try #require(model.tabs.group(of: 4))
        #expect(group.members == [4, 2, 7] && group.active == 2)
        #expect(model.order.filter { !model.tabs.isBehind($0) } == [9, 2])
    }

    @Test func movingATabToAnotherWorkspaceTakesItOutOfItsTabs() {
        var model = WorkspaceModel()
        for id: CGWindowID in [1, 2, 3] { model.assign(id, to: "1") }
        model.order = [1, 2, 3]
        model.joinTab(2, onto: 1)
        model.joinTab(3, onto: 1)
        model.assign(3, to: "1")
        #expect(model.tabs.group(of: 1)?.members.count == 3)
        model.assign(3, to: "2")
        #expect(model.tabs.group(of: 1)?.members == [1, 2])
        #expect(model.tabs.group(of: 1)?.active == 1)
        model.assign(4, to: "2")
        model.order.append(4)
        model.joinTab(4, onto: 1)
        model.assign(4, to: "1")
        #expect(model.tabs.group(of: 1)?.members == [1, 4, 2])
        model.forget(4)
        model.forget(2)
        #expect(model.tabs.isEmpty)
        #expect(model.order == [1, 3])
    }
}
