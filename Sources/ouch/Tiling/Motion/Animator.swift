import AppKit
import QuartzCore

final class Animator {
    struct Move {
        let window: Window
        let to: CGRect
        let bounds: CGRect
        var from: CGRect? = nil
    }

    struct Item {
        let move: Move
        let from: CGRect
        let start: CFTimeInterval
        let duration: Double
        let curve: AnimationCurve
        let bounce: Double
    }

    private var items: [CGWindowID: Item] = [:]
    private var landing: [CGWindowID: (move: Move, number: Int)] = [:]
    private var landings = 0
    private var quietUntil: [CGWindowID: CFTimeInterval] = [:]
    private var writers: [pid_t: AXWriter] = [:]
    private var owners: [CGWindowID: pid_t] = [:]
    private var epochs: [CGWindowID: Int] = [:]
    private var timer: Timer?
    private var timing = Timing()
    private var frameRun: FrameRun?
    var onMinimumSize: ((CGWindowID, CGSize) -> Void)?

    func isBusy(_ id: CGWindowID) -> Bool {
        items[id] != nil || landing[id] != nil || (quietUntil[id] ?? 0) > CACurrentMediaTime()
    }

    func isMoving(_ id: CGWindowID, to frame: CGRect) -> Bool {
        (items[id]?.move.to ?? landing[id]?.move.to) == frame
    }

    func cancel(_ id: CGWindowID) {
        epochs[id, default: 0] += 1
        let item = items.removeValue(forKey: id), landed = landing.removeValue(forKey: id)
        guard let pid = item?.move.window.pid ?? landed?.move.window.pid ?? owners[id] else { return }
        writer(pid).cancel(id)
    }

    func quiet(_ id: CGWindowID, for seconds: Double = 0.4) {
        quietUntil[id] = CACurrentMediaTime() + seconds
    }

    func animate(_ moves: [Move], duration: Double, curve: AnimationCurve = .easeOut, bounce: Double = 0) {
        let now = CACurrentMediaTime()
        for m in moves {
            let id = m.window.id
            let from: CGRect
            if let running = items[id] {
                from = running.frame(at: now)
            } else if let landed = landing.removeValue(forKey: id) {
                from = m.from ?? landed.move.to
            } else {
                from = m.from ?? m.window.cachedFrame
            }
            cancel(id)
            owners[id] = m.window.pid
            if duration < 0.01 || from.isNull || from.approxEqual(m.to, tolerance: 2) {
                items[id] = nil
                land(m)
            } else {
                items[id] = Item(move: m, from: from, start: now, duration: duration, curve: curve, bounce: bounce)
            }
        }
        if !items.isEmpty && timer == nil {
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            frameRun = PerfMonitor.begin("window-move")
            tick()
        }
    }

    private func writer(_ pid: pid_t) -> AXWriter {
        if let w = writers[pid] { return w }
        let w = AXWriter(pid: pid)
        writers[pid] = w
        return w
    }

    var activeWriterPids: Set<pid_t> { Set(writers.keys) }

    func afterPendingWrites(_ completion: @escaping () -> Void) {
        afterPendingWrites(pids: nil, completion)
    }

    func afterPendingWrites(pids: Set<pid_t>?, _ completion: @escaping () -> Void) {
        let selected = pids.map { ids in ids.compactMap { writers[$0] } } ?? Array(writers.values)
        guard !selected.isEmpty else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        let group = DispatchGroup()
        for writer in selected {
            group.enter()
            writer.run { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        timing.tick(at: now)
        for (id, item) in items {
            if now - item.start >= item.duration {
                items[id] = nil
                land(item.move)
            } else {
                writer(item.move.window.pid).step(item.move.window, to: item.frame(at: now))
            }
        }
        timing.ticks.add(CACurrentMediaTime() - now)
        if items.isEmpty {
            timer?.invalidate(); timer = nil
            let stats = writers.map { ($0.key, $0.value.takeStats()) }
            frameRun?.end(apps: stats.compactMap(Self.slowApp))
            frameRun = nil
            timing.log(stats)
            timing = Timing()
        }
    }

    private static func slowApp(_ pid: pid_t, _ s: AXWriter.Stats) -> PerfMonitor.SlowApp? {
        guard s.position.count > 0, let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        let step = (s.size.count > 0 ? s.size.total / Double(s.size.count) : 0) + s.position.total / Double(s.position.count)
        return .init(bundle: bundle, stepMs: step * 1000, skipped: Double(s.skipped) / Double(s.skipped + s.position.count))
    }

    private func land(_ m: Move) {
        let id = m.window.id
        landings += 1
        let number = landings
        let epoch = epochs[id] ?? 0
        landing[id] = (m, number)
        quietUntil[id] = CACurrentMediaTime() + 0.4
        writer(m.window.pid).land(m.window, at: m.to) { [weak self] wrote in
            guard let self, self.landing[id]?.number == number else { return }
            self.landing[id] = nil
            guard wrote else { return }
            CursorRefresh.soon()
            self.quietUntil[id] = CACurrentMediaTime() + 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.verify(m, epoch: epoch) }
        }
    }

    private func verify(_ m: Move, epoch: Int) {
        let w = m.window
        guard epochs[w.id, default: 0] == epoch, items[w.id] == nil, landing[w.id] == nil,
              !w.placementSuspended else { return }
        quietUntil[w.id] = CACurrentMediaTime() + 0.4
        writer(w.pid).run(for: w.id) { [weak self] isCurrent in
            var actual = w.frame
            guard isCurrent(), !w.placementSuspended, !w.isNativeFullscreen,
                  w.element.bool(kAXMinimizedAttribute) != true,
                  !actual.isNull, !actual.approxEqual(m.to, tolerance: 2) else { return }
            EnhancedUI.suspend(w.pid)
            defer { EnhancedUI.resume(w.pid) }
            guard isCurrent(), !w.placementSuspended else { return }
            w.setFrame(m.to)
            actual = w.frame
            guard isCurrent(), !w.placementSuspended else { return }
            var minimum: CGSize?
            if !actual.isNull, actual.width > m.to.width + 1 || actual.height > m.to.height + 1 {
                minimum = CGSize(width: actual.width > m.to.width + 1 ? actual.width : 0,
                                 height: actual.height > m.to.height + 1 ? actual.height : 0)
                var o = m.to.origin
                o.x = max(m.bounds.minX, min(o.x, m.bounds.maxX - actual.width))
                o.y = max(m.bounds.minY, min(o.y, m.bounds.maxY - actual.height))
                w.setPosition(o)
            }
            DispatchQueue.main.async {
                guard let self, self.epochs[w.id, default: 0] == epoch else { return }
                self.quietUntil[w.id] = CACurrentMediaTime() + 0.4
                if let minimum { self.onMinimumSize?(w.id, minimum) }
            }
        }
    }
}
