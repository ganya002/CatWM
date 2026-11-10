import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct NativePreparationTests {
    @Test func preparingADesktopDoesNotWaitForAnUnrelatedApp() async throws {
        try await preparation(blockedPID: -2, shouldWait: false)
    }

    @Test func preparingADesktopWaitsForItsOwnAppWrites() async throws {
        try await preparation(blockedPID: -1, shouldWait: true)
    }

    private func preparation(blockedPID: pid_t, shouldWait: Bool) async throws {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let manager = WindowManager(config: .parse(defaultText))
        manager.tilingEnabled = true
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        func window(_ id: CGWindowID, pid: pid_t) -> Window {
            let window = Window(id: id, element: AXUIElementCreateApplication(pid), pid: pid, bundleID: nil)
            window.remember(frame)
            return window
        }
        let target = window(.max - 10, pid: -1)
        let blocked = window(.max - 11, pid: blockedPID)
        let writer = AXWriter(pid: blockedPID)
        let release = DispatchSemaphore(value: 0)
        writer.run { _ = release.wait(timeout: .now() + 2) }
        defer { release.signal() }
        manager.animator = Animator(makeWriter: { $0 == blockedPID ? writer : AXWriter(pid: $0) })
        manager.animator.position(blocked, at: frame)
        manager.windows[target.id] = target
        manager.observedApps = [(pid: target.pid, bundleID: nil)]
        manager.order = [target.id]
        manager.model.assign(target.id, to: "test")
        var released = false
        let delayedRelease = Task { @MainActor in
            guard shouldWait else { return }
            released = true
            release.signal()
        }
        defer { delayedRelease.cancel() }
        let started = ProcessInfo.processInfo.systemUptime
        try await manager.prepareNativeLayout(.init(workspace: "test", display: screen.uuid, space: 0))
        let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
        print("native preparation: blocked PID \(blockedPID), \(elapsed) ms, released \(released)")
        #expect(released == shouldWait)
        #expect(manager.targets[target.id] != nil)
    }
}
