@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WindowSpaceMoveTests {
    private final class Server {
        var spaces: [UInt64] = [1]
        var visible = false
        var accepted = true
        var submissions = 0
        var visibilityReads = 0
        var time = 0.0
        var pending: [(Double, () -> Void)] = []

        var move: WindowSpaceMove {
            WindowSpaceMove(membership: { self.spaces }, submit: {
                self.submissions += 1
                return self.accepted
            }, isOnScreen: {
                self.visibilityReads += 1
                return self.visible
            }, now: { self.time }, schedule: { self.pending.append(($0, $1)) })
        }

        func step() {
            let (delay, work) = pending.removeFirst()
            time += delay
            work()
        }
    }

    @Test func fastArrivalCompletesAtTheNextMillisecondCheck() {
        let server = Server()
        var results: [Bool] = []
        server.move.run(to: 2, waitUntilOnScreen: false) { results.append($0) }
        #expect(results.isEmpty && server.submissions == 1)
        server.spaces = [2]
        server.step()
        #expect(results == [true] && server.time == 0.001)
        #expect(server.visibilityReads == 0 && server.pending.isEmpty)
    }

    @Test func existingMembershipStillWaitsForVisibleArrival() {
        let server = Server()
        var results: [Bool] = []
        server.move.run(to: 1, waitUntilOnScreen: true) { results.append($0) }
        #expect(results.isEmpty && server.submissions == 0)
        server.step()
        #expect(results.isEmpty)
        server.visible = true
        server.step()
        #expect(results == [true] && server.pending.isEmpty)
    }

    @Test func visibleWindowMustAlsoReachTheTargetDesktop() {
        let server = Server()
        server.visible = true
        var results: [Bool] = []
        server.move.run(to: 2, waitUntilOnScreen: true) { results.append($0) }
        server.step()
        #expect(results.isEmpty && server.visibilityReads == 0)
        server.spaces = [2]
        server.step()
        #expect(results == [true] && server.visibilityReads == 1)
    }

    @Test func slowArrivalBacksOffAndStopsAtTheDeadline() {
        let server = Server()
        var results: [Bool] = []
        server.move.run(to: 2, waitUntilOnScreen: false) { results.append($0) }
        for _ in 0..<4 {
            #expect(server.pending.first?.0 == 0.001)
            server.step()
        }
        #expect(server.pending.first?.0 == 0.004)
        while !server.pending.isEmpty { server.step() }
        #expect(results == [false] && server.time == 0.5)
        #expect(server.submissions == 1)
    }

    @Test func rejectedMoveDoesNotStartPolling() {
        let server = Server()
        server.accepted = false
        var results: [Bool] = []
        server.move.run(to: 2, waitUntilOnScreen: false) { results.append($0) }
        #expect(results == [false] && server.pending.isEmpty && server.submissions == 1)
    }
}
