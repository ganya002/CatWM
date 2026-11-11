import AppKit
@testable import CatWM
@testable import CatWMKit
import os
import Testing

@MainActor @Suite struct ApplicationObservationTests {
    @Test func applicationReadsDoNotBlockInputOrPublishAnIncompleteObservation() async {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let application = RunningApplicationSnapshot(pid: 42, bundleID: "test.app", regular: true, hidden: false)
        let scanner = WindowScanner(readDesktop: { _ in
            #expect(Thread.isMainThread)
            return WindowServerObservation(spaces: [7: [9]])
        }, readApplications: {
            #expect(!Thread.isMainThread)
            if reads.withLock({ $0 += 1; return $0 }) == 1 {
                entered.signal()
                _ = release.wait(timeout: .now() + 30)
            }
            return [application]
        })
        var completed = false
        scanner.observeDesktop(known: [7]) { completed = true }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = entered.wait(timeout: .now() + 30)
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(!completed)
        #expect(scanner.desktop.spaces.isEmpty)
        #expect(scanner.applications.isEmpty)
        release.signal()
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: [7]) { continuation.resume() }
        }
        #expect(completed)
        #expect(scanner.desktop.spaces[7] == [9])
        #expect(scanner.applications.map(\.pid) == [42])
        #expect(scanner.applications.first?.bundleID == "test.app")
    }

    @Test func eachObservationReadsCurrentApplicationState() async {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let scanner = WindowScanner(readDesktop: { _ in WindowServerObservation() }, readApplications: {
            let count = reads.withLock { $0 += 1; return $0 }
            return [.init(pid: pid_t(count), bundleID: nil, regular: true, hidden: count == 2)]
        })
        for expected in 1...2 {
            await withCheckedContinuation { continuation in
                scanner.observeDesktop(known: []) { continuation.resume() }
            }
            #expect(scanner.applications.first?.pid == pid_t(expected))
            #expect(scanner.applications.first?.hidden == (expected == 2))
        }
    }
}
