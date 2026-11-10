import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct AnimatorPendingWritesTests {
    private struct BlockedWriter {
        let animator: Animator
        let writer: AXWriter
        let release: DispatchSemaphore
    }

    @Test func noWritersCompleteImmediately() async {
        #expect(await Animator().waitForPendingWrites(pids: []) == true)
    }

    @Test func timeoutReleasesTheWaitAndIgnoresLateCompletion() async {
        let blocked = blockedWriter()
        defer { blocked.release.signal() }
        #expect(await blocked.animator.waitForPendingWrites(pids: [-1], timeout: 0.02) == false)
        blocked.release.signal()
        await withCheckedContinuation { continuation in blocked.writer.run { continuation.resume() } }
        #expect(await blocked.animator.waitForPendingWrites(pids: [-1]) == true)
    }

    @Test func cancellationReleasesTheWaitBeforeTheWriter() async {
        let blocked = blockedWriter()
        defer { blocked.release.signal() }
        let waiting = Task { @MainActor in await blocked.animator.waitForPendingWrites(pids: [-1]) }
        await Task.yield()
        waiting.cancel()
        #expect(await waiting.value == false)
    }

    @Test func anAlreadyCancelledTaskDoesNotStartWaiting() async {
        let blocked = blockedWriter()
        defer { blocked.release.signal() }
        let waiting = Task { @MainActor in await blocked.animator.waitForPendingWrites(pids: [-1]) }
        waiting.cancel()
        #expect(await waiting.value == false)
    }

    private func blockedWriter() -> BlockedWriter {
        let writer = AXWriter(pid: -1)
        let release = DispatchSemaphore(value: 0)
        writer.run { _ = release.wait(timeout: .now() + 2) }
        let animator = Animator(makeWriter: { _ in writer })
        let window = Window(id: .max - 12, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        animator.position(window, at: CGRect(x: 10, y: 20, width: 300, height: 200))
        return BlockedWriter(animator: animator, writer: writer, release: release)
    }
}
