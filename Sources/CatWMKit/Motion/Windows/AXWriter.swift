import AppKit
import QuartzCore

package final class AXWriter {
    private enum Operation {
        case step(notBefore: CFTimeInterval, frame: (CFTimeInterval) -> CGRect)
        case land(CGRect, done: (Bool) -> Void), position(CGPoint, done: (Bool) -> Void)
        case follow(CGRect, done: (CGSize?) -> Void)
    }
    private struct Pending { let window: Window; let operation: Operation; let epoch: Int }
    package struct Stats { var size = Stat(), position = Stat(), land = Stat(), skipped = 0 }

    package let pid: pid_t
    private let backend: any WindowBackend
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [CGWindowID: Pending] = [:]
    private var epochs: [CGWindowID: Int] = [:]
    private var draining = false
    private var stats = Stats()
    private var animating: Set<CGWindowID> = []
    private var lastSize: [CGWindowID: CGSize] = [:]
    private var stepCosts: [CGWindowID: StepCost] = [:]
    private var enhancedUI: EnhancedUI

    package init(pid: pid_t, backend: any WindowBackend = AXBackend.shared) {
        self.pid = pid
        self.backend = backend
        enhancedUI = EnhancedUI(pid: pid, backend: backend)
        queue = DispatchQueue(label: "catwm.ax.\(pid)", qos: .userInteractive)
    }

    package func step(_ window: Window, notBefore: CFTimeInterval = 0, to frame: @escaping (CFTimeInterval) -> CGRect) {
        submit(window, .step(notBefore: notBefore, frame: frame))
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

    private func submit(_ window: Window, _ operation: Operation) {
        let start = lock.withLock { () -> Bool in
            if case .step = pending[window.id]?.operation { stats.skipped += 1 }
            pending[window.id] = Pending(window: window, operation: operation, epoch: epochs[window.id] ?? 0)
            defer { draining = true }
            return !draining
        }
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            let batch = lock.withLock { () -> [Pending] in
                let items = Array(pending.values)
                pending = [:]
                if items.isEmpty { draining = false }
                return items
            }
            if batch.isEmpty { return }
            for item in batch where lock.withLock({ epochs[item.window.id] ?? 0 }) == item.epoch { apply(item) }
        }
    }

    private func write(_ window: Window, _ frame: CGRect) -> (size: Double, position: Double) {
        let previous = lastSize[window.id]
        lastSize[window.id] = frame.size
        guard previous != frame.size else { return (0, measure { window.setPosition(frame.origin) }) }
        let shrinks = previous.map { frame.size.width <= $0.width && frame.size.height <= $0.height } ?? false
        if shrinks {
            let positionTime = measure { window.setPosition(frame.origin) }
            return (measure { window.setSize(frame.size) }, positionTime)
        }
        let rises = !window.cachedFrame.isNull && frame.minY < window.cachedFrame.minY
        var sizeTime = measure { window.setSize(frame.size) }
        let positionTime = measure { window.setPosition(frame.origin) }
        if rises { sizeTime += measure { window.setSize(frame.size) } }
        return (sizeTime, positionTime)
    }

    private func apply(_ item: Pending) {
        let window = item.window
        let stepFrame: CGRect
        if case let .step(presentation, frameAt) = item.operation {
            stepFrame = frameAt(max(presentation, CACurrentMediaTime() + (stepCosts[window.id]?.lead ?? 0)))
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
            let (sizeTime, positionTime) = write(window, stepFrame)
            stepCosts[window.id, default: StepCost()].add(sizeTime + positionTime)
            lock.withLock { if sizeTime > 0 { stats.size.add(sizeTime) }; stats.position.add(positionTime) }
        case let .follow(frame, done):
            let resized = lastSize[window.id] != frame.size
            let (sizeTime, positionTime) = write(window, frame)
            let actual = resized ? window.frame.size : nil
            lock.withLock { if resized { stats.size.add(sizeTime) }; stats.position.add(positionTime) }
            DispatchQueue.main.async { done(actual) }
        case let .position(point, done):
            let elapsed = measure { window.setPosition(point) }
            animating.remove(window.id)
            enhancedUI.resume()
            lock.withLock { stats.position.add(elapsed) }
            DispatchQueue.main.async { done(true) }
        case let .land(frame, done):
            let sized = lastSize.removeValue(forKey: window.id) == frame.size
            stepCosts[window.id] = nil
            let elapsed = measure { sized ? window.setPosition(frame.origin) : window.setFrame(frame) }
            animating.remove(window.id)
            enhancedUI.resume()
            lock.withLock { stats.land.add(elapsed) }
            DispatchQueue.main.async { done(true) }
        }
    }
}
