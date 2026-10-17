import AppKit
import Testing
@testable import ouch

@Suite struct FocusObservationTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.withLock { count += 1; return count } }
        var value: Int { lock.withLock { count } }
    }

    private func window(_ id: CGWindowID) -> Window {
        Window(id: id, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
    }

    @MainActor private func manager() -> WindowManager {
        let manager = WindowManager()
        manager.isStarted = true
        manager.frontmostPID = { -1 }
        manager.config.virtualWorkspaces = false
        manager.config.mouseFollowsFocus = false
        return manager
    }

    @Test func globalCommandsDoNotWaitForFocus() {
        func requires(_ dispatcher: String, _ arg: String = "") -> Bool {
            Actions.requiresFocus(BindRow(mods: "", key: "", dispatcher: dispatcher, args: arg))
        }
        #expect(!requires("workspace", "project"))
        #expect(!requires("exit"))
        #expect(!requires("reevaluate"))
        #expect(!requires("focusmonitor", "+2"))
        #expect(requires("movetoworkspace", "project"))
        #expect(requires("movetoworkspacesilent", "+1"))
        #expect(requires("movewindowtomonitor", "+2"))
        #expect(requires("swapwindow", "l"))
        #expect(requires("setlayout", "bsp"))
    }

    @Test @MainActor func commandsWaitForFocusAfterActivation() async {
        let manager = manager()
        let w = window(7)
        manager.windows[w.id] = w
        manager.visible = [w.id]
        let release = DispatchSemaphore(value: 0)
        let reads = Counter()
        manager.focusReader = FocusReader { _ in
            if reads.next() == 1 { _ = release.wait(timeout: .now() + 3) }
            return .focused(w.id)
        }
        var dispatched: [(String, Bool)] = []
        await withCheckedContinuation { continuation in
            manager.onDispatch = { [weak manager] dispatcher, _, inMode in
                dispatched.append((dispatcher, inMode))
                if dispatched.count == 2 {
                    manager?.isStarted = false
                    continuation.resume()
                }
            }
            manager.requestFocusObservation()
            manager.dispatch("minimize", "", inMode: true)
            manager.dispatch("minimize", "", inMode: false)
            #expect(dispatched.isEmpty)
            #expect(manager.focusCommands.count == 2)
            release.signal()
        }
        #expect(dispatched.map(\.0) == ["minimize", "minimize"])
        #expect(dispatched.map(\.1) == [true, false])
        #expect(manager.focusCommands.isEmpty)
        manager.onDispatch = nil
    }

    @Test @MainActor func anUnavailableReplyDoesNotDiscardACommand() async {
        let manager = manager()
        let w = window(7)
        manager.windows[w.id] = w
        let reads = Counter()
        manager.focusReader = FocusReader { _ in reads.next() == 1 ? .unavailable : .focused(w.id) }
        await withCheckedContinuation { continuation in
            manager.onDispatch = { [weak manager] _, _, _ in
                manager?.isStarted = false
                continuation.resume()
            }
            manager.dispatch("minimize", "")
        }
        #expect(reads.value == 2)
        #expect(manager.reportedFocus?.id == w.id)
        manager.onDispatch = nil
    }

    @Test @MainActor func aFocusedElementWithoutAWindowIDDoesNotRetry() async throws {
        let manager = manager()
        let reads = Counter()
        manager.focusReader = FocusReader { _ in
            _ = reads.next()
            return FocusReader.resolve(AXUIElementCreateApplication(-1))
        }
        var dispatched = 0
        manager.onDispatch = { _, _, _ in dispatched += 1 }
        await withCheckedContinuation { continuation in
            manager.onChange = { continuation.resume() }
            manager.dispatch("minimize", "")
        }
        manager.onChange = nil
        #expect(manager.reportedFocus?.pid == -1)
        #expect(manager.reportedFocus?.id == nil)
        #expect(manager.focusCommands.isEmpty)
        #expect(dispatched == 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(reads.value == 1)
        manager.isStarted = false
        manager.onDispatch = nil
    }

    @Test @MainActor func aCommandDoesNotFollowTheUserToAnotherApp() async {
        let manager = manager()
        var active: pid_t = -1
        manager.frontmostPID = { active }
        let release = DispatchSemaphore(value: 0)
        manager.focusReader = FocusReader { pid in
            if pid == -1 { _ = release.wait(timeout: .now() + 3) }
            return .focused(nil)
        }
        var dispatched = false
        manager.onDispatch = { _, _, _ in dispatched = true }
        await withCheckedContinuation { continuation in
            manager.onChange = { [weak manager] in
                manager?.isStarted = false
                release.signal()
                continuation.resume()
            }
            manager.dispatch("minimize", "")
            active = -2
            manager.requestFocusObservation()
        }
        #expect(!dispatched)
        #expect(manager.focusCommands.isEmpty)
        manager.onChange = nil
        manager.onDispatch = nil
    }

    @Test @MainActor func closingAReportedWindowRetriesFocusAfterTheRead() async {
        let manager = manager()
        let closed = window(7), remaining = window(8)
        manager.windows = [closed.id: closed, remaining.id: remaining]
        manager.visible = [closed.id, remaining.id]
        manager.model.assign(closed.id, to: "1")
        manager.model.assign(remaining.id, to: "1")
        manager.model.show("1", on: "display")
        manager.model.noteFocus(remaining.id)
        manager.model.noteFocus(closed.id)
        manager.reportedFocus = (-1, closed.id)
        let release = DispatchSemaphore(value: 0)
        let reads = Counter()
        manager.focusReader = FocusReader { _ in
            if reads.next() == 1 {
                _ = release.wait(timeout: .now() + 3)
                return .focused(closed.id)
            }
            return .focused(nil)
        }
        await withCheckedContinuation { continuation in
            manager.animator = Animator(applyFocus: { [weak manager] w, isCurrent in
                #expect(w.id == remaining.id && isCurrent())
                DispatchQueue.main.async {
                    manager?.isStarted = false
                    continuation.resume()
                }
            })
            manager.requestFocusObservation()
            manager.forget(closed.id)
            #expect(manager.reportedFocus == nil)
            manager.refocusRecent(on: "1")
            #expect(manager.waitingRefocus?.workspace == "1")
            release.signal()
        }
        #expect(manager.pendingFocus?.id == remaining.id)
        #expect(reads.value == 2)
    }

    @Test @MainActor func focusReadsDoNotWaitForABulkScan() async {
        let manager = manager()
        let w = window(7)
        manager.windows[w.id] = w
        let release = DispatchSemaphore(value: 0)
        manager.scanner.run(w.pid) { _ = release.wait(timeout: .now() + 3) }
        manager.focusReader = FocusReader { _ in .focused(w.id) }
        await withCheckedContinuation { continuation in
            manager.onChange = { [weak manager] in
                manager?.isStarted = false
                continuation.resume()
            }
            manager.requestFocusObservation()
        }
        #expect(manager.reportedFocus?.id == w.id)
        release.signal()
        manager.onChange = nil
    }

    @Test @MainActor func aPendingFocusDoesNotExpireWhileItsWriteIsBlocked() async throws {
        let manager = manager()
        let w = window(7)
        manager.windows[w.id] = w
        manager.visible = [w.id]
        let release = DispatchSemaphore(value: 0)
        manager.animator = Animator(applyFocus: { _, _ in _ = release.wait(timeout: .now() + 3) })
        manager.focus(w, warp: false)
        manager.acceptFocus(pid: w.pid, id: w.id)
        try await Task.sleep(for: .milliseconds(600))
        #expect(manager.focusedWindow()?.id == w.id)
        #expect(manager.pendingFocus?.id == w.id)
        manager.isStarted = false
        release.signal()
    }

    @Test @MainActor func restorationCancelsPendingFocusAndCommands() {
        let manager = manager()
        manager.pendingFocus = WindowManager.PendingFocus(id: 7, pid: -1, origin: -1, request: UUID())
        manager.focusCommands = [WindowManager.FocusCommand(pid: -1, dispatcher: "minimize", arg: "", inMode: false)]
        manager.restoreHiddenWindows()
        #expect(manager.pendingFocus == nil)
        #expect(manager.focusCommands.isEmpty)
    }

    @Test @MainActor func aNewAppInvalidatesAPendingFocusRequest() {
        let manager = manager()
        let w = window(7)
        manager.windows[w.id] = w
        manager.visible = [w.id]
        manager.pendingFocus = WindowManager.PendingFocus(id: w.id, pid: w.pid, origin: -1, request: UUID())
        manager.frontmostPID = { -2 }
        #expect(manager.focusedWindow() == nil)
        #expect(manager.pendingFocus == nil)
    }

    @Test @MainActor func focusWritesDoNotWaitForPlacementWrites() {
        let w = window(7)
        let writer = AXWriter(pid: w.pid)
        let release = DispatchSemaphore(value: 0)
        let focused = DispatchSemaphore(value: 0)
        writer.run { _ = release.wait(timeout: .now() + 3) }
        let animator = Animator(makeWriter: { _ in writer }, applyFocus: { _, isCurrent in
            #expect(!Thread.isMainThread && isCurrent())
            focused.signal()
        })
        animator.position(w, at: CGRect(x: 10, y: 20, width: 300, height: 200))
        animator.focus(w)
        #expect(focused.wait(timeout: .now() + 2) == .success)
        release.signal()
    }
}
