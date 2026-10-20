import AppKit
import QuartzCore

final class Animator {
    struct Move {
        let window: Window
        let target: CGRect
        let bounds: CGRect
        var from: CGRect?

        init(window: Window, to target: CGRect, bounds: CGRect, from: CGRect? = nil) {
            self.window = window
            self.target = target
            self.bounds = bounds
            self.from = from
        }
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
    private let focusLock = NSLock()
    private var focusGeneration = 0
    private var focusQueues: [pid_t: DispatchQueue] = [:]
    private let makeWriter: (pid_t) -> AXWriter
    private let applyFocus: (Window, () -> Bool) -> Void
    private var timer: Timer?
    private var timing = Timing()
    private var frameRun: FrameRun?
    var onMinimumSize: ((CGWindowID, CGSize) -> Void)?

    init(makeWriter: @escaping (pid_t) -> AXWriter = AXWriter.init,
         applyFocus: @escaping (Window, () -> Bool) -> Void = { $0.focus(ifCurrent: $1) }) {
        self.makeWriter = makeWriter
        self.applyFocus = applyFocus
    }

    func cancelFocus() { focusLock.withLock { focusGeneration += 1 } }

    func focus(_ window: Window, done: @escaping () -> Void = {}) {
        let generation = focusLock.withLock { focusGeneration += 1; return focusGeneration }
        let queue = focusQueues[window.pid]
            ?? DispatchQueue(label: "ouch.focus-write.\(window.pid)", qos: .userInteractive)
        focusQueues[window.pid] = queue
        queue.async { [weak self] in
            guard let self else { return }
            let isCurrent = { self.focusLock.withLock { self.focusGeneration == generation } }
            guard isCurrent() else { return }
            self.applyFocus(window, isCurrent)
            DispatchQueue.main.async {
                guard isCurrent() else { return }
                done()
            }
        }
    }

