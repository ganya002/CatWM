import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct ScanCompletionTests {
    final class BlockingBackend: WindowBackend {
        static let pid: pid_t = -300
        static let window: CGWindowID = 4_300

        private let lock = NSLock()
        private var reads = 0
        private var readStarted: (() -> Void)?
        let release = DispatchSemaphore(value: 0)
        var onScreens: (() -> Void)?

        func firstRead(started: @escaping () -> Void) { lock.withLock { readStarted = started } }

        func applications() -> [RunningApplicationSnapshot] {
            [RunningApplicationSnapshot(pid: Self.pid, bundleID: "test.blocking", regular: true, hidden: false)]
        }

        func desktop(known _: Set<CGWindowID>) -> WindowServerObservation {
            let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
            let info = CGWindowInfo(id: Self.window, pid: Self.pid, bounds: bounds)
            return WindowServerObservation(windows: [info], allWindows: [info])
        }

        func scan(_ job: WindowScanner.Job, discovered _: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
            let (first, started) = lock.withLock { reads += 1; return (reads == 1, readStarted) }
            if first {
                started?()
                release.wait()
                return WindowScanner.AppScan()
            }
            var scan = WindowScanner.AppScan()
            scan.listed = [Self.window]
            scan.found[Self.window] = .init(element: AXUIElementCreateApplication(Self.pid),
                                            frame: CGRect(x: 0, y: 0, width: 400, height: 300), title: "Blocked",
                                            resizable: true, frameRevision: job.known[Self.window]?.frameRevision)
            return scan
        }

        func focusedWindow(pid _: pid_t) -> FocusReader.Result { .focused(Self.window) }
        func screens() -> [Screen] {
            onScreens?()
            let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
            return [Screen(id: 1, uuid: "blocking", frame: frame, visible: frame, isBuiltin: false, nsScreen: nil)]
        }
        func currentSpace(display _: String) -> UInt64 { 1 }
        func isRunning(_ pid: pid_t) -> Bool { pid == Self.pid }
        func frontmostPID() -> pid_t? { Self.pid }
        func frame(of _: Window) -> CGRect { CGRect(x: 0, y: 0, width: 400, height: 300) }
        func setPosition(_: Window, _: CGPoint) -> Bool { false }
        func setSize(_: Window, _: CGSize) -> Bool { false }
        func blocksPlacement(_: Window) -> Bool { true }
        func suspendEnhancedUI(_: pid_t) -> Bool { false }
        func resumeEnhancedUI(_: pid_t) {}
        func focus(_: Window, ifCurrent _: () -> Bool) {}
        func refreshCursor() {}
        func close(_: Window) -> String { "not supported" }
    }

    private func nextRefresh(_ backend: BlockingBackend) async {
        await withCheckedContinuation { done in
            backend.onScreens = {
                backend.onScreens = nil
                DispatchQueue.main.async { done.resume() }
            }
        }
    }

    @Test func aScanWaitsForABlockedAppAndThenReadsItAgain() async {
        let backend = BlockingBackend()
        var config = Config.parse(defaultText)
        config.virtualWorkspaces = false
        config.animate = false
        config.mouseFollowsFocus = false
        config.focusFollowsMouse = false
        let manager = WindowManager(backend: backend, config: config)
        manager.startEngine()
        await withCheckedContinuation { started in
            backend.firstRead { started.resume() }
            manager.scanAndRefresh()
        }
        await nextRefresh(backend)

        var finished: CheckedContinuation<Void, Never>?
        var fired = false, knewWindow = false
        manager.scanAndRefresh {
            fired = true
            knewWindow = manager.windows[BlockingBackend.window] != nil
            finished?.resume()
        }
        await nextRefresh(backend)
        #expect(!fired, "The scan finished while the app scan was still blocked")

        backend.release.signal()
        if !fired { await withCheckedContinuation { finished = $0 } }
        #expect(knewWindow)
    }
}
