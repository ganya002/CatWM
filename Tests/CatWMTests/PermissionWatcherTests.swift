import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct PermissionWatcherTests {
    private final class Reader {
        private let lock = NSLock()
        private var reads = 0
        private var completed = false
        let release = DispatchSemaphore(value: 0)
        var count: Int { lock.withLock { reads } }
        var finished: Bool { lock.withLock { completed } }

        func read() -> Set<Permission> {
            let count = lock.withLock { reads += 1; return reads }
            if count < 3 { return [.accessibility, .inputMonitoring] }
            if count == 3 {
                _ = release.wait(timeout: .now() + 30)
                lock.withLock { completed = true }
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
}