    func focusSink(_ window: CGWindowID) {
        let generation = focusLock.withLock { focusGeneration += 1; return focusGeneration }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self, self.focusLock.withLock({ self.focusGeneration == generation }) else { return }
            if !WindowServerFocus.focus(pid: getpid(), window: window) {
                DispatchQueue.main.async {
                    guard self.focusLock.withLock({ self.focusGeneration == generation }) else { return }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    func isBusy(_ id: CGWindowID) -> Bool {
        items[id] != nil || landing[id] != nil || (quietUntil[id] ?? 0) > CACurrentMediaTime()
    }

    func destination(_ id: CGWindowID) -> CGRect? { items[id]?.move.target ?? landing[id]?.move.target }

    func isMoving(_ id: CGWindowID, to frame: CGRect) -> Bool {
        (items[id]?.move.target ?? landing[id]?.move.target) == frame
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
        for move in moves {
            let id = move.window.id
            let from: CGRect
            if let running = items[id] {
                from = running.frame(at: now)
            } else if let landed = landing.removeValue(forKey: id) {
                from = move.from ?? landed.move.target
            } else {
                from = move.from ?? move.window.cachedFrame
            }
            cancel(id)
            owners[id] = move.window.pid
            if duration < 0.01 || from.isNull || from.approxEqual(move.target, tolerance: 2) {
                items[id] = nil
                land(move)
            } else {
                items[id] = Item(move: move, from: from, start: now, duration: duration, curve: curve, bounce: bounce)
            }
        }
        if !items.isEmpty && timer == nil {
            let newTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
            frameRun = PerfMonitor.begin("window-move")
            tick()
        }
    }

    func position(_ window: Window, at frame: CGRect) {
        cancel(window.id)
        owners[window.id] = window.pid
        landings += 1
        let number = landings
        landing[window.id] = (.init(window: window, to: frame, bounds: frame), number)
        quiet(window.id)
        writer(window.pid).position(window, at: frame.origin) { [weak self] _ in
            guard let self, self.landing[window.id]?.number == number else { return }
            self.landing[window.id] = nil
            self.quiet(window.id)
        }
    }

    private func writer(_ pid: pid_t) -> AXWriter {
        if let existing = writers[pid] { return existing }
        let created = makeWriter(pid)
        writers[pid] = created
        return created
    }

    var activeWriterPids: Set<pid_t> { Set(writers.keys) }

    func afterPendingWrites(_ completion: @escaping () -> Void) {
        afterPendingWrites(pids: nil, completion)
    }

    func afterPendingWrites(
        pids: Set<pid_t>?, completionQueue: DispatchQueue = .main, _ completion: @escaping () -> Void
    ) {
        let selected = pids.map { ids in ids.compactMap { writers[$0] } } ?? Array(writers.values)
        guard !selected.isEmpty else {
            completionQueue.async(execute: completion)
            return
        }
        let group = DispatchGroup()
        for writer in selected {
            group.enter()
            writer.run { group.leave() }
        }
        group.notify(queue: completionQueue, execute: completion)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        timing.tick(at: now)
        for (id, item) in items {
            if now - item.start >= item.duration {
                items[id] = nil
                land(item.move)
            } else {
                writer(item.move.window.pid).step(item.move.window) { item.frame(at: $0) }
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

    private static func slowApp(_ pid: pid_t, _ stats: AXWriter.Stats) -> PerfMonitor.SlowApp? {
        guard !stats.position.isEmpty,
              let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        let step = (stats.size.isEmpty ? 0 : stats.size.total / Double(stats.size.count))
            + stats.position.total / Double(stats.position.count)
        return .init(bundle: bundle, stepMs: step * 1000,
                     skipped: Double(stats.skipped) / Double(stats.skipped + stats.position.count))
    }

    private func land(_ move: Move) {
        let id = move.window.id
        landings += 1
        let number = landings
        let epoch = epochs[id] ?? 0
        landing[id] = (move, number)
        quietUntil[id] = CACurrentMediaTime() + 0.4
        writer(move.window.pid).land(move.window, at: move.target) { [weak self] wrote in
            guard let self, self.landing[id]?.number == number else { return }
            self.landing[id] = nil
            guard wrote else { return }
            CursorRefresh.soon()
            self.quietUntil[id] = CACurrentMediaTime() + 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.verify(move, epoch: epoch) }
        }
    }

    private func verify(_ move: Move, epoch: Int) {
        let window = move.window
        guard epochs[window.id, default: 0] == epoch, items[window.id] == nil, landing[window.id] == nil,
              !window.placementSuspended else { return }
        quietUntil[window.id] = CACurrentMediaTime() + 0.4
        writer(window.pid).run(for: window.id) { [weak self] isCurrent in
            var actual = window.frame
            guard isCurrent(), !window.placementSuspended, !window.isNativeFullscreen,
                  !window.element.flag(kAXMinimizedAttribute),
                  !actual.isNull, !actual.approxEqual(move.target, tolerance: 2) else { return }
            EnhancedUI.suspend(window.pid)
            defer { EnhancedUI.resume(window.pid) }
            guard isCurrent(), !window.placementSuspended else { return }
            window.setFrame(move.target)
            actual = window.frame
            guard isCurrent(), !window.placementSuspended else { return }
            var minimum: CGSize?
            if !actual.isNull, actual.width > move.target.width + 1 || actual.height > move.target.height + 1 {
                minimum = CGSize(width: actual.width > move.target.width + 1 ? actual.width : 0,
                                 height: actual.height > move.target.height + 1 ? actual.height : 0)
                var origin = move.target.origin
                origin.x = max(move.bounds.minX, min(origin.x, move.bounds.maxX - actual.width))
                origin.y = max(move.bounds.minY, min(origin.y, move.bounds.maxY - actual.height))
                window.setPosition(origin)
            }
            DispatchQueue.main.async {
                guard let self, self.epochs[window.id, default: 0] == epoch else { return }
                self.quietUntil[window.id] = CACurrentMediaTime() + 0.4
                if let minimum { self.onMinimumSize?(window.id, minimum) }
            }
        }
    }
}
