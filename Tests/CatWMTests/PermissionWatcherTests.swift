import AppKit
@testable import CatWM
@testable import CatWMKit
import os
import Testing

private struct ReaderState { var reads = 0, completed = false }

@MainActor @Suite struct PermissionWatcherTests {
    private final class Reader: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: ReaderState())
        let release = DispatchSemaphore(value: 0)
        var count: Int { state.withLock { $0.reads } }
        var finished: Bool { state.withLock { $0.completed } }

        func read() -> Set<Permission> {
            let count = state.withLock { $0.reads += 1; return $0.reads }
            if count < 3 { return [.accessibility, .inputMonitoring] }
            if count == 3 {
                _ = release.wait(timeout: .now() + 30)
                state.withLock { $0.completed = true }
                return [.accessibility]
            }
            return []
        }
    }

    @Test func aBlockedCheckLeavesMainFreeAndCoalescesPendingChecks() async {
        let reader = Reader()
        var refreshes = 0
        let watcher = PermissionWatcher(read: reader.read, refreshScreenRecording: {
            #expect(Thread.isMainThread)
            refreshes += 1
        })
        defer { reader.release.signal() }
        var results: [(Set<Permission>, Set<Permission>)] = []
        watcher.subscribe { [weak watcher] granted, changed in
            #expect(Thread.isMainThread)
            #expect(watcher?.granted == granted)
            results.append((granted, changed))
        }
        watcher.tick()
        #expect(await poll(15, every: 1_000_000) { results.count == 1 })
        results = []
        watcher.tick()
        #expect(await poll(15, every: 1_000_000) { reader.count == 3 })
        #expect(!reader.finished)
        #expect(results.isEmpty)
        watcher.tick()
        watcher.tick()
        #expect(reader.count == 3)
        #expect(refreshes == 2)
        reader.release.signal()
        #expect(await poll(15, every: 1_000_000) { results.count == 2 })
        #expect(reader.count == 4)
        #expect(refreshes == 3)
        #expect(results.map(\.0) == [[.accessibility], []])
        #expect(results.map(\.1) == [[.inputMonitoring], [.accessibility]])
        #expect(watcher.atLaunch == [.accessibility, .inputMonitoring])
    }

    @Test func unchangedPermissionsStillNotifySubscribers() async {
        let watcher = PermissionWatcher(read: { [.accessibility] })
        watcher.tick()
        #expect(await poll(15, every: 1_000_000) { watcher.granted == [.accessibility] })
        var notified = false
        watcher.subscribe { granted, changed in
            #expect(Thread.isMainThread)
            #expect(granted == [.accessibility])
            #expect(changed.isEmpty)
            notified = true
        }
        watcher.tick()
        #expect(await poll(15, every: 1_000_000) { notified })
    }

    @Test func anUnwatchedWatcherChecksOnlyWhenWatchingChanges() async {
        var watched = false
        var refreshes = 0
        let watcher = PermissionWatcher(read: { [.accessibility] }, refreshScreenRecording: { refreshes += 1 },
                                        isWatched: { watched })
        watcher.start()
        defer { watcher.stop() }
        #expect(!watcher.isPolling)
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        watched = true
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(await poll(15, every: 1_000_000) { refreshes == 1 })
        #expect(watcher.isPolling)
        watched = false
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(await poll(15, every: 1_000_000) { refreshes == 2 })
        #expect(!watcher.isPolling)
    }
}
