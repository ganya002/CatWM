import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import os
import QuartzCore
import Testing
import XCTest

private final class SlowBackend: WindowBackend {
    private struct State {
        var time = 0.0, cost = 0.0, fails = false
        var failures = 0
        var onApplied: (@Sendable () -> Void)?
        var frames: [CGRect] = []
    }
    let inner = FakeBackend()
    private let state = OSAllocatedUnfairLock(initialState: State())

    var time: CFTimeInterval { state.withLock { $0.time } }
    func advance(_ seconds: Double) { state.withLock { $0.time += seconds } }
    func set(cost: Double, fails: Bool = false) { state.withLock { $0.cost = cost; $0.fails = fails } }

    func failNextWrite(onApplied: @escaping @Sendable () -> Void) {
        state.withLock { $0.failures = 1; $0.onApplied = onApplied }
    }

    private func spend() -> Bool {
        state.withLock {
            $0.time += $0.cost
            if $0.failures > 0 { $0.failures -= 1; return false }
            return !$0.fails
        }
    }

    var frames: [CGRect] { state.withLock { $0.frames } }
    func clearFrames() { state.withLock { $0.frames.removeAll() } }
    private func apply(_ window: Window, _ write: () -> Bool) -> Bool {
        guard spend(), write() else { return false }
        let frame = inner.frame(of: window.id)
        let applied = state.withLock { $0.frames.append(frame); return $0.onApplied }
        applied?()
        return true
    }
    func setPosition(_ window: Window, _ point: CGPoint) -> Bool { apply(window) { inner.setPosition(window, point) } }
    func setSize(_ window: Window, _ size: CGSize) -> Bool { apply(window) { inner.setSize(window, size) } }

    func applications() -> [RunningApplicationSnapshot] { inner.applications() }
    func desktop(known: Set<CGWindowID>) -> WindowServerObservation { inner.desktop(known: known) }
    func scan(_ job: WindowScanner.Job, discovered: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
        inner.scan(job, discovered: discovered)
    }
    func focusedWindow(pid: pid_t) -> FocusReader.Result { inner.focusedWindow(pid: pid) }
    func screens() -> [Screen] { inner.screens() }
    func currentSpace(display: String) -> UInt64 { inner.currentSpace(display: display) }
    func isRunning(_ pid: pid_t) -> Bool { inner.isRunning(pid) }
    func frontmostPID() -> pid_t? { inner.frontmostPID() }
    func frame(of window: Window) -> CGRect { inner.frame(of: window) }
    func blocksPlacement(_ window: Window) -> Bool { inner.blocksPlacement(window) }
    func suspendEnhancedUI(_ pid: pid_t) -> Bool { inner.suspendEnhancedUI(pid) }
    func resumeEnhancedUI(_ pid: pid_t) { inner.resumeEnhancedUI(pid) }
    func focus(_ window: Window, ifCurrent: () -> Bool) { inner.focus(window, ifCurrent: ifCurrent) }
    func refreshCursor() { inner.refreshCursor() }
    func close(_ window: Window) -> String { inner.close(window) }
}

@Suite struct AXWriterPredictionTests {
    private let start = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let backend = SlowBackend()
    private let window: Window
    private let writer: AXWriter

    init() throws {
        let id = backend.inner.addWindow(frame: start)
        window = Window(id: id, element: try #require(backend.inner.element(id)), pid: -100,
                        bundleID: nil, backend: backend)
        window.remember(start)
        let backend = backend
        writer = AXWriter(pid: -100, backend: backend, now: { backend.time })
    }

    private func drain() async {
        await withCheckedContinuation { continuation in writer.run { continuation.resume() } }
    }

    @discardableResult
    private func step(_ width: Double) async -> CFTimeInterval? {
        let sampled = SampleLog()
        writer.step(window) { time in
            sampled.record(time)
            return CGRect(x: 100, y: 100, width: width, height: 600)
        }
        await drain()
        return sampled.last
    }

    @Test func aStepIsSampledWhenTheLastWriteSaysItWillLand() async {
        backend.set(cost: 0.01)
        await step(810)
        let now = backend.time
        let sampled = await step(820)
        #expect(abs((sampled ?? 0) - (now + 0.02)) < 1e-9)
    }

    @Test func aWriteThatGetsSlowerMovesTheNextSampleAtOnce() async {
        backend.set(cost: 0.005)
        await step(810)
        await step(820)
        backend.set(cost: 0.015)
        await step(830)
        let before = backend.time
        let sampled = await step(840)
        #expect((sampled ?? 0) - before > 0.024)
    }

