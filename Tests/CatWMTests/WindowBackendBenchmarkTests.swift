import AppKit
@testable import CatWM
@testable import CatWMKit
import QuartzCore
import Testing

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CATWM_BENCH"] != nil))
struct WindowBackendBenchmarkTests {
    final class CountingBackend: WindowBackend {
        private let lock = NSLock()
        private var count = 0
        var writes: Int { lock.withLock { count } }

        func applications() -> [RunningApplicationSnapshot] { [] }
        func desktop(known _: Set<CGWindowID>) -> WindowServerObservation { WindowServerObservation() }
        func scan(_: WindowScanner.Job, discovered _: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
            WindowScanner.AppScan()
        }
        func focusedWindow(pid _: pid_t) -> FocusReader.Result { .focused(nil) }
        func screens() -> [Screen] { [] }
        func currentSpace(display _: String) -> UInt64 { 1 }
        func isRunning(_: pid_t) -> Bool { true }
        func frontmostPID() -> pid_t? { nil }
        func frame(of _: Window) -> CGRect { .null }
        func setPosition(_: Window, _: CGPoint) -> Bool { lock.withLock { count += 1 }; return true }
        func setSize(_: Window, _: CGSize) -> Bool { lock.withLock { count += 1 }; return true }
        func blocksPlacement(_: Window) -> Bool { false }
        func suspendEnhancedUI(_: pid_t) -> Bool { false }
        func resumeEnhancedUI(_: pid_t) {}
        func focus(_: Window, ifCurrent _: () -> Bool) {}
        func refreshCursor() {}
        func close(_: Window) -> String { "not supported" }
    }

    private static let windows = 200, steps = 120, runs = 7

    private func report(_ name: String, _ samples: [Double], per count: Int) {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let line = String(format: "BENCH %@ median %.2f ms, min %.2f ms, %.3f us each",
                          name, median * 1000, sorted[0] * 1000, median / Double(count) * 1e6)
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private func writePath(_ backend: any WindowBackend) -> [Double] {
        let pid: pid_t = -4242
        let windows = (0..<Self.windows).map { index in
            Window(id: CGWindowID(90_000 + index), element: AXUIElementCreateApplication(-Int32(50_000 + index)),
                   pid: pid, bundleID: nil, backend: backend)
        }
        let writer = AXWriter(pid: pid, backend: backend)
        return (0..<Self.runs).map { _ in
            let start = CACurrentMediaTime()
            for step in 0..<Self.steps {
                for (index, window) in windows.enumerated() {
                    let offset = CGFloat(step)
                    writer.step(window) { _ in
                        CGRect(x: CGFloat(index) + offset, y: 10, width: 300 + offset, height: 200)
                    }
                }
                let drained = DispatchSemaphore(value: 0)
                writer.run { drained.signal() }
                drained.wait()
            }
            return CACurrentMediaTime() - start
        }
    }

    @Test func refusedAXWritePath() {
        report("refused-ax-write-path", writePath(AXBackend.shared), per: Self.windows * Self.steps)
    }

    @Test func recordedWritePath() {
        let backend = CountingBackend()
        report("recorded-write-path", writePath(backend), per: Self.windows * Self.steps)
        #expect(backend.writes >= Self.windows * Self.steps * Self.runs)
    }

    @Test func refusedSetPositionCall() {
        let window = Window(id: 1, element: AXUIElementCreateApplication(-77_777), pid: -77_777, bundleID: nil)
        let calls = 20_000
        let samples = (0..<Self.runs).map { _ in
            let start = CACurrentMediaTime()
            for index in 0..<calls { window.setPosition(CGPoint(x: index, y: 0)) }
            return CACurrentMediaTime() - start
        }
        report("refused-set-position", samples, per: calls)
    }
}
