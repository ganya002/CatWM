@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct FocusRequestLifecycleTests {
    @Test func aReplyFromAnOlderObservationCannotConfirmNewState() {
        var focus = FocusRequests()
        let first = focus.beginObservation(pid: -1)
        let second = focus.beginObservation(pid: -1)
        #expect(first.shouldRead)
        #expect(!second.shouldRead)
        let accepted = focus.finishObservation(pid: -1, generation: first.generation)
        #expect(!accepted)
        let next = focus.beginObservation(pid: -1)
        #expect(next.shouldRead)
    }

    @Test func anOldWriteCannotExecuteANewerRequest() {
        var focus = FocusRequests()
        let old = focus.begin(id: 7, pid: -1, origin: -1)
        let current = focus.begin(id: 8, pid: -1, origin: -1)
        let executedOld = focus.executed(old)
        let executedCurrent = focus.executed(current)
        #expect(!executedOld)
        #expect(executedCurrent)
        let confirmedOld = focus.confirm(7)
        #expect(!confirmedOld)
        #expect(focus.pendingFocus?.id == 8)
        let confirmedCurrent = focus.confirm(8)
        #expect(confirmedCurrent)
        #expect(focus.pendingFocus == nil)
    }

    @Test func changingAppInvalidatesRequestsAndDeferredCommands() {
        var focus = FocusRequests()
        focus.begin(id: 7, pid: -1, origin: -1)
        focus.enqueue(.init(pid: -1, dispatcher: "minimize", arg: "", inMode: false))
        focus.waitToRefocus(on: "1", pid: -1)
        let observation = focus.beginObservation(pid: -2)
        #expect(observation.cancelledRequest)
        #expect(!focus.needsObservation)
        #expect(focus.pendingFocus == nil)
        let commands = focus.takeCommands()
        let waiting = focus.takeWaitingRefocus()
        #expect(commands.isEmpty)
        #expect(waiting == nil)
    }
}
