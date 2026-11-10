@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct WorkspaceReconciliationTests {
    private let displayA = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let displayB = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    private func observation(frames: [CGWindowID: CGRect], held: Set<CGWindowID> = []) -> WorkspaceObservation {
        WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1]),
                                        .init(id: "B", frame: displayB, space: 2, spaces: [2])],
                             frames: frames, present: Set(frames.keys), held: held)
    }

    @Test func fiftyWindowsProduceAReplayableSwitchPlan() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "2", "B": "3"]
        model.monitorOf = ["1": "A", "2": "A", "3": "B"]
        var frames: [CGWindowID: CGRect] = [:]
        for id in CGWindowID(1)...50 {
            model.assign(id, to: id <= 25 ? "1" : "2")
            model.order.append(id)
            frames[id] = id <= 25 ? displayA : CGRect(x: 999, y: 799, width: 500, height: 400)
        }
        let facts = observation(frames: frames)
        let first = WorkspaceReconciliation.reconcile(
            facts, model: model, virtual: true, homeSpace: [:], displayOf: [:]
        )
        let replay = WorkspaceReconciliation.reconcile(
            facts, model: model, virtual: true, homeSpace: [:], displayOf: [:]
        )
        #expect(first.visible == Set(26...50))
        #expect(first.park == Set(1...25))
        #expect(first.visible == replay.visible && first.park == replay.park)
        #expect(first.model.workspaceOf == model.workspaceOf)
        #expect(model.shown.isEmpty)
        #expect(first.homeSpace == ["A": 1, "B": 2])
    }

    @Test func externalMovesJoinTheDestinationWorkspace() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "1", "B": "2"]
        model.monitorOf = ["1": "A", "2": "B"]
        model.assign(7, to: "1")
        let result = WorkspaceReconciliation.reconcile(observation(frames: [7: displayB]), model: model, virtual: true,
                                                       homeSpace: [:], displayOf: [7: "A"])
        #expect(result.model.workspaceOf[7] == "2")
        #expect(result.displayOf[7] == "B")
    }

    @Test func inFlightMovesKeepTheirWorkspace() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "1", "B": "2"]
        model.monitorOf = ["1": "A", "2": "B"]
        model.assign(7, to: "1")
        let result = WorkspaceReconciliation.reconcile(
            observation(frames: [7: displayB], held: [7]), model: model, virtual: true,
            homeSpace: [:], displayOf: [7: "A"]
        )
        #expect(result.model.workspaceOf[7] == "1")
        #expect(result.displayOf[7] == "A")
    }

    @Test func disconnectedDisplaysAndUnknownFramesUseTheRemainingDisplay() {
        var model = WorkspaceModel()
        model.virtualShown = ["gone": "1"]
        model.monitorOf = ["1": "gone"]
        model.assign(7, to: "1")
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                         frames: [7: .null, 8: .null], present: [7, 8], held: [])
        let result = WorkspaceReconciliation.reconcile(
            facts, model: model, virtual: true, homeSpace: [:], displayOf: [:]
        )
        #expect(result.model.virtualShown == ["A": "1"])
        #expect(result.model.monitorOf["1"] == "A")
        #expect(result.model.workspaceOf[8] == "1")
        #expect(result.visible == [7, 8])
    }

    @Test func rehomedTabsOnDifferentDisplaysSeparate() {
        var model = WorkspaceModel()
        for id: CGWindowID in [7, 8] { model.assign(id, to: "removed") }
        model.joinTab(8, onto: 7)
        let result = WorkspaceReconciliation.reconcile(
            observation(frames: [7: displayA, 8: displayB]), model: model, virtual: false,
            homeSpace: [:], displayOf: [:])
        #expect(result.model.workspaceOf[7] == result.model.shown["A"])
        #expect(result.model.workspaceOf[8] == result.model.shown["B"])
        #expect(result.model.tabs.isEmpty)
        #expect(result.visible == [7, 8])
    }

    @Test func fullscreenWindowsJoinTheWorkspaceOfTheirOwnSpace() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "1"]
        model.monitorOf = ["1": "A"]
        model.assign(7, to: "1")
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1, 5])],
                                         frames: [8: displayA], present: [8], held: [], fullscreen: [7: 5])
        let result = WorkspaceReconciliation.reconcile(
            facts, model: model, virtual: true, homeSpace: [:], displayOf: [:]
        )
        let workspace = WindowManager.spaceWorkspace(display: "A", space: 5)
        #expect(result.model.workspaceOf[7] == workspace)
        #expect(result.model.fullscreenHost[workspace] == 7)
        #expect(result.model.monitorOf[workspace] == "A")
        #expect(result.model.fullscreenHost["1"] == nil)
        #expect(result.visible == [8])
        #expect(!result.park.contains(7))
    }

    @Test func fullscreenWorkspaceIsShownWhileItsSpaceIsCurrent() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "1"]
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 5, spaces: [1, 5])],
                                         frames: [:], present: [], held: [], fullscreen: [7: 5])
        let result = WorkspaceReconciliation.reconcile(
            facts, model: model, virtual: true, homeSpace: ["A": 1], displayOf: [:]
        )
        let workspace = WindowManager.spaceWorkspace(display: "A", space: 5)
        #expect(result.model.shown["A"] == workspace)
        #expect(result.model.isShown(result.model.workspaceOf[7]))
    }

    @Test func leavingFullscreenReturnsTheWindowToTheShownWorkspace() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "1"]
        model.monitorOf = ["1": "A"]
        let stale = WindowManager.spaceWorkspace(display: "A", space: 5)
        model.assign(7, to: stale)
        model.fullscreenHost[stale] = 7
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                         frames: [7: displayA], present: [7], held: [])
        let result = WorkspaceReconciliation.reconcile(
            facts, model: model, virtual: true, homeSpace: [:], displayOf: [:]
        )
        #expect(result.model.workspaceOf[7] == "1")
        #expect(result.model.fullscreenHost.isEmpty)
        #expect(result.visible == [7])
    }

    @Test func fullscreenWindowsOnUnknownSpacesStayUnassigned() {
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                         frames: [:], present: [], held: [], fullscreen: [7: 9])
        let result = WorkspaceReconciliation.reconcile(
            facts, model: WorkspaceModel(), virtual: true, homeSpace: [:], displayOf: [:]
        )
        #expect(result.model.workspaceOf[7] == nil)
        #expect(result.model.fullscreenHost.isEmpty)
    }

    @Test func aTabThatGoesFullscreenJoinsItsGroupAgainWhenItLeaves() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "1"]
        model.monitorOf = ["1": "A"]
        model.assign(7, to: "1"); model.assign(8, to: "1")
        model.joinTab(8, onto: 7)
        let entering = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1, 5])],
                                            frames: [7: displayA], present: [7], held: [], fullscreen: [8: 5])
        var result = WorkspaceReconciliation.reconcile(
            entering, model: model, virtual: true, homeSpace: [:], displayOf: [:]
        )
        #expect(!result.model.tabs.isGrouped(8))
        let leaving = WorkspaceObservation(displays: [.init(id: "A", frame: displayA, space: 1, spaces: [1])],
                                           frames: [7: displayA, 8: displayA], present: [7, 8], held: [])
        result = WorkspaceReconciliation.reconcile(
            leaving, model: result.model, virtual: true, homeSpace: [:], displayOf: [:]
        )
        model = result.model
        #expect(model.rejoinMaximisedTabs { _ in true } == [8])
        #expect(model.tabs.group(of: 7)?.members == [7, 8])
    }
}
