import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

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
        let manager = WindowManager(config: .parse(defaultText))
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
        let tracked = window(7)
        manager.windows[tracked.id] = tracked
        manager.visible = [tracked.id]
        let release = DispatchSemaphore(value: 0)
        let reads = Counter()
        manager.focusRequests.focusReader = FocusReader { _ in
            if reads.next() == 1 { _ = release.wait(timeout: .now() + 3) }
            return .focused(tracked.id)
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
            #expect(manager.focusRequests.focusCommands.count == 2)
            release.signal()
        }
        #expect(dispatched.map(\.0) == ["minimize", "minimize"])
        #expect(dispatched.map(\.1) == [true, false])
        #expect(manager.focusRequests.focusCommands.isEmpty)
        manager.onDispatch = nil
    }

    @Test @MainActor func anUnavailableReplyDoesNotDiscardACommand() async {
        let manager = manager()
        let tracked = window(7)
        manager.windows[tracked.id] = tracked
        let reads = Counter()
        manager.focusRequests.focusReader = FocusReader { _ in reads.next() == 1 ? .unavailable : .focused(tracked.id) }
        await withCheckedContinuation { continuation in
            manager.onDispatch = { [weak manager] _, _, _ in
                manager?.isStarted = false
                continuation.resume()
            }
            manager.dispatch("minimize", "")
        }
        #expect(reads.value == 2)
        #expect(manager.focusRequests.reportedFocus?.id == tracked.id)
        manager.onDispatch = nil
    }

    @Test @MainActor func aFocusedElementWithoutAWindowIDDoesNotRetry() async {
        let manager = manager()
        let reads = Counter()
        manager.focusRequests.focusReader = FocusReader { _ in
            _ = reads.next()
            return FocusReader.resolve(AXUIElementCreateApplication(-1))
        }
        var dispatched = 0, retries = 0
        manager.onDispatch = { _, _, _ in dispatched += 1 }
        manager.focusRequests.retryRead = { _ in retries += 1 }
        await withCheckedContinuation { continuation in
            manager.onChange = { continuation.resume() }
            manager.dispatch("minimize", "")
        }
        manager.onChange = nil
        #expect(manager.focusRequests.reportedFocus?.pid == -1)
        #expect(manager.focusRequests.reportedFocus?.id == nil)
        #expect(manager.focusRequests.focusCommands.isEmpty)
        #expect(dispatched == 1)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(retries == 0)
        #expect(manager.focusRequests.focusReads.isEmpty)
        #expect(reads.value == 1)
        manager.isStarted = false
        manager.onDispatch = nil
    }

    @Test @MainActor func aCommandDoesNotFollowTheUserToAnotherApp() async {
        let manager = manager()
        var active: pid_t = -1
        manager.frontmostPID = { active }
        let release = DispatchSemaphore(value: 0)
        manager.focusRequests.focusReader = FocusReader { pid in
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
        #expect(manager.focusRequests.focusCommands.isEmpty)
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
        manager.focusRequests.report(pid: -1, id: closed.id)
        let release = DispatchSemaphore(value: 0)
        let reads = Counter()
        manager.focusRequests.focusReader = FocusReader { _ in
            if reads.next() == 1 {
                _ = release.wait(timeout: .now() + 3)
                return .focused(closed.id)
            }
            return .focused(nil)
        }
        await withCheckedContinuation { continuation in
            manager.animator = Animator(applyFocus: { [weak manager] focused, isCurrent in
                #expect(focused.id == remaining.id && isCurrent())
                DispatchQueue.main.async {
                    manager?.isStarted = false
                    continuation.resume()
                }
            })
            manager.requestFocusObservation()
            manager.forget(closed.id)
            #expect(manager.focusRequests.reportedFocus == nil)
            manager.refocusRecent(on: "1")
            #expect(manager.focusRequests.waitingRefocus?.workspace == "1")
            release.signal()
        }
        #expect(manager.focusRequests.pendingFocus?.id == remaining.id)
        #expect(reads.value == 2)
    }

    @Test @MainActor func focusReadsDoNotWaitForABulkScan() async {
        let manager = manager()
        let tracked = window(7)
        manager.windows[tracked.id] = tracked
        let release = DispatchSemaphore(value: 0)
        manager.scanner.run(tracked.pid) { _ = release.wait(timeout: .now() + 3) }
        manager.focusRequests.focusReader = FocusReader { _ in .focused(tracked.id) }
        await withCheckedContinuation { continuation in
            manager.onChange = { [weak manager] in
                manager?.isStarted = false
                continuation.resume()
            }
            manager.requestFocusObservation()
        }
        #expect(manager.focusRequests.reportedFocus?.id == tracked.id)
        release.signal()
        manager.onChange = nil
    }

    @Test @MainActor func aPendingFocusStaysWhileItsWriteIsBlocked() async {
        let manager = manager()
        let tracked = window(7)
        manager.windows[tracked.id] = tracked
        manager.visible = [tracked.id]
        let release = DispatchSemaphore(value: 0)
        await withCheckedContinuation { continuation in
            manager.animator = Animator(applyFocus: { _, _ in
                continuation.resume()
                _ = release.wait(timeout: .now() + 3)
            })
            manager.focus(tracked, warp: false)
        }
        manager.acceptFocus(pid: tracked.pid, id: tracked.id)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(manager.focusedWindow()?.id == tracked.id)
        #expect(manager.focusRequests.pendingFocus?.id == tracked.id)
        manager.isStarted = false
        release.signal()
    }

    @Test @MainActor func restorationCancelsPendingFocusAndCommands() {
        let manager = manager()
        manager.focusRequests.begin(id: 7, pid: -1, origin: -1)
        manager.focusRequests.enqueue(.init(pid: -1, dispatcher: "minimize", arg: "", inMode: false))
        manager.restoreHiddenWindows()
        #expect(manager.focusRequests.pendingFocus == nil)
        #expect(manager.focusRequests.focusCommands.isEmpty)
    }

    @Test @MainActor func aNewAppInvalidatesAPendingFocusRequest() {
        let manager = manager()
        let tracked = window(7)
        manager.windows[tracked.id] = tracked
        manager.visible = [tracked.id]
        manager.focusRequests.begin(id: tracked.id, pid: tracked.pid, origin: -1)
        manager.frontmostPID = { -2 }
        #expect(manager.focusedWindow() == nil)
        #expect(manager.focusRequests.pendingFocus == nil)
    }

    @Test @MainActor func focusWritesDoNotWaitForPlacementWrites() {
        let tracked = window(7)
        let writer = AXWriter(pid: tracked.pid)
        let release = DispatchSemaphore(value: 0)
        let focused = DispatchSemaphore(value: 0)
        writer.run { _ = release.wait(timeout: .now() + 3) }
        let animator = Animator(makeWriter: { _ in writer }, applyFocus: { _, isCurrent in
            #expect(!Thread.isMainThread && isCurrent())
            focused.signal()
        })
        animator.position(tracked, at: CGRect(x: 10, y: 20, width: 300, height: 200))
        animator.focus(tracked)
        #expect(focused.wait(timeout: .now() + 2) == .success)
        release.signal()
    }
}
