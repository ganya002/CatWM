import CoreGraphics
@testable import ouch
import Testing

private func item(
    _ id: CGWindowID,
    _ app: String,
    title: String = "",
    bundle: String? = nil,
    recency: Int? = nil
) -> SortItem {
    SortItem(id: id, title: title, app: app, bundleID: bundle, icon: nil, recency: recency ?? Int(id))
}

private func plan(items: [SortItem]? = nil, lanes: [SortLane]? = nil, taken: Set<String> = []) -> SortPlan {
    let items = items ?? [item(1, "Safari"), item(2, "Mail"), item(3, "Xcode")]
    let lanes = lanes ?? [
        SortLane(workspace: "1", name: "", layout: .tall, ids: [1, 2]),
        SortLane(workspace: "2", name: "", layout: .bsp, ids: [3])
    ]
    return SortPlan(display: "D", items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }), lanes: lanes,
                    strategy: nil, existing: lanes.map(\.workspace), taken: taken, active: "1")
}

@Suite struct SortPlanTests {
    @Test func workspacesSortNumericallyThenByName() {
        #expect(["10", "web", "2", "1", "chat"].sorted(by: SortPlan.order) == ["1", "2", "10", "chat", "web"])
    }

    @Test func availableNamesSkipUsedAndTakenOnes() {
        let sortPlan = plan(taken: ["3"])
        #expect(Array(sortPlan.available(avoiding: ["4"]).prefix(3)) == ["5", "6", "7"])
    }

    @Test func markClosingAndRestorePutsAWindowBackInItsPlace() {
        var sortPlan = plan()
        sortPlan.markClosing(1)
        #expect(sortPlan.isClosing(1))
        #expect(sortPlan.lanes[0].ids == [2])
        sortPlan.restore(1, avoiding: [])
        #expect(!sortPlan.isClosing(1))
        #expect(sortPlan.lanes[0].ids == [1, 2])
    }

    @Test func closeLaneAndReopenBringsTheWholeWorkspaceBack() {
        var sortPlan = plan()
        #expect(sortPlan.closeLane(at: 1) == 1)
        #expect(sortPlan.lanes.map(\.workspace) == ["1"])
        #expect(sortPlan.close == [3])
        sortPlan.restore(3, avoiding: [])
        #expect(sortPlan.lanes.map(\.workspace) == ["1", "2"])
        #expect(sortPlan.lanes[1].ids == [3])
        #expect(sortPlan.lanes[1].layout == .bsp)
        #expect(sortPlan.close.isEmpty)
    }

    @Test func theLastLaneCannotBeClosedOrRemoved() {
        var sortPlan = plan(lanes: [SortLane(workspace: "1", name: "", layout: .tall, ids: [1, 2, 3])])
        #expect(sortPlan.closeLane(at: 0) == nil)
        #expect(sortPlan.removeLane(at: 0) == nil)
    }

    @Test func removeLaneMovesWindowsToTheLaneBefore() {
        var sortPlan = plan()
        let removal = sortPlan.removeLane(at: 1)
        #expect(removal?.target == 0 && removal?.moved == 1)
        #expect(sortPlan.lanes[0].ids == [1, 2, 3])
    }

    @Test func mergeLaneKeepsTheTargetsName() {
        var sortPlan = plan()
        let merge = sortPlan.mergeLane(0, into: 1)
        #expect(merge?.target == 0)
        #expect(sortPlan.lanes.map(\.workspace) == ["2"])
        #expect(sortPlan.lanes[0].ids == [3, 1, 2])
    }

    @Test func moveLaneKeepsNumbersInOrder() {
        var sortPlan = plan()
        #expect(sortPlan.moveLane(1, toSlot: 0) == 0)
        #expect(sortPlan.lanes.map(\.workspace) == ["1", "2"])
        #expect(sortPlan.lanes[0].ids == [3])
        #expect(sortPlan.lanes[1].ids == [1, 2])
    }

    @Test func addLaneTakesTheFirstFreeNumberInOrder() {
        var sortPlan = plan(lanes: [
            SortLane(workspace: "1", name: "", layout: .tall, ids: [1]),
            SortLane(workspace: "3", name: "", layout: .tall, ids: [2, 3])
        ])
        let index = sortPlan.addLane(layout: .bsp, avoiding: [])
        #expect(index == 1)
        #expect(sortPlan.lanes.map(\.workspace) == ["1", "2", "3"])
    }