    @Test func aFailedWriteDoesNotTeachTheLead() async {
        backend.set(cost: 0.5, fails: true)
        await step(810)
        backend.set(cost: 0)
        let now = backend.time
        #expect(await step(820) == now)
    }

    @Test func aSuccessfulLandingKeepsRecentPredictionForTheNextResize() async {
        backend.set(cost: 0.01)
        await step(810)
        await withCheckedContinuation { continuation in
            writer.land(window, at: CGRect(x: 100, y: 100, width: 810, height: 600)) { _ in continuation.resume() }
        }
        let now = backend.time
        let sampled = await step(820)
        #expect(abs((sampled ?? 0) - (now + 0.02)) < 1e-9)
    }

    @Test func anOldPredictionExpiresWhileTheAppIsIdle() async {
        backend.set(cost: 0.01)
        await step(810)
        backend.advance(2)
        let now = backend.time
        #expect(await step(820) == now)
    }

    @Test func aFailedSizeWriteIsRepeatedWhenLanding() async {
        let target = CGRect(x: 100, y: 100, width: 900, height: 600)
        backend.set(cost: 0, fails: true)
        await step(900)
        backend.set(cost: 0)
        await withCheckedContinuation { continuation in
            writer.land(window, at: target) { _ in continuation.resume() }
        }
        #expect(backend.inner.frame(of: window.id) == target)
    }

    @MainActor @Test func aFailedFinalResizeStillRunsFrameRecovery() async {
        let target = CGRect(x: 100, y: 100, width: 900, height: 600)
        let recovered = XCTestExpectation(description: "failed landing is retried")
        let backend = backend
        let window = window
        backend.failNextWrite {
            if backend.inner.frame(of: window.id) == target { recovered.fulfill() }
        }
        let animator = Animator(backend: backend)
        defer { animator.cancel(window.id) }
        animator.animate([.init(window: window, to: target, bounds: target)], duration: 0)
        let placed = await XCTWaiter.fulfillment(of: [recovered], timeout: 10)
        #expect(placed == .completed)
        #expect(backend.inner.frame(of: window.id) == target)
    }

    @Test func anObservedSizeChangeInvalidatesTheLastAcceptedResize() async {
        await step(810)
        let changed = CGRect(x: 100, y: 100, width: 800, height: 600)
        _ = backend.inner.setSize(window, changed.size)
        window.remember(changed)
        let target = CGRect(x: 100, y: 100, width: 810, height: 600)
        await withCheckedContinuation { continuation in
            writer.land(window, at: target) { _ in continuation.resume() }
        }
        #expect(backend.inner.frame(of: window.id) == target)
    }

    @Test func aGrowingRightTileNeverMovesPastTheScreenEdge() async {
        let source = CGRect(x: 910, y: 38, width: 800, height: 600)
        _ = backend.inner.setPosition(window, source.origin)
        _ = backend.inner.setSize(window, source.size)
        window.remember(source)
        writer.step(window) { _ in CGRect(x: 850, y: 38, width: 860, height: 600) }
        await drain()
        #expect(!backend.frames.isEmpty)
        #expect(backend.frames.allSatisfy { $0.maxX <= 1710 })
    }

    @Test func aShrinkingRightTileNeverMovesPastTheScreenEdge() async {
        writer.step(window) { _ in CGRect(x: 840, y: 38, width: 870, height: 600) }
        await drain()
        backend.clearFrames()
        writer.step(window) { _ in CGRect(x: 910, y: 38, width: 800, height: 600) }
        await drain()
        #expect(backend.frames.allSatisfy { $0.maxX <= 1710 })
    }

    @Test func aStepCancelledBeforeItRunsLeavesNothingLearned() async {
        let gate = DispatchSemaphore(value: 0)
        writer.run { _ = gate.wait(timeout: .now() + 2) }
        backend.set(cost: 0.04)
        let skipped = SampleLog()
        writer.step(window) { time in skipped.record(time); return start.offsetBy(dx: 10, dy: 0) }
        writer.cancel(window.id)
        gate.signal()
        await drain()
        #expect(skipped.last == nil)
        let now = backend.time
        #expect(await step(810) == now)
    }
}

private final class SampleLog: Sendable {
    private let times = OSAllocatedUnfairLock(initialState: [CFTimeInterval]())
    var last: CFTimeInterval? { times.withLock { $0.last } }
    func record(_ time: CFTimeInterval) { times.withLock { $0.append(time) } }
}
