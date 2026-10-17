import CoreGraphics
import Testing
@testable import ouch

@Suite struct WorkspaceReconciliationTests {
    private let a = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let b = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    private func observation(frames: [CGWindowID: CGRect], held: Set<CGWindowID> = []) -> WorkspaceObservation {
        WorkspaceObservation(displays: [.init(id: "A", frame: a, space: 1, spaces: [1]),
                                        .init(id: "B", frame: b, space: 2, spaces: [2])],
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
            frames[id] = id <= 25 ? a : CGRect(x: 999, y: 799, width: 500, height: 400)
        }
        let facts = observation(frames: frames)
        let first = WorkspaceReconciliation.reconcile(facts, model: model, virtual: true, homeSpace: [:], displayOf: [:])
        let replay = WorkspaceReconciliation.reconcile(facts, model: model, virtual: true, homeSpace: [:], displayOf: [:])
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
        let result = WorkspaceReconciliation.reconcile(observation(frames: [7: b]), model: model, virtual: true,
                                                       homeSpace: [:], displayOf: [7: "A"])
        #expect(result.model.workspaceOf[7] == "2")
        #expect(result.displayOf[7] == "B")
    }

    @Test func inFlightMovesKeepTheirWorkspace() {
        var model = WorkspaceModel()
        model.virtualShown = ["A": "1", "B": "2"]
        model.monitorOf = ["1": "A", "2": "B"]
        model.assign(7, to: "1")
        let result = WorkspaceReconciliation.reconcile(observation(frames: [7: b], held: [7]), model: model, virtual: true,
                                                       homeSpace: [:], displayOf: [7: "A"])
        #expect(result.model.workspaceOf[7] == "1")
        #expect(result.displayOf[7] == "A")
    }

    @Test func disconnectedDisplaysAndUnknownFramesUseTheRemainingDisplay() {
        var model = WorkspaceModel()
        model.virtualShown = ["gone": "1"]
        model.monitorOf = ["1": "gone"]
        model.assign(7, to: "1")
        let facts = WorkspaceObservation(displays: [.init(id: "A", frame: a, space: 1, spaces: [1])],
                                         frames: [7: .null, 8: .null], present: [7, 8], held: [])
        let result = WorkspaceReconciliation.reconcile(facts, model: model, virtual: true, homeSpace: [:], displayOf: [:])
        #expect(result.model.virtualShown == ["A": "1"])
        #expect(result.model.monitorOf["1"] == "A")
        #expect(result.model.workspaceOf[8] == "1")
        #expect(result.visible == [7, 8])
    }
}
