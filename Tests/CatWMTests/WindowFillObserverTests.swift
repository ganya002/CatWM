import AppKit
@testable import CatWM
@testable import CatWMKit
import os
import Testing
import XCTest

@MainActor struct WindowFillObserverTests {
    @Test func readsOffMainAndDeliversOnlyTheLatestRequest() async {
        let queue = DispatchQueue(label: "test.fill-read")
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let observer = WindowFillObserver(queue: queue) { ids in
            #expect(!Thread.isMainThread)
            calls.withLock { $0 += 1 }
            return WindowFillObservation(participants: ids, order: [1], frames: [:])
        }
        let delivered = XCTestExpectation(description: "latest presentation receives the read")
        queue.suspend()
        observer.request([1]) { _ in Issue.record("an obsolete callback ran") }
        observer.request([1]) { observation in
            #expect(Thread.isMainThread)
            #expect(observation?.participants == [1])
            delivered.fulfill()
        }
        queue.resume()
        #expect(await XCTWaiter.fulfillment(of: [delivered], timeout: 2) == .completed)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func cancellationCannotDeliverAReadToANewAnimation() async {
        let queue = DispatchQueue(label: "test.fill-cancel")
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let observer = WindowFillObserver(queue: queue) { ids in
            calls.withLock { $0 += 1 }
            return WindowFillObservation(participants: ids, order: [1], frames: [:])
        }
        let delivered = XCTestExpectation(description: "new animation gets a new read")
        queue.suspend()
        observer.request([1]) { _ in Issue.record("cancelled animation received a read") }
        observer.cancel()
        observer.request([1]) { _ in delivered.fulfill() }
        queue.resume()
        #expect(await XCTWaiter.fulfillment(of: [delivered], timeout: 2) == .completed)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func participantChangesRequireANewObservation() async {
        let queue = DispatchQueue(label: "test.fill-participants")
        let observer = WindowFillObserver(queue: queue) { ids in
            WindowFillObservation(participants: ids, order: Array(ids), frames: [:])
        }
        let delivered = XCTestExpectation(description: "new participants are observed")
        queue.suspend()
        observer.request([1]) { _ in Issue.record("replaced participants received a read") }
        observer.request([2]) { observation in
            #expect(observation?.participants == [2])
            delivered.fulfill()
        }
        queue.resume()
        #expect(await XCTWaiter.fulfillment(of: [delivered], timeout: 2) == .completed)
    }

    @Test func cutoutCoversObservedAndRequestedNativeContent() throws {
        let actual = CGRect(x: 100, y: 38, width: 800, height: 600)
        let requested = CGRect(x: 200, y: 38, width: 650, height: 600)
        let snapshot = WindowFillObservation(participants: [1], order: [1], frames: [1: actual])
        let hole = try #require(snapshot.cutout(for: 1, requested: requested))
        #expect(hole.contains(actual))
        #expect(hole.contains(requested))
        #expect(snapshot.cutout(for: 1, requested: .null) == actual)
        #expect(snapshot.cutout(for: 2, requested: requested) == nil)
    }

    @Test func aSnapshotStillRejectsForegroundObstructionsAndMissingParticipants() {
        let tile = CGRect(x: 0, y: 38, width: 800, height: 600)
        let snapshot = WindowFillObservation(participants: [1], order: [2, 1],
                                              frames: [1: tile, 2: tile.insetBy(dx: 20, dy: 20)])
        #expect(!snapshot.canPresent([tile], excluding: []))
        #expect(snapshot.canPresent([tile], excluding: [2]))
        let missing = WindowFillObservation(participants: [3], order: [1], frames: [1: tile])
        #expect(!missing.canPresent([tile], excluding: []))
    }
}
