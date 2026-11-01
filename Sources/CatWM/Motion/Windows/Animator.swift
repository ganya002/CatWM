import AppKit
import Foundation
import os
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

    private var items: [CGWindowID: Item] = [:]
    private var landing: [CGWindowID: (move: Move, number: Int)] = [:]
    private var landings = 0
    private var quietUntil: [CGWindowID: CFTimeInterval] = [:]
    private var following = FollowedMoves()
    private var writers: [pid_t: AXWriter] = [:]
    private var owners: [CGWindowID: pid_t] = [:]
    private var epochs: [CGWindowID: Int] = [:], epochCount = 0
    private let focusLock = NSLock()
    private var focusGeneration = 0
    private var focusQueues: [pid_t: DispatchQueue] = [:]
    private let backend: any WindowBackend
    private let makeWriter: (pid_t) -> AXWriter
    private let applyFocus: (Window, () -> Bool) -> Void
    private var timer: Timer?
    private var timing = Timing()
    private var frameRun: FrameRun?
    var onMinimumSize: ((CGWindowID, CGSize) -> Void)?
    var onTopRefused: ((_ target: CGRect, _ actual: CGRect) -> Void)?
    var onLanded: (() -> Void)?

    init(backend: any WindowBackend = AXBackend.shared, makeWriter: ((pid_t) -> AXWriter)? = nil,
         applyFocus: @escaping (Window, () -> Bool) -> Void = { $0.focus(ifCurrent: $1) }) {
        self.backend = backend
        self.makeWriter = makeWriter ?? { AXWriter(pid: $0, backend: backend) }
        self.applyFocus = applyFocus
    }

    func cancelFocus() { focusLock.withLock { focusGeneration += 1 } }

    func focus(_ window: Window, done: @escaping () -> Void = {}) {
        let generation = focusLock.withLock { focusGeneration += 1; return focusGeneration }
        let queue = focusQueues[window.pid]
            ?? DispatchQueue(label: "catwm.focus-write.\(window.pid)", qos: .userInteractive)
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
        items[id] != nil || landing[id] != nil || following[id] != nil || (quietUntil[id] ?? 0) > CACurrentMediaTime()
    }

    func destination(_ id: CGWindowID) -> CGRect? {
        items[id]?.move.target ?? landing[id]?.move.target ?? following[id]?.target
    }

    func isMoving(_ id: CGWindowID, to frame: CGRect) -> Bool { destination(id) == frame }

    func cancel(_ id: CGWindowID) {
        nextEpoch(for: id)
        following.remove(id)
        let item = items.removeValue(forKey: id), landed = landing.removeValue(forKey: id)
        guard let pid = item?.move.window.pid ?? landed?.move.window.pid ?? owners[id] else { return }
        writers[pid]?.cancel(id)
    }

    func quiet(_ id: CGWindowID, for seconds: Double = 0.4) {
        quietUntil[id] = CACurrentMediaTime() + seconds
    }

    func animate(_ moves: [Move], duration: Double, curve: AnimationCurve = .easeOut, bounce: Double = 0) {
        animate(moves, spec: MotionSpec(duration: duration, curve: curve, bounce: bounce))
    }

    func animate(_ moves: [Move], spec: MotionSpec) {
        let now = CACurrentMediaTime()
        let duration = spec.duration
        for move in moves {
            let id = move.window.id
            let from: CGRect
            var velocity: [Double]?
            if let running = items[id] {
                from = running.frame(at: now)
                velocity = running.velocity(at: now)
            } else if let landed = landing.removeValue(forKey: id) {
                from = move.from ?? landed.move.target
            } else if let followed = following[id] {
                from = move.from ?? followed.target
            } else {
                from = move.from ?? move.window.cachedFrame
            }
            cancel(id)
            owners[id] = move.window.pid
            if duration < 0.01 || from.isNull || from.approxEqual(move.target, tolerance: 2) {
                items[id] = nil
                land(move)
            } else {
                items[id] = Item(move: move, from: from, start: now, spec: spec, velocity: velocity)
            }
        }
        if !items.isEmpty && timer == nil {
            let newTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
            frameRun = PerfMonitor.shared.begin("window-move")
            tick()
        }
    }

    func follow(_ moves: [Move]) {
        for move in moves {
            let id = move.window.id
            if items[id] != nil || landing[id] != nil { cancel(id) }
            owners[id] = move.window.pid
            following.add(move)
            quietUntil[id] = CACurrentMediaTime() + 0.4
            writer(move.window.pid).follow(move.window, to: move.target) { [weak self] actual in
                guard let self, let minimum = self.following.minimum(after: move, actual: actual) else { return }
                self.onMinimumSize?(move.window.id, minimum)
            }
        }
    }

    func endFollow() { following.removeAll().forEach(land) }

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
        let epoch = epochs[id] ?? nextEpoch(for: id)
        landing[id] = (move, number)
        quietUntil[id] = CACurrentMediaTime() + 0.4
        writer(move.window.pid).land(move.window, at: move.target) { [weak self] wrote in
            guard let self, self.landing[id]?.number == number else { return }
            self.landing[id] = nil
            guard wrote else { return }
            self.onLanded?()
            self.quietUntil[id] = CACurrentMediaTime() + 0.4
            DispatchQueue.main.asyncAfter( // style-ok: an app that ignores a write sends no event
                deadline: .now() + 0.12
            ) { [weak self] in self?.verify(move, epoch: epoch) }
        }
    }

    private func verify(_ move: Move, epoch: Int) {
        let window = move.window
        guard epochs[window.id, default: 0] == epoch, items[window.id] == nil, landing[window.id] == nil,
              !window.placementSuspended else { return }
        quietUntil[window.id] = CACurrentMediaTime() + 0.4
        let writer = writer(window.pid)
        writer.run(for: window.id) { [weak self, backend] isCurrent in
            var actual = window.frame
            guard isCurrent(), !window.placementSuspended, !backend.blocksPlacement(window),
                  !actual.isNull, !actual.approxEqual(move.target, tolerance: 2) else { return }
            writer.suspendEnhancedUI()
            defer { writer.resumeEnhancedUI() }
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
            DispatchQueue.main.async { [actual] in
                guard let self, self.epochs[window.id, default: 0] == epoch else { return }
                self.quietUntil[window.id] = CACurrentMediaTime() + 0.4
                if let minimum { self.onMinimumSize?(window.id, minimum) }
                if !actual.isNull, actual.minY > move.target.minY + 1 { self.onTopRefused?(move.target, actual) }
            }
        }
    }
}

