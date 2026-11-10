@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct WorkspaceModelTests {
    @Test func theShownSetFollowsEveryChange() {
        var model = WorkspaceModel()
        #expect(!model.isShown("1"))
        model.show("1", on: "A")
        model.shown["B"] = "2"
        #expect(model.isShown("1") && model.isShown("2"))
        model.show("3", on: "A")
        #expect(!model.isShown("1") && model.isShown("3"))
        model.shown["B"] = nil
        #expect(!model.isShown("2"))
        model.shown = [:]
        #expect(!model.isShown("3"))
        #expect(!model.isShown(nil))
    }

    @Test func forgetRemovesEveryTraceOfAWindow() {
        var model = WorkspaceModel()
        model.assign(7, to: "1"); model.assign(8, to: "1")
        model.order = [7, 8]
        model.noteFocus(8); model.noteFocus(7)
        model.lastFocused["1"] = 7
        model.forget(7)
        #expect(model.workspaceOf[7] == nil)
        #expect(model.order == [8])
        #expect(model.focusStamps[7] == nil)
        #expect(model.focusOrder == [8])
        #expect(model.lastFocused["1"] == nil)
        #expect(model.mostRecent(of: [7]) == nil)
        #expect(model.mostRecent(of: [7, 8]) == 8)
    }

    @Test func noteFocusKeepsTheMostRecentFirst() {
        var model = WorkspaceModel()
        model.noteFocus(1); model.noteFocus(2); model.noteFocus(1)
        #expect(model.focusOrder == [1, 2])
        #expect(model.mostRecent(of: [1, 2]) == 1)
        let clock = model.focusClock
        model.noteFocus(1)
        #expect(model.focusClock == clock)
    }

    @Test func focusOrderIsCapped() {
        var model = WorkspaceModel()
        for id in 1...100 { model.noteFocus(CGWindowID(id)) }
        #expect(model.focusOrder.count == 80)
        #expect(model.focusOrder.first == 100)
    }

    @Test func swapExchangesTheTwoWorkspaces() {
        var model = WorkspaceModel()
        model.assign(1, to: "1"); model.assign(2, to: "2")
        model.swapWorkspaces(1, 2)
        #expect(model.workspaceOf[1] == "2" && model.workspaceOf[2] == "1")
    }

    @Test func forgettingAWindowReleasesItsFullscreenWorkspace() {
        var model = WorkspaceModel()
        let workspace = WindowManager.spaceWorkspace(display: "A", space: 5)
        model.assign(7, to: workspace); model.fullscreenHost[workspace] = 7
        model.forget(7)
        #expect(model.fullscreenHost[workspace] == nil && model.workspaceOf[7] == nil)
        model.fullscreenHost[workspace] = 8
        model.resetWorkspaces()
        #expect(model.fullscreenHost.isEmpty)
    }

    @Test func resetKeepsOrderAndFocusHistory() {
        var model = WorkspaceModel()
        model.assign(1, to: "1"); model.order = [1]; model.noteFocus(1)
        model.show("1", on: "A"); model.virtualShown["A"] = "1"; model.monitorOf["1"] = "A"; model.lastFocused["1"] = 1
        _ = model.states["1", default: ScreenState(layout: .tall)]
        model.resetWorkspaces()
        #expect(
            model.workspaceOf.isEmpty && model.shown.isEmpty && model.virtualShown.isEmpty
                && model.monitorOf.isEmpty && model.lastFocused.isEmpty
        )
        #expect(!model.isShown("1"))
        #expect(model.order == [1] && model.focusOrder == [1])
    }

    @Test func aSnapshotDoesNotChangeWithTheModel() {
        var model = WorkspaceModel()
        let state = ScreenState(layout: .tall)
        state.ratio = 0.6; state.mainCount = 2; state.zoomed = 4
        model.states["1"] = state
        model.assign(4, to: "1"); model.order = [4]; model.lastFocused["1"] = 4
        let snap = model.snapshot()
        state.layout = .bsp; state.ratio = 0.3
        model.assign(4, to: "2"); model.order = []; model.lastFocused["1"] = nil
        #expect(snap.states["1"]?.layout == .tall)
        #expect(snap.states["1"]?.ratio == 0.6)
        #expect(snap.states["1"]?.mainCount == 2)
        #expect(snap.states["1"]?.zoomed == 4)
        #expect(snap.workspaceOf[4] == "1")
        #expect(snap.order == [4])
        #expect(snap.lastFocused["1"] == 4)
    }

    @Test func aMaximisedTabJoinsItsGroupAgainWhenItComesBack() {
        var model = WorkspaceModel()
        for id: CGWindowID in [1, 2, 3] { model.assign(id, to: "1") }
        model.order = [1, 2, 3]
        model.joinTab(2, onto: 1)
        model.joinTab(3, onto: 2)
        let maximised = WindowManager.spaceWorkspace(display: "A", space: 5)
        model.hostMaximised(2, in: maximised)
        #expect(model.tabs.group(of: 1)?.members == [1, 3])
        #expect(model.rejoinMaximisedTabs { _ in true }.isEmpty)
        model.assign(2, to: "1")
        #expect(model.rejoinMaximisedTabs { _ in true } == [2])
        #expect(model.tabs.group(of: 2)?.members == [1, 2, 3])
        #expect(model.tabs.group(of: 2)?.active == 2)
        #expect(model.maximisedTabs.isEmpty)
    }

    @Test func aMaximisedTabStaysAloneWhenItsGroupIsGone() {
        var model = WorkspaceModel()
        for id: CGWindowID in [1, 2, 3] { model.assign(id, to: "1") }
        model.joinTab(2, onto: 1)
        model.joinTab(3, onto: 2)
        let maximised = WindowManager.spaceWorkspace(display: "A", space: 5)
        model.hostMaximised(2, in: maximised)
        model.leaveTab(3)
        model.assign(2, to: "2")
        #expect(model.rejoinMaximisedTabs { _ in true }.isEmpty)
        #expect(model.maximisedTabs.isEmpty)
        model.hostMaximised(1, in: maximised)
        model.forget(1)
        #expect(model.maximisedTabs.isEmpty && !model.tabs.isGrouped(2))
    }
}
