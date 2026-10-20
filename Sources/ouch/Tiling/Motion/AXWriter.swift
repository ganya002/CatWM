import AppKit
import QuartzCore

final class AXWriter {
    private enum Operation {
        case step(CGRect), land(CGRect, done: (Bool) -> Void), position(CGPoint, done: (Bool) -> Void)
        case follow(CGRect, done: (CGSize?) -> Void)
    }
    private struct Pending { let window: Window; let operation: Operation; let epoch: Int }
    struct Stats { var size = Stat(), position = Stat(), land = Stat(), skipped = 0 }

    let pid: pid_t
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [CGWindowID: Pending] = [:]
    private var epochs: [CGWindowID: Int] = [:]
    private var draining = false
    private var stats = Stats()
    private var animating: Set<CGWindowID> = []
    private var lastSize: [CGWindowID: CGSize] = [:]

    init(pid: pid_t) {
        self.pid = pid
        queue = DispatchQueue(label: "ouch.ax.\(pid)", qos: .userInteractive)
    }

    func step(_ window: Window, to frame: CGRect) { submit(window, .step(frame)) }
    func land(_ window: Window, at frame: CGRect, done: @escaping (Bool) -> Void) {
        submit(window, .land(frame, done: done))
    }

    func follow(_ window: Window, to frame: CGRect, done: @escaping (CGSize?) -> Void) {
        submit(window, .follow(frame, done: done))
    }

    func position(_ window: Window, at point: CGPoint, done: @escaping (Bool) -> Void) {
        submit(window, .position(point, done: done))
    }

    func cancel(_ id: CGWindowID) {
        lock.withLock { pending[id] = nil; epochs[id, default: 0] += 1 }
        queue.async { [self] in if animating.remove(id) != nil { EnhancedUI.resume(pid) } }
    }

    func run(_ work: @escaping () -> Void) { queue.async(execute: work) }

    func run(for id: CGWindowID, _ work: @escaping (_ isCurrent: () -> Bool) -> Void) {
        let epoch = lock.withLock { epochs[id] ?? 0 }
        queue.async { [self] in
            let isCurrent = { self.lock.withLock { (self.epochs[id] ?? 0) == epoch } }
            guard isCurrent() else { return }
            work(isCurrent)
        }
    }

    func takeStats() -> Stats {
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

    private func apply(_ item: Pending) {
        let window = item.window
        if window.placementSuspended || window.isNativeFullscreen || window.element.flag(kAXMinimizedAttribute) {
            if animating.remove(window.id) != nil { EnhancedUI.resume(pid) }
            switch item.operation {
            case let .land(_, done), let .position(_, done): DispatchQueue.main.async { done(false) }
            case let .follow(_, done): DispatchQueue.main.async { done(nil) }
            case .step: break
            }
            return
        }
        if animating.insert(window.id).inserted { EnhancedUI.suspend(pid) }
        switch item.operation {
        case let .step(frame):
            var sizeTime = 0.0
            if lastSize[window.id] != frame.size {
                sizeTime = measure { window.setSize(frame.size) }
                lastSize[window.id] = frame.size
            }
            let positionTime = measure { window.setPosition(frame.origin) }
            lock.withLock { if sizeTime > 0 { stats.size.add(sizeTime) }; stats.position.add(positionTime) }
        case let .follow(frame, done):
            var actual: CGSize?
            if lastSize[window.id] != frame.size {
                let sizeTime = measure { window.setSize(frame.size) }
                lastSize[window.id] = frame.size
                actual = window.frame.size
                lock.withLock { stats.size.add(sizeTime) }
            }
            let positionTime = measure { window.setPosition(frame.origin) }
            lock.withLock { stats.position.add(positionTime) }
            DispatchQueue.main.async { done(actual) }
        case let .position(point, done):
            let elapsed = measure { window.setPosition(point) }
            animating.remove(window.id)
            EnhancedUI.resume(pid)
            lock.withLock { stats.position.add(elapsed) }
            DispatchQueue.main.async { done(true) }
        case let .land(frame, done):
            lastSize[window.id] = nil
            let elapsed = measure { window.setFrame(frame) }
            animating.remove(window.id)
            EnhancedUI.resume(pid)
            lock.withLock { stats.land.add(elapsed) }
            DispatchQueue.main.async { done(true) }
        }
    }
}
