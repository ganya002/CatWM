import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct WindowDiscoveryTests {
    private func window(_ id: CGWindowID) -> Window {
        Window(id: id, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
    }

    @Test func aNewWindowPublishesBeforeItsOwnAppsKnownWindowsFinish() async {
        let old = window(1), new = window(2)
        old.fullscreen = true
        old.minimized = true
        let release = DispatchSemaphore(value: 0)
        let scanner = WindowScanner(read: { job, discovered in
            var scan = WindowScanner.AppScan()
            scan.listed = [old.id, new.id]
            scan.fullscreen = job.fullscreen
            scan.minimized = job.minimized
            scan.found[new.id] = .init(element: new.element,
                frame: CGRect(x: 10, y: 20, width: 300, height: 200), title: nil, resizable: true)
            discovered(scan)
            _ = release.wait(timeout: .now() + 30)
            scan.fullscreen = []
            scan.minimized = []
            return scan
        }, deadline: 60)
        var completed = false
        await withCheckedContinuation { continuation in
            scanner.scan([.init(pid: -1, listWindows: true, known: [old.id: old])],
                         done: { completed = true }, updated: { continuation.resume() })
        }
        #expect(!completed)
        #expect(scanner.results[-1]?.listed == [old.id, new.id])
        #expect(scanner.results[-1]?.found[new.id] != nil)
        #expect(scanner.results[-1]?.found[old.id] == nil)
        #expect(scanner.results[-1]?.fullscreen == [old.id])
        #expect(scanner.results[-1]?.minimized == [old.id])
        release.signal()
        await drain(scanner)
        #expect(completed)
        #expect(scanner.results[-1]?.fullscreen.isEmpty == true)
        #expect(scanner.results[-1]?.minimized.isEmpty == true)
    }

    @Test func terminationDiscardsBothDiscoveryAndFinalResults() async {
        let release = DispatchSemaphore(value: 0)
        let scanner = WindowScanner(read: { _, discovered in
            var scan = WindowScanner.AppScan()
            scan.listed = [7]
            discovered(scan)
            _ = release.wait(timeout: .now() + 30)
            return scan
        }, deadline: 60)
        await withCheckedContinuation { continuation in
            scanner.scan([.init(pid: -1, listWindows: true, known: [:])],
                         done: {}, updated: { continuation.resume() })
        }
        #expect(scanner.results[-1]?.listed == [7])
        scanner.forget(-1)
        release.signal()
        await drain(scanner)
        #expect(scanner.results[-1] == nil)
    }

    @Test func discoveryKeepsTheCapturedKnownWindowState() {
        let old = window(1)
        old.fullscreen = true
        old.minimized = true
        let job = WindowScanner.Job(pid: -1, listWindows: true, known: [old.id: old])
        old.fullscreen = false
        old.minimized = false
        #expect(job.fullscreen == [old.id])
        #expect(job.minimized == [old.id])
    }

    private func drain(_ scanner: WindowScanner) async {
        await withCheckedContinuation { continuation in
            scanner.run(-1) { DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
