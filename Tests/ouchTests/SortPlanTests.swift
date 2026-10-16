// Tests: the Sort panel's plan, which the panel edits before the window manager applies it.
import CoreGraphics
import Testing
@testable import ouch

private func item(_ id: CGWindowID, _ app: String, title: String = "", bundle: String? = nil, recency: Int? = nil) -> SortItem {
    SortItem(id: id, title: title, app: app, bundleID: bundle, icon: nil, recency: recency ?? Int(id))
}

/// A display with workspaces "1" (windows 1, 2) and "2" (window 3), showing "1".
private func plan(items: [SortItem]? = nil, lanes: [SortLane]? = nil, taken: Set<String> = []) -> SortPlan {
    let items = items ?? [item(1, "Safari"), item(2, "Mail"), item(3, "Xcode")]
    let lanes = lanes ?? [SortLane(ws: "1", name: "", layout: .tall, ids: [1, 2]), SortLane(ws: "2", name: "", layout: .bsp, ids: [3])]
    return SortPlan(display: "D", items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }), lanes: lanes,
                    strategy: nil, existing: lanes.map(\.ws), taken: taken, active: "1")
}

@Suite struct SortPlanTests {
    @Test func workspacesSortNumericallyThenByName() {
        #expect(["10", "web", "2", "1", "chat"].sorted(by: SortPlan.order) == ["1", "2", "10", "chat", "web"])
    }

    @Test func availableNamesSkipUsedAndTakenOnes() {
        let p = plan(taken: ["3"])
        #expect(Array(p.available(avoiding: ["4"]).prefix(3)) == ["5", "6", "7"])
    }

    @Test func markClosingAndRestorePutsAWindowBackInItsPlace() {
        var p = plan()
        p.markClosing(1)
        #expect(p.isClosing(1))
        #expect(p.lanes[0].ids == [2])
        p.restore(1, avoiding: [])
        #expect(!p.isClosing(1))
        #expect(p.lanes[0].ids == [1, 2])
    }

    @Test func closeLaneAndReopenBringsTheWholeWorkspaceBack() {
        var p = plan()
        #expect(p.closeLane(at: 1) == 1)
        #expect(p.lanes.map(\.ws) == ["1"])
        #expect(p.close == [3])
        p.restore(3, avoiding: [])
        #expect(p.lanes.map(\.ws) == ["1", "2"])
        #expect(p.lanes[1].ids == [3])
        #expect(p.lanes[1].layout == .bsp)
        #expect(p.close.isEmpty)
    }

    @Test func theLastLaneCannotBeClosedOrRemoved() {
        var p = plan(lanes: [SortLane(ws: "1", name: "", layout: .tall, ids: [1, 2, 3])])
        #expect(p.closeLane(at: 0) == nil)
        #expect(p.removeLane(at: 0) == nil)
    }

    @Test func removeLaneMovesWindowsToTheLaneBefore() {
        var p = plan()
        let r = p.removeLane(at: 1)
        #expect(r?.target == 0 && r?.moved == 1)
        #expect(p.lanes[0].ids == [1, 2, 3])
    }

    @Test func mergeLaneKeepsTheTargetsName() {
        var p = plan()
        let r = p.mergeLane(0, into: 1)
        #expect(r?.target == 0)
        #expect(p.lanes.map(\.ws) == ["2"])
        #expect(p.lanes[0].ids == [3, 1, 2])
    }

    @Test func moveLaneKeepsNumbersInOrder() {
        var p = plan()
        #expect(p.moveLane(1, toSlot: 0) == 0)
        #expect(p.lanes.map(\.ws) == ["1", "2"])
        #expect(p.lanes[0].ids == [3])
        #expect(p.lanes[1].ids == [1, 2])
    }

    @Test func addLaneTakesTheFirstFreeNumberInOrder() {
        var p = plan(lanes: [SortLane(ws: "1", name: "", layout: .tall, ids: [1]), SortLane(ws: "3", name: "", layout: .tall, ids: [2, 3])])
        let i = p.addLane(layout: .bsp, avoiding: [])
        #expect(i == 1)
        #expect(p.lanes.map(\.ws) == ["1", "2", "3"])
    }

    @Test func renumberLaneUpdatesRememberedOrigins() {
        var p = plan()
        p.markClosing(3)
        p.renumberLane(0, to: "5")
        #expect(p.lanes.map(\.ws) == ["2", "5"])
        p.markClosing(1)
        #expect(p.origin[1]?.ws == "5")
    }

    @Test func duplicatesKeepTheMostRecentWindow() {
        let items = [item(1, "Finder", title: "Downloads", recency: 2), item(2, "Finder", title: "Downloads", recency: 0),
                     item(3, "Finder", title: "Desktop"), item(4, "Notes", title: "Untitled"), item(5, "Notes", title: "Untitled")]
        let p = plan(items: items, lanes: [SortLane(ws: "1", name: "", layout: .tall, ids: [1, 2, 3, 4, 5])])
        #expect(p.duplicates == [1])
        #expect(p.duplicateText == "Close 1 duplicate Finder window")
    }

    @Test func sortByAppGroupsTheBusiestAppFirst() {
        let items = [item(1, "Safari"), item(2, "Mail"), item(3, "Safari"), item(4, "Xcode")]
        var p = plan(items: items, lanes: [SortLane(ws: "1", name: "", layout: .tall, ids: [1, 2, 3, 4])])
        p.sort(by: .app, layouts: Layout.allCases, avoiding: [])
        #expect(p.lanes.first?.name == "Safari")
        #expect(p.lanes.first?.ids == [1, 3])
        #expect(p.lanes.flatMap(\.ids).sorted() == [1, 2, 3, 4])
        #expect(Set(p.lanes.map(\.ws)).count == p.lanes.count)
    }

    @Test func sortByFocusPutsThreeRecentWindowsFirst() {
        let items = (1...5).map { item(CGWindowID($0), "App\($0)") }
        var p = plan(items: items, lanes: [SortLane(ws: "1", name: "", layout: .tall, ids: [1, 2, 3, 4, 5])])
        p.sort(by: .focus, layouts: Layout.allCases, avoiding: [])
        #expect(p.lanes.map(\.ids) == [[1, 2, 3], [4, 5]])
        #expect(p.lanes[1].layout == .fullscreen)
    }

    @Test func layoutForCountFallsBackToTheFirstEnabledLayout() {
        #expect(SortPlan.layout(forCount: 2, in: Layout.allCases) == .column)
        #expect(SortPlan.layout(forCount: 2, in: [.wide, .tall]) == .wide)
    }

    @Test func appliedListsDroppedWorkspaces() {
        var p = plan()
        _ = p.mergeLane(1, into: 0)
        let a = p.applied
        #expect(a.lanes.map(\.name) == ["1"])
        #expect(Set(a.dropped) == ["1", "2"])
    }
}
