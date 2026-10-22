import AppKit
@testable import ouch
import Testing

@Suite struct WindowObservationTests {
    private func window() -> Window {
        Window(id: 7, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
    }

    @Test @MainActor func emptyRestorationRepliesDuringTheTerminationRunLoop() {
        let manager = WindowManager()
        manager.config.virtualWorkspaces = false
        var returned = false
        var completed = false
        manager.restoreHiddenWindows {
            #expect(returned)
            completed = true
        }
        returned = true
        let deadline = Date().addingTimeInterval(2)
        while !completed && Date() < deadline {
            RunLoop.current.run(mode: .modalPanel, before: Date().addingTimeInterval(0.005))
        }
        #expect(completed)
    }

    @Test @MainActor func floatingFocusUsesThePendingUnparkDestination() {
        let manager = WindowManager()
        let tracked = window()
        tracked.userFloating = .chosen(true)
        tracked.remember(CGRect(x: 1999, y: 799, width: 300, height: 200))
        let destination = CGRect(x: 100, y: 100, width: 300, height: 200)
        manager.animator.position(tracked, at: destination)
        #expect(manager.navFrame(tracked) == destination)
    }

    @Test func anObservationCannotReplaceANewerPlacement() {
        let tracked = window()
        let observed = CGRect(x: 10, y: 20, width: 100, height: 200)
        let placed = CGRect(x: 50, y: 60, width: 300, height: 400)
        tracked.remember(observed)
        let version = tracked.frameRevision
        tracked.remember(placed)
        tracked.remember(observed, ifRevision: version)
        #expect(tracked.cachedFrame == placed)
    }

    @Test func theFinalDragObservationReplacesEarlierObservations() {
        let tracked = window()
        let revision = tracked.frameRevision
        let first = CGRect(x: 10, y: 20, width: 100, height: 200)
        let final = CGRect(x: 50, y: 60, width: 300, height: 400)
        let start = Date(timeIntervalSince1970: 1000)
        tracked.remember(first, ifRevision: revision, readAt: start)
        tracked.remember(final, ifRevision: revision, readAt: start.addingTimeInterval(1))
        #expect(tracked.cachedFrame == final)
        tracked.remember(first, ifRevision: revision, readAt: start)
        #expect(tracked.cachedFrame == final)
    }

    @Test @MainActor func replayingAScanCannotUndoANewerFrame() {
        let manager = WindowManager()
        let tracked = window()
        let frame = CGRect(x: 10, y: 20, width: 100, height: 200)
        let placed = CGRect(x: 50, y: 60, width: 300, height: 400)
        let found = WindowScanner.Found(element: tracked.element, frame: frame, title: "Window", resizable: false)
        let scan = WindowScanner.AppScan()
        manager.accept(found, from: scan, for: tracked)
        #expect(tracked.title == "Window" && !tracked.resizable)
        tracked.remember(placed)
        manager.accept(found, from: scan, for: tracked)
        #expect(tracked.cachedFrame == placed)
    }

    @Test @MainActor func aSlowAppDoesNotBlockTheMainQueueOrOtherApps() async {
        let release = DispatchSemaphore(value: 0)
        let scanner = WindowScanner { job in
            #expect(!Thread.isMainThread)
            if job.pid == 1, !Thread.isMainThread { release.wait() }
            var scan = WindowScanner.AppScan()
            scan.listed = job.pid == 2 ? Array(1...50) : [51]
            return scan
        }
        var mainQueueRan = false
        let jobs = [1, 2].map { WindowScanner.Job(pid: $0, listWindows: true, known: [:]) }
        await withCheckedContinuation { continuation in
            scanner.scan(jobs, done: { continuation.resume() }, late: {})
            DispatchQueue.main.async { mainQueueRan = true }
        }
        #expect(mainQueueRan)
        #expect(scanner.results[1] == nil)
        #expect(scanner.results[2]?.listed.count == 50)
        release.signal()
        await drain(scanner, pid: 1)
        #expect(scanner.results[1]?.listed == [51])
    }

    @Test @MainActor func repeatedScansDoNotQueueMoreWorkForABusyApp() async {
        let release = DispatchSemaphore(value: 0)
        let scanner = WindowScanner { _ in
            _ = release.wait(timeout: .now() + 3)
            return WindowScanner.AppScan()
        }
        let jobs = [WindowScanner.Job(pid: 1, listWindows: true, known: [:])]
        scanner.scan(jobs, done: {}, late: {})
        var completions = 0
        for _ in 0..<50 { scanner.scan(jobs, done: { completions += 1 }, late: {}) }
        #expect(completions == 50)
        release.signal()
        await drain(scanner, pid: 1)
    }

    @Test @MainActor func terminationDiscardsAnInFlightScan() async {
        let release = DispatchSemaphore(value: 0)
        let scanner = WindowScanner { _ in
            _ = release.wait(timeout: .now() + 3)
            var scan = WindowScanner.AppScan()
            scan.listed = [7]
            return scan
        }
        scanner.scan([.init(pid: 1, listWindows: true, known: [:])], done: {}, late: {})
        scanner.forget(1)
        release.signal()
        await drain(scanner, pid: 1)
        #expect(scanner.results[1] == nil)
    }

    @MainActor private func drain(_ scanner: WindowScanner, pid: pid_t) async {
        await withCheckedContinuation { continuation in
            scanner.run(pid) { DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
