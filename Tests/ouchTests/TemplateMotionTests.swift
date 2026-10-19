import AppKit
@testable import ouch
import Testing

@Suite struct TemplateMotionTests {
    final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    @Test @MainActor func aShutdownBarrierDoesNotRequireTheMainQueue() {
        let animator = Animator()
        let completed = DispatchSemaphore(value: 0)
        animator.afterPendingWrites(pids: nil, completionQueue: .global(qos: .userInitiated)) { completed.signal() }
        #expect(completed.wait(timeout: .now() + 2) == .success)
    }

    @Test func cancellingAQueuedVerificationPreventsItsWrite() async {
        let writer = AXWriter(pid: getpid())
        let release = DispatchSemaphore(value: 0)
        let ran = ResultBox()
        writer.run { _ = release.wait(timeout: .now() + 2) }
        writer.run(for: 42) { _ in ran.value = true }
        writer.cancel(42)
        release.signal()
        await drain(writer)
        #expect(!ran.value)
    }

    @Test func cancellingDuringReadInvalidatesTheFollowingWrite() async {
        let writer = AXWriter(pid: getpid())
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let valid = ResultBox()
        writer.run(for: 42) { isCurrent in
            started.signal()
            _ = release.wait(timeout: .now() + 2)
            valid.value = isCurrent()
        }
        #expect(started.wait(timeout: .now() + 2) == .success)
        writer.cancel(42)
        release.signal()
        await drain(writer)
        #expect(!valid.value)
    }

    @Test func anotherWindowsCancellationDoesNotDropTheCurrentWrite() async {
        let writer = AXWriter(pid: getpid())
        let release = DispatchSemaphore(value: 0)
        let ran = ResultBox()
        writer.run { _ = release.wait(timeout: .now() + 2) }
        writer.run(for: 42) { isCurrent in ran.value = isCurrent() }
        writer.cancel(43)
        release.signal()
        await drain(writer)
        #expect(ran.value)
    }

    @Test func collapsingDisplaysKeepsTheMainDisplaysLayoutAndZoomPriority() {
        var template = WorkspaceTemplateTests().template()
        template.displays.reverse()
        let preferred = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "only", "builtin": "only"]
        )
        #expect(preferred == ["only": "external"])
    }

    @Test func separateDisplaysKeepTheirOwnLayoutAndZoomPriority() {
        let template = WorkspaceTemplateTests().template()
        let preferred = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "desk", "builtin": "laptop"]
        )
        #expect(preferred == ["desk": "external", "laptop": "builtin"])
    }

    private func drain(_ writer: AXWriter) async {
        await withCheckedContinuation { continuation in writer.run { continuation.resume() } }
    }
}
