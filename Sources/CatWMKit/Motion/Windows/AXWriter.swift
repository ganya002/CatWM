import AppKit
import os
import QuartzCore

package final class AXWriter: Sendable {
    private enum Operation: Sendable {
        case step(notBefore: CFTimeInterval, frame: @Sendable (CFTimeInterval) -> CGRect)
        case land(CGRect, done: @MainActor (Bool) -> Void), position(CGPoint, done: @MainActor (Bool) -> Void)
        case follow(CGRect, done: @MainActor (CGSize?) -> Void)
    }
    private struct Pending: Sendable {
        let window: Window
        let operation: Operation
        let epoch: Int
        let releasesSpace: Bool
    }
    private struct Write { var size = 0.0, position = 0.0, applied = true }
    package struct Stats: Sendable { var size = Stat(), position = Stat(), land = Stat(), skipped = 0 }

    private struct State: Sendable {
        var pending: [CGWindowID: Pending] = [:]
        var epochs: [CGWindowID: Int] = [:]
        var draining = false
        var stats = Stats()
        var animating: Set<CGWindowID> = []
        var lastSize: [CGWindowID: CGSize] = [:]
        var stepCosts: [CGWindowID: WindowWriteCost] = [:]
    }

    package let pid: pid_t
    private let backend: any WindowBackend
    private let now: @Sendable () -> CFTimeInterval
    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let enhancedUI: EnhancedUI

    package init(pid: pid_t, backend: any WindowBackend = AXBackend.shared,
                 now: @escaping @Sendable () -> CFTimeInterval = CACurrentMediaTime) {
        self.pid = pid
        self.backend = backend
        self.now = now
        enhancedUI = EnhancedUI(pid: pid, backend: backend)
        queue = DispatchQueue(label: "catwm.ax.\(pid)", qos: .userInteractive)
    }

    package func step(_ window: Window, notBefore: CFTimeInterval = 0, releasesSpace: Bool = false,
                      to frame: @escaping @Sendable (CFTimeInterval) -> CGRect) {
        submit(window, .step(notBefore: notBefore, frame: frame), releasesSpace: releasesSpace)
    }
    package func land(_ window: Window, at frame: CGRect, done: @escaping @MainActor (Bool) -> Void) {
        submit(window, .land(frame, done: done))
    }

    package func follow(_ window: Window, to frame: CGRect, done: @escaping @MainActor (CGSize?) -> Void) {
        submit(window, .follow(frame, done: done))
    }

    package func position(_ window: Window, at point: CGPoint, done: @escaping @MainActor (Bool) -> Void) {
        submit(window, .position(point, done: done))
    }

    package func cancel(_ id: CGWindowID) {
        state.withLock { $0.pending[id] = nil; $0.epochs[id, default: 0] += 1 }
        queue.async { [self] in
            let wasAnimating = state.withLock { state in
                state.lastSize[id] = nil
                return state.animating.remove(id) != nil
            }
            if wasAnimating { enhancedUI.resume() }
        }
    }

    package func forget(_ id: CGWindowID) {
        queue.async { [self] in
            state.withLock { $0.stepCosts[id] = nil; $0.epochs[id] = nil }
        }
    }

    package func run(_ work: @escaping @Sendable () -> Void) { queue.async(execute: work) }

    package func suspendEnhancedUI() { enhancedUI.suspend() }
    package func resumeEnhancedUI() { enhancedUI.resume() }

    package func run(for id: CGWindowID, _ work: @escaping @Sendable (_ isCurrent: () -> Bool) -> Void) {
        let epoch = state.withLock { $0.epochs[id] ?? 0 }
        queue.async { [self] in
            let isCurrent = { self.state.withLock { ($0.epochs[id] ?? 0) == epoch } }
            guard isCurrent() else { return }
            work(isCurrent)
        }
    }

    package func takeStats() -> Stats {
        state.withLock { state in defer { state.stats = Stats() }; return state.stats }
    }

    private func submit(_ window: Window, _ operation: Operation, releasesSpace: Bool = false) {
        let start = state.withLock { state -> Bool in
            if case .step = state.pending[window.id]?.operation { state.stats.skipped += 1 }
            state.pending[window.id] = Pending(window: window, operation: operation,
                                               epoch: state.epochs[window.id] ?? 0, releasesSpace: releasesSpace)
            defer { state.draining = true }
            return !state.draining
        }
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            let batch = state.withLock { state -> [Pending] in
                let items = state.pending.values.sorted {
                    $0.releasesSpace == $1.releasesSpace ? $0.window.id < $1.window.id : $0.releasesSpace
                }
                state.pending = [:]
                if items.isEmpty { state.draining = false }
                return items
            }
            if batch.isEmpty { return }
            for item in batch where state.withLock({ $0.epochs[item.window.id] ?? 0 }) == item.epoch { apply(item) }
        }
    }

    private func measure(_ body: () -> Void) -> Double {
        let start = now()
        body()
        return now() - start
    }

    private func attempt(_ write: () -> Bool) -> (seconds: Double, applied: Bool) {
        var applied = false
        let seconds = measure { applied = write() }
        return (seconds, applied)
    }

    private func write(_ window: Window, _ frame: CGRect) -> Write {
        var result = Write()
        func move() {
            let moved = attempt { window.setPosition(frame.origin) }
            result.position += moved.seconds
            result.applied = result.applied && moved.applied
        }
        func resize() {
            let sized = attempt { window.setSize(frame.size) }
            result.size += sized.seconds
            result.applied = result.applied && sized.applied
            state.withLock { $0.lastSize[window.id] = sized.applied ? frame.size : nil }
        }
        let previous = state.withLock { $0.lastSize[window.id] }
        guard previous != frame.size || window.cachedFrame.size != frame.size else { move(); return result }
        switch WindowFrameOrder(from: window.cachedFrame, to: frame) {
        case .positionFirst: move(); resize()
        case .sizeFirst: resize(); move()
        }
        return result
    }

    private func refuse(_ item: Pending) {
        if state.withLock({ $0.animating.remove(item.window.id) }) != nil { enhancedUI.resume() }
        switch item.operation {
        case let .land(_, done), let .position(_, done): DispatchQueue.main.async { done(false) }
        case let .follow(_, done): DispatchQueue.main.async { done(nil) }
        case .step: break
        }
    }

    private func record(step written: Write, for window: Window) {
        let finished = written.applied ? now() : nil
        state.withLock { state in
            if let finished {
                state.stepCosts[window.id, default: WindowWriteCost()]
                    .add(written.size + written.position, at: finished)
            }
            if written.size > 0 { state.stats.size.add(written.size) }
            state.stats.position.add(written.position)
        }
    }

    private func apply(_ item: Pending) {
        let window = item.window
        let stepFrame: CGRect
        if case let .step(presentation, frameAt) = item.operation {
            let start = now()
            let lead = state.withLock { $0.stepCosts[window.id]?.lead(at: start) ?? 0 }
            stepFrame = frameAt(max(presentation, start + lead))
            guard window.cachedFrame != stepFrame else { return }
        } else {
            stepFrame = .null
        }
        if window.placementSuspended || backend.blocksPlacement(window) { return refuse(item) }
        if state.withLock({ $0.animating.insert(window.id).inserted }) { enhancedUI.suspend() }
        switch item.operation {
        case .step:
            let written = write(window, stepFrame)
            record(step: written, for: window)
        case let .follow(frame, done):
            let resized = state.withLock { $0.lastSize[window.id] } != frame.size
            let written = write(window, frame)
            let actual = resized ? window.frame.size : nil
            state.withLock { state in
                if resized { state.stats.size.add(written.size) }
                state.stats.position.add(written.position)
            }
            DispatchQueue.main.async { done(actual) }
        case let .position(point, done):
            let written = attempt { window.setPosition(point) }
            state.withLock { state in
                state.animating.remove(window.id)
                state.stats.position.add(written.seconds)
            }
            enhancedUI.resume()
            DispatchQueue.main.async { done(written.applied) }
        case let .land(frame, done):
            let written = write(window, frame)
            state.withLock { state in
                state.lastSize[window.id] = nil
                state.animating.remove(window.id)
                state.stats.land.add(written.size + written.position)
            }
            enhancedUI.resume()
            DispatchQueue.main.async { done(written.applied) }
        }
    }
}
