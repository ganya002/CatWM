import AppKit
@testable import CatWM
import os
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct NativePreparationTests {
    @Test func preparingADesktopDoesNotWaitForAnUnrelatedApp() async throws {
        let test = try preparation(blockedPID: -2)
        try await test.prepare()
        await test.finish(expecting: ["preparationReturned", "writerFinished"])
    }

    @Test func preparingADesktopWaitsForItsOwnAppWrites() async throws {
        let test = try preparation(blockedPID: -1)
        Task { @MainActor in
            test.events.withLock { $0.append("writerReleased") }
            test.release.signal()
        }
        try await test.prepare()
        await test.finish(expecting: ["writerReleased", "writerFinished", "preparationReturned"])
    }

    @Test func preparingADesktopFailsWhileItsOwnAppWriteIsBlocked() async throws {
        let test = try preparation(blockedPID: -1)
        await #expect(throws: DesktopTransitionError.self) { try await test.prepare() }
        test.events.withLock { $0.append("preparationFailed") }
        await test.finish(expecting: ["preparationFailed", "writerFinished"])
    }

    private struct Preparation {
        let manager: WindowManager
        let target: Window
        let request: NativeDesktopController.Request
        let release: DispatchSemaphore
        let events: OSAllocatedUnfairLock<[String]>

        func prepare() async throws {
            try await manager.prepareNativeLayout(request)
            events.withLock { $0.append("preparationReturned") }
        }

        func finish(expecting expected: [String]) async {
            release.signal()
            let finished = await poll(2) { events.withLock { $0.contains("writerFinished") } }
            #expect(finished)
            #expect(events.withLock { $0 } == expected)
            if expected.contains("preparationReturned") { #expect(manager.targets[target.id] != nil) }
        }
    }

    private func preparation(blockedPID: pid_t) throws -> Preparation {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let manager = WindowManager()
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
        let events = OSAllocatedUnfairLock<[String]>(initialState: [])
        writer.run {
            _ = release.wait(timeout: .now() + 3)
            events.withLock { $0.append("writerFinished") }
        }
        manager.animator = Animator(makeWriter: { $0 == blockedPID ? writer : AXWriter(pid: $0) })
        manager.animator.position(blocked, at: frame)
        manager.windows[target.id] = target
        manager.observedApps = [(pid: target.pid, bundleID: nil)]
        manager.order = [target.id]
        manager.model.assign(target.id, to: "test")
        return .init(manager: manager, target: target,
                     request: .init(workspace: "test", display: screen.uuid, space: 0),
                     release: release, events: events)
    }
}