extension Animator {
    private func writer(_ pid: pid_t) -> AXWriter {
        if let existing = writers[pid] { return existing }
        let created = makeWriter(pid)
        writers[pid] = created
        return created
    }

    func forget(_ id: CGWindowID) {
        cancel(id)
        if let pid = owners.removeValue(forKey: id) { writers[pid]?.forget(id) }
        epochs[id] = nil
        quietUntil[id] = nil
    }

    @discardableResult
    private func nextEpoch(for id: CGWindowID) -> Int {
        epochCount += 1
        epochs[id] = epochCount
        return epochCount
    }

    func terminated(_ pid: pid_t) {
        writers[pid] = nil
        focusQueues[pid] = nil
    }
}

extension Animator {
    func retarget(_ window: Window, to frame: CGRect) -> Bool {
        guard let running = items[window.id] else { return false }
        let target = [frame.minX, frame.minY, frame.width, frame.height]
        let tracks = zip(running.tracks, target).map { $0.retargeted(to: $1) }
        items[window.id] = Item(move: .init(window: window, to: frame, bounds: frame), tracks: tracks,
                                start: running.start, duration: running.duration)
        return true
    }
}

extension Animator {
    @MainActor func waitForPendingWrites(pids: Set<pid_t>, timeout: TimeInterval = 1) async -> Bool {
        let completion = PendingWrites()
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return } // style-ok: a hung app never drains
            completion.finish(false)
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                completion.wait(continuation)
                afterPendingWrites(pids: pids) { completion.finish(true) }
            }
        } onCancel: {
            completion.finish(false)
        }
    }
}

private final class PendingWrites: Sendable {
    private struct State: Sendable {
        var continuation: CheckedContinuation<Bool, Never>?
        var result: Result<Bool, Never>?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func wait(_ continuation: CheckedContinuation<Bool, Never>) {
        let result = state.withLock { state -> Result<Bool, Never>? in
            if state.result == nil { state.continuation = continuation }
            return state.result
        }
        if let result { continuation.resume(with: result) }
    }

    func finish(_ result: Bool) {
        let waiting = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            guard state.result == nil else { return nil }
            state.result = .success(result)
            defer { state.continuation = nil }
            return state.continuation
        }
        waiting?.resume(returning: result)
    }
}
