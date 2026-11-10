@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

private func plan(_ lanes: [[CGWindowID]], tabs: [[CGWindowID]]) -> SortPlan {
    let ids = lanes.flatMap(\.self)
    let items = ids.map { SortItem(id: $0, title: "\($0)", app: "App", bundleID: nil, icon: nil, recency: Int($0)) }
    let sortLanes = lanes.enumerated().map { SortLane(workspace: "\($0 + 1)", name: "", layout: .tall, ids: $1) }
    var sortPlan = SortPlan(display: "D", items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }),
                            lanes: sortLanes, existing: sortLanes.map(\.workspace), taken: [],
                            active: "1")
    sortPlan.tabs = tabs
    sortPlan.keepTabsTogether()
    return sortPlan
}

@Suite struct SortTabsTests {
    @Test func tabsStayTogetherWithTheActiveTabFirst() {
        let sortPlan = plan([[3, 1, 4], [2]], tabs: [[2, 3]])
        #expect(sortPlan.lanes.map(\.ids) == [[1, 4], [2, 3]])
        #expect(sortPlan.tiles(sortPlan.lanes[1].ids) == [2])
        #expect(sortPlan.tabBlocks([1, 4]) == [[1], [4]])
        #expect(sortPlan.tabBlocks(sortPlan.lanes[1].ids) == [[2, 3]])
    }

    @Test func placingTheGroupMovesEveryTab() {
        var sortPlan = plan([[1, 2, 3], [4]], tabs: [[1, 2]])
        sortPlan.placeTabs(1, inLane: 1)
        #expect(sortPlan.lanes.map(\.ids) == [[3], [4, 1, 2]])
    }

    @Test func anUntabbedTabMovesAloneAndTheGroupStays() {
        var sortPlan = plan([[1, 2, 3], [4]], tabs: [[1, 2]])
        sortPlan.untab(2)
        sortPlan.place(2, inLane: 1)
        #expect(sortPlan.lanes.map(\.ids) == [[1, 3], [4, 2]])
        #expect(sortPlan.tabs == [[1]])
        #expect(sortPlan.tabBlocks([1, 3]) == [[1], [3]])
        #expect(sortPlan.rowCount(sortPlan.lanes[0]) == 3)
    }

    @Test func aWindowJoinsAGroupInAnotherLane() {
        var sortPlan = plan([[1, 2, 3], [4]], tabs: [[1, 2]])
        sortPlan.joinTabs(4, onto: 1)
        #expect(sortPlan.lanes.map(\.ids) == [[1, 2, 4, 3], []])
        #expect(sortPlan.tabs == [[1, 2, 4]])
        #expect(sortPlan.tabBlocks(sortPlan.lanes[0].ids) == [[1, 2, 4], [3]])
    }

    @Test func reorderMovesTheGroupAsOneBlock() {
        var sortPlan = plan([[5, 1, 2, 3]], tabs: [[1, 2]])
        sortPlan.reorder(2, by: 1)
        #expect(sortPlan.lanes[0].ids == [5, 3, 1, 2])
        sortPlan.reorder(5, by: 1)
        #expect(sortPlan.lanes[0].ids == [3, 5, 1, 2])
    }

    @Test func aBatchMoveKeepsAGroupThatMovesTogether() {
        var model = WorkspaceModel()
        for id: CGWindowID in [1, 2, 3] { model.assign(id, to: "1") }
        model.order = [1, 2, 3]
        model.joinTab(2, onto: 1)
        model.assign([1: "2", 2: "2"])
        #expect(model.tabs.group(of: 1)?.members == [1, 2])
        #expect(model.workspaceOf[2] == "2")
    }

    @Test func aBatchMoveSplitsATabThatMovesAlone() {
        var model = WorkspaceModel()
        for id: CGWindowID in [1, 2, 3] { model.assign(id, to: "1") }
        model.order = [1, 2, 3]
        model.joinTab(2, onto: 1)
        model.joinTab(3, onto: 2)
        model.assign([3: "2"])
        #expect(model.tabs.group(of: 1)?.members == [1, 2])
        #expect(!model.tabs.isGrouped(3))
    }

    @Test func closedTabsShowAsOneGroup() {
        var sortPlan = plan([[1, 2, 3], [4]], tabs: [[1, 2]])
        [1, 2, 3].forEach { sortPlan.markClosing($0) }
        #expect(sortPlan.closeBlocks(sortPlan.close) == [[1, 2], [3]])
        #expect(sortPlan.closeRowCount == 4)
    }

    @Test func bringingBackOneClosedTabBringsBackTheGroup() {
        var sortPlan = plan([[1, 2, 3], [4]], tabs: [[1, 2]])
        sortPlan.markClosing(1)
        sortPlan.markClosing(2)
        sortPlan.restore(2, avoiding: [])
        #expect(sortPlan.close.isEmpty)
        #expect(sortPlan.lanes[0].ids == [1, 2, 3])
        #expect(sortPlan.tabs == [[1, 2]])
    }

    @Test func draggingAClosedGroupMovesEveryClosedTab() {
        var sortPlan = plan([[1, 2, 3], [4]], tabs: [[1, 2]])
        sortPlan.markClosing(1)
        sortPlan.markClosing(2)
        sortPlan.placeTabs(1, inLane: 1)
        sortPlan.keepTabsTogether()
        #expect(sortPlan.close.isEmpty)
        #expect(sortPlan.lanes[1].ids == [4, 1, 2])
    }
}
