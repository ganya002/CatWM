import AppKit
import QuartzCore

package final class AXWriter {
    private enum Operation {
        case step(notBefore: CFTimeInterval, frame: (CFTimeInterval) -> CGRect)
        case land(CGRect, done: (Bool) -> Void), position(CGPoint, done: (Bool) -> Void)
        case follow(CGRect, done: (CGSize?) -> Void)
    }
    private struct Pending {
        let window: Window
        let operation: Operation
        let epoch: Int
        let releasesSpace: Bool
    }
    private struct Write { var size = 0.0, position = 0.0, applied = true }
    package struct Stats { var size = Stat(), position = Stat(), land = Stat(), skipped = 0 }

    package let pid: pid_t
    private let backend: any WindowBackend
    private let now: () -> CFTimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [CGWindowID: Pending] = [:]
    private var epochs: [CGWindowID: Int] = [:]
    private var draining = false
    private var stats = Stats()
    private var animating: Set<CGWindowID> = []
    private var lastSize: [CGWindowID: CGSize] = [:]
    private var stepCosts: [CGWindowID: WindowWriteCost] = [:]
    private var enhancedUI: EnhancedUI

    package init(pid: pid_t, backend: any WindowBackend = AXBackend.shared,
                 now: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.pid = pid
        self.backend = backend
        self.now = now
        enhancedUI = EnhancedUI(pid: pid, backend: backend)
        queue = DispatchQueue(label: "catwm.ax.\(pid)", qos: .userInteractive)
    }

    package func step(_ window: Window, notBefore: CFTimeInterval = 0, releasesSpace: Bool = false,
                      to frame: @escaping (CFTimeInterval) -> CGRect) {
        submit(window, .step(notBefore: notBefore, frame: frame), releasesSpace: releasesSpace)
    }
    package func land(_ window: Window, at frame: CGRect, done: @escaping (Bool) -> Void) {
        submit(window, .land(frame, done: done))
    }

    package func follow(_ window: Window, to frame: CGRect, done: @escaping (CGSize?) -> Void) {
        submit(window, .follow(frame, done: done))
    }

    package func position(_ window: Window, at point: CGPoint, done: @escaping (Bool) -> Void) {
        submit(window, .position(point, done: done))
    }

    package func cancel(_ id: CGWindowID) {
        lock.withLock { pending[id] = nil; epochs[id, default: 0] += 1 }
        queue.async { [self] in
            lastSize[id] = nil
            if animating.remove(id) != nil { enhancedUI.resume() }
        }
    }

    package func forget(_ id: CGWindowID) {
        queue.async { [self] in
            stepCosts[id] = nil
            lock.withLock { epochs[id] = nil }
        }
    }

    package func run(_ work: @escaping () -> Void) { queue.async(execute: work) }

    package func suspendEnhancedUI() { enhancedUI.suspend() }
    package func resumeEnhancedUI() { enhancedUI.resume() }

    package func run(for id: CGWindowID, _ work: @escaping (_ isCurrent: () -> Bool) -> Void) {
        let epoch = lock.withLock { epochs[id] ?? 0 }
        queue.async { [self] in
            let isCurrent = { self.lock.withLock { (self.epochs[id] ?? 0) == epoch } }
            guard isCurrent() else { return }
            work(isCurrent)
        }
    }

    package func takeStats() -> Stats {
        lock.withLock { defer { stats = Stats() }; return stats }
    }

    private func submit(_ window: Window, _ operation: Operation, releasesSpace: Bool = false) {
        let start = lock.withLock { () -> Bool in
            if case .step = pending[window.id]?.operation { stats.skipped += 1 }
            pending[window.id] = Pending(window: window, operation: operation,
                                         epoch: epochs[window.id] ?? 0, releasesSpace: releasesSpace)
            defer { draining = true }
            return !draining
        }
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            let batch = lock.withLock { () -> [Pending] in
                let items = pending.values.sorted {
                    $0.releasesSpace == $1.releasesSpace ? $0.window.id < $1.window.id : $0.releasesSpace
                }
                pending = [:]
                if items.isEmpty { draining = false }
                return items
            }
            if batch.isEmpty { return }
            for item in batch where lock.withLock({ epochs[item.window.id] ?? 0 }) == item.epoch { apply(item) }
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
            lastSize[window.id] = sized.applied ? frame.size : nil
        }
        let previous = lastSize[window.id]
        guard previous != frame.size || window.cachedFrame.size != frame.size else { move(); return result }
        switch WindowFrameOrder(from: window.cachedFrame, to: frame) {
        case .positionFirst: move(); resize()
        case .sizeFirst: resize(); move()
        }
        return result
    }

    private func apply(_ item: Pending) {
        let window = item.window
        let stepFrame: CGRect
        if case let .step(presentation, frameAt) = item.operation {
            let start = now()
            stepFrame = frameAt(max(presentation, start + (stepCosts[window.id]?.lead(at: start) ?? 0)))
            guard window.cachedFrame != stepFrame else { return }
        } else {
            stepFrame = .null
        }
        if window.placementSuspended || backend.blocksPlacement(window) {
            if animating.remove(window.id) != nil { enhancedUI.resume() }
            switch item.operation {
            case let .land(_, done), let .position(_, done): DispatchQueue.main.async { done(false) }
            case let .follow(_, done): DispatchQueue.main.async { done(nil) }
            case .step: break
            }
            return
        }
        if animating.insert(window.id).inserted { enhancedUI.suspend() }
        switch item.operation {
        case .step:
            let written = write(window, stepFrame)
            if written.applied {
                stepCosts[window.id, default: WindowWriteCost()].add(written.size + written.position, at: now())
            }
            lock.withLock {
                if written.size > 0 { stats.size.add(written.size) }
                stats.position.add(written.position)
            }
        case let .follow(frame, done):
            let resized = lastSize[window.id] != frame.size
            let written = write(window, frame)
            let actual = resized ? window.frame.size : nil
            lock.withLock { if resized { stats.size.add(written.size) }; stats.position.add(written.position) }
            DispatchQueue.main.async { done(actual) }
        case let .position(point, done):
            let written = attempt { window.setPosition(point) }
            animating.remove(window.id)
            enhancedUI.resume()
            lock.withLock { stats.position.add(written.seconds) }
            DispatchQueue.main.async { done(written.applied) }
        case let .land(frame, done):
            let written = write(window, frame)
            lastSize[window.id] = nil
            animating.remove(window.id)
            enhancedUI.resume()
            lock.withLock { stats.land.add(written.size + written.position) }
            DispatchQueue.main.async { done(written.applied) }
        }
    }
}
