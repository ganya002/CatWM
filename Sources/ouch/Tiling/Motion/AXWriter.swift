import AppKit
import QuartzCore

final class AXWriter {
    private enum Op { case step(CGRect), land(CGRect, done: (Bool) -> Void) }
    private struct Pending { let window: Window; let op: Op; let epoch: Int }
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

    func step(_ w: Window, to frame: CGRect) { submit(w, .step(frame)) }
    func land(_ w: Window, at frame: CGRect, done: @escaping (Bool) -> Void) { submit(w, .land(frame, done: done)) }

    func cancel(_ id: CGWindowID) {
        lock.withLock { pending[id] = nil; epochs[id, default: 0] += 1 }
        queue.async { [self] in if animating.remove(id) != nil { EnhancedUI.resume(pid) } }
    }

    func run(_ f: @escaping () -> Void) { queue.async(execute: f) }

    func run(for id: CGWindowID, _ f: @escaping (_ isCurrent: () -> Bool) -> Void) {
        let epoch = lock.withLock { epochs[id] ?? 0 }
        queue.async { [self] in
            let isCurrent = { self.lock.withLock { (self.epochs[id] ?? 0) == epoch } }
            guard isCurrent() else { return }
            f(isCurrent)
        }
    }

    func takeStats() -> Stats {
        lock.withLock { defer { stats = Stats() }; return stats }
    }

    private func submit(_ w: Window, _ op: Op) {
        let start = lock.withLock { () -> Bool in
            if case .step = pending[w.id]?.op { stats.skipped += 1 }
            pending[w.id] = Pending(window: w, op: op, epoch: epochs[w.id] ?? 0)
            defer { draining = true }
            return !draining
        }
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            let batch = lock.withLock { () -> [Pending] in
                let b = Array(pending.values)
                pending = [:]
                if b.isEmpty { draining = false }
                return b
            }
            if batch.isEmpty { return }
            for p in batch where lock.withLock({ epochs[p.window.id] ?? 0 }) == p.epoch { apply(p) }
        }
    }

    private func apply(_ p: Pending) {
        let w = p.window
        if w.placementSuspended || w.isNativeFullscreen || w.element.bool(kAXMinimizedAttribute) == true {
            if animating.remove(w.id) != nil { EnhancedUI.resume(pid) }
            if case let .land(_, done) = p.op { DispatchQueue.main.async { done(false) } }
            return
        }
        if animating.insert(w.id).inserted { EnhancedUI.suspend(pid) }
        switch p.op {
        case let .step(f):
            var s = 0.0
            if lastSize[w.id] != f.size {
                s = measure { w.setSize(f.size) }
                lastSize[w.id] = f.size
            }
            let o = measure { w.setPosition(f.origin) }
            lock.withLock { if s > 0 { stats.size.add(s) }; stats.position.add(o) }
        case let .land(f, done):
            lastSize[w.id] = nil
            let t = measure { w.setFrame(f) }
            animating.remove(w.id)
            EnhancedUI.resume(pid)
            lock.withLock { stats.land.add(t) }
            DispatchQueue.main.async { done(true) }
        }
    }
}
