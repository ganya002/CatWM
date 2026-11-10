import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct NativeWindowMovesTests {
    @Test func creationThenMoveRetainsMembershipUntilObservationCatchesUp() {
        var moves = NativeWindowMoves()
        moves.requestWorkspace(1, workspace: "2")
        #expect(moves.isBusy(1))
        #expect(!moves.isMoving(1))
        #expect(moves.requestedWorkspace(1) == "2")
        moves.begin(1)
        #expect(moves.isMoving(1))
        #expect(moves.requestedWorkspace(1) == nil)
        moves.finish(1, on: 20)
        #expect(moves.isEmpty)
        #expect(moves.observedMembership(1, observed: [10]) == [20])
        #expect(moves.observedMembership(1, observed: [20]) == [20])
        #expect(moves.observedMembership(1, observed: [30]) == [30])
    }

    @Test func failureReleasesTheMoveWithoutClaimingItsDestination() {
        var moves = NativeWindowMoves()
        moves.requestWorkspace(1, workspace: "2")
        moves.cancelRequest(1)
        #expect(moves.isEmpty)
        moves.begin(1)
        moves.cancelRequest(1)
        #expect(moves.isMoving(1))
        moves.finish(1)
        #expect(moves.isEmpty)
        #expect(moves.observedMembership(1, observed: [10]) == [10])
    }

    @Test func idleCancelsQueuedFollowMovesButPreservesIndependentMoves() {
        var moves = NativeWindowMoves()
        let window = Window(id: 1, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        moves.follow(.init(window: window, workspace: "2", space: 20, from: "1"))
        moves.begin(2)
        moves.requestWorkspace(3, workspace: "4")
        #expect(moves.following(to: "2").keys.sorted() == [1])
        #expect(moves.movingIDs == [1, 2])
        moves.desktopBecameIdle()
        #expect(!moves.isBusy(1))
        #expect(moves.isMoving(2))
        #expect(moves.requestedWorkspace(3) == "4")
        #expect(moves.following(to: "2").isEmpty)
    }

    @Test func completedFollowMovesDeliverTheirFramesOnce() {
        var moves = NativeWindowMoves()
        let window = Window(id: 1, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        let frame = CGRect(x: 10, y: 20, width: 500, height: 400)
        moves.follow(.init(window: window, workspace: "2", space: 20, from: "1"))
        moves.begin(1)
        moves.finish(1, on: 20)
        moves.arrived(1, frame: frame)
        #expect(moves.following(to: "2").isEmpty)
        #expect(moves.isEmpty)
        #expect(moves.takeArrivals() == [1: frame])
        #expect(moves.takeArrivals().isEmpty)
        moves.arrived(1, frame: frame)
        moves.forget(1)
        #expect(!moves.confirms(1, on: 20))
        #expect(moves.takeArrivals().isEmpty)
    }
}