    @Test func renumberLaneUpdatesRememberedOrigins() {
        var sortPlan = plan()
        sortPlan.markClosing(3)
        sortPlan.renumberLane(0, to: "5")
        #expect(sortPlan.lanes.map(\.workspace) == ["2", "5"])
        sortPlan.markClosing(1)
        #expect(sortPlan.origin[1]?.workspace == "5")
    }

    @Test func duplicatesKeepTheMostRecentWindow() {
        let items = [
            item(1, "Finder", title: "Downloads", recency: 2),
            item(2, "Finder", title: "Downloads", recency: 0),
            item(3, "Finder", title: "Desktop"),
            item(4, "Notes", title: "Untitled"),
            item(5, "Notes", title: "Untitled")
        ]
        let sortPlan = plan(
            items: items,
            lanes: [SortLane(workspace: "1", name: "", layout: .tall, ids: [1, 2, 3, 4, 5])]
        )
        #expect(sortPlan.duplicates == [1])
        #expect(sortPlan.duplicateText == "Close 1 duplicate Finder window")
    }

    @Test func sortByAppGroupsTheBusiestAppFirst() {
        let items = [item(1, "Safari"), item(2, "Mail"), item(3, "Safari"), item(4, "Xcode")]
        var sortPlan = plan(
            items: items,
            lanes: [SortLane(workspace: "1", name: "", layout: .tall, ids: [1, 2, 3, 4])]
        )
        sortPlan.sort(by: .app, layouts: Layout.allCases, avoiding: [])
        #expect(sortPlan.lanes.first?.name == "Safari")
        #expect(sortPlan.lanes.first?.ids == [1, 3])
        #expect(sortPlan.lanes.flatMap(\.ids).sorted() == [1, 2, 3, 4])
        #expect(Set(sortPlan.lanes.map(\.workspace)).count == sortPlan.lanes.count)
    }

    @Test func sortByFocusPutsThreeRecentWindowsFirst() {
        let items = (1...5).map { item(CGWindowID($0), "App\($0)") }
        var sortPlan = plan(
            items: items,
            lanes: [SortLane(workspace: "1", name: "", layout: .tall, ids: [1, 2, 3, 4, 5])]
        )
        sortPlan.sort(by: .focus, layouts: Layout.allCases, avoiding: [])
        #expect(sortPlan.lanes.map(\.ids) == [[1, 2, 3], [4, 5]])
        #expect(sortPlan.lanes[1].layout == .fullscreen)
    }

    @Test func layoutForCountFallsBackToTheFirstEnabledLayout() {
        #expect(SortPlan.layout(forCount: 2, in: Layout.allCases) == .column)
        #expect(SortPlan.layout(forCount: 2, in: [.wide, .tall]) == .wide)
    }

    @Test func appliedListsDroppedWorkspaces() {
        var sortPlan = plan()
        _ = sortPlan.mergeLane(1, into: 0)
        let applied = sortPlan.applied
        #expect(applied.lanes.map(\.name) == ["1"])
        #expect(Set(applied.dropped) == ["1", "2"])
    }
}

@Suite struct SortFullscreenTests {
    private func plain() -> SortPlan {
        SortPlan(
            display: "D",
            items: [1: SortItem(id: 1, title: "", app: "Safari", bundleID: nil, icon: nil, recency: 1)],
            lanes: [
                SortLane(workspace: "1", name: "", layout: .tall, ids: [1]),
                SortLane(workspace: "2", name: "", layout: .tall, ids: [])
            ],
            strategy: nil, existing: ["1", "2"], taken: [], active: "1"
        )
    }

    @Test func adoptingAFullscreenWindowAddsItToThePlanAndALane() {
        var sortPlan = plain()
        let fullscreen = SortItem(id: 9, title: "Talk", app: "Keynote", bundleID: nil, icon: nil, recency: 2)
        sortPlan.adopt(fullscreen, inLane: 1)
        #expect(sortPlan.items[9]?.app == "Keynote")
        #expect(sortPlan.lanes[1].ids == [9])
        #expect(sortPlan.lane(of: 9) == 1)
    }

    @Test func movesNameTheWorkspaceOfEachListedWindow() {
        var sortPlan = plain()
        sortPlan.adopt(SortItem(id: 9, title: "", app: "Keynote", bundleID: nil, icon: nil, recency: 2), inLane: 1)
        #expect(sortPlan.moves(of: [9, 5]) == [9: "2"])
        #expect(sortPlan.moves(of: []).isEmpty)
    }
}
