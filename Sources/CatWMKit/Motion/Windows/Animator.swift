import AppKit
import Foundation
import os
import QuartzCore

package final class Animator {
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
    package var makeResizeScene: (([Move]) -> WindowResizeScene?)?
    package var windowPresentation: (any WindowPresentation)?
    private var resizeScene: WindowResizeScene?
    private var clock: WindowFrameClock?
    private var timing = Timing()
    private var endRun: (([SlowApp]) -> Void)?
    package var beginRun: (String) -> (([SlowApp]) -> Void)? = { _ in nil }
    package var onMinimumSize: ((CGWindowID, CGSize) -> Void)?
    package var onTopRefused: ((_ target: CGRect, _ actual: CGRect) -> Void)?
    package var onLanded: (() -> Void)?

    package init(backend: any WindowBackend = AXBackend.shared, makeWriter: ((pid_t) -> AXWriter)? = nil,
                 applyFocus: @escaping (Window, () -> Bool) -> Void = { $0.focus(ifCurrent: $1) }) {
        self.backend = backend
        self.makeWriter = makeWriter ?? { AXWriter(pid: $0, backend: backend) }
        self.applyFocus = applyFocus
    }

    deinit { clock?.stop(); resizeScene?.close(); windowPresentation?.close() }

    package func cancelFocus() { focusLock.withLock { focusGeneration += 1 } }

    package func focus(_ window: Window, done: @escaping () -> Void = {}) {
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

    package func focusSink(_ window: CGWindowID) {
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

    package func isBusy(_ id: CGWindowID) -> Bool {
        isAnimating(id) || (quietUntil[id] ?? 0) > CACurrentMediaTime()
    }

    package func isAnimating(_ id: CGWindowID) -> Bool {
        items[id] != nil || landing[id] != nil || following[id] != nil
    }

    package func destination(_ id: CGWindowID) -> CGRect? {
        items[id]?.move.target ?? landing[id]?.move.target ?? following[id]?.target
    }

    package func isMoving(_ id: CGWindowID, to frame: CGRect) -> Bool { destination(id) == frame }

    package func cancel(_ id: CGWindowID, keepingScene: Bool = false) {
        windowPresentation?.cancel(id)
        if !keepingScene { endResizeScene() }
        nextEpoch(for: id)
        following.remove(id)
        let item = items.removeValue(forKey: id), landed = landing.removeValue(forKey: id)
        guard let pid = item?.move.window.pid ?? landed?.move.window.pid ?? owners[id] else { return }
        writers[pid]?.cancel(id)
    }

    package func quiet(_ id: CGWindowID, for seconds: Double = 0.4) {
        quietUntil[id] = CACurrentMediaTime() + seconds
    }

    package func animate(_ moves: [Move], duration: Double, curve: AnimationCurve = .easeOut, bounce: Double = 0) {
        animate(moves, spec: MotionSpec(duration: duration, curve: curve, bounce: bounce))
    }

    package func animate(_ moves: [Move], spec: MotionSpec) {
        guard !moves.isEmpty else { return }
        prepareResizeScene(for: moves, spec: spec)
        let now = CACurrentMediaTime()
        let duration = spec.duration
        for move in moves {
            let id = move.window.id
            let from: CGRect
            var velocity: [Double]?
            if let running = items[id] {
                from = running.frame(at: now, aligned: resizeScene?.visible != true)
                velocity = running.velocity(at: now)
            } else if let landed = landing.removeValue(forKey: id) {
                from = move.from ?? landed.move.target
            } else if let followed = following[id] {
                from = move.from ?? followed.target
            } else {
                from = move.from ?? move.window.cachedFrame
            }
            cancel(id, keepingScene: true)
            owners[id] = move.window.pid
            if duration < 0.01 || from.isNull || from.approxEqual(move.target, tolerance: 2) {
                items[id] = nil
                land(move)
            } else {
                items[id] = Item(move: move, from: from, start: now, spec: spec, velocity: velocity)
                items[id]?.colorSizing = windowPresentation?.sizing(for: move, from: from, spec: spec)
                if resizeScene?.usesLiveBuffers == true {
                    items[id]?.colorSizing = ColorFillSizing(source: from, target: move.target)
                    resizeScene?.cover(id, to: move.target)
                } else if resizeScene?.visible == true { land(move) }
            }
        }
        windowPresentation?.prepare(moves, spec: spec)
        startClock()
        finishResizeScene()
    }

    package func endFollow() { following.removeAll().forEach(land) }

    package func position(_ window: Window, at frame: CGRect) {
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

    package var activeWriterPids: Set<pid_t> { Set(writers.keys) }

    package func afterPendingWrites(_ completion: @escaping () -> Void) {
        afterPendingWrites(pids: nil, completion)
    }

    package func afterPendingWrites(
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

    private func tick(at presentation: CFTimeInterval) {
        let now = CACurrentMediaTime()
        timing.tick(at: now)
        resizeScene?.update(items.mapValues { $0.frame(at: presentation, aligned: false) })
        let ordered = items.sorted {
            let left = $0.value.colorSizing?.releasesSpace == true
            let right = $1.value.colorSizing?.releasesSpace == true
            return left == right ? $0.key < $1.key : left
        }
        for (id, item) in ordered {
            if presentation - item.start >= item.duration {
                items[id] = nil
                land(item.move)
            } else if resizeScene?.visible != true || resizeScene?.usesLiveBuffers == true {
                writer(item.move.window.pid).step(item.move.window, notBefore: presentation,
                                                  releasesSpace: item.colorSizing?.releasesSpace == true) {
                    item.request(at: $0, presentedAt: presentation)
                }
            }
        }
        updateWindowPresentation(at: presentation)
        timing.ticks.add(CACurrentMediaTime() - now)
        if items.isEmpty {
            clock?.stop(); clock = nil
            let stats = writers.map { ($0.key, $0.value.takeStats()) }
            endRun?(stats.compactMap(Self.slowApp))
            endRun = nil
            timing.log(stats)
            timing = Timing()
        }
    }

    private func land(_ move: Move) {
        let id = move.window.id
        landings += 1
        let number = landings
        let epoch = epochs[id] ?? nextEpoch(for: id)
        landing[id] = (move, number)
        quietUntil[id] = CACurrentMediaTime() + 0.4
        resizeScene?.cover(id, to: move.target)
        writer(move.window.pid).land(move.window, at: move.target) { [weak self] wrote in
            guard let self, self.landing[id]?.number == number else { return }
            self.landing[id] = nil
            self.updateWindowPresentation()
            if wrote { self.resizeScene?.placed(id, at: move.target) }
            self.finishResizeScene()
            if wrote { self.onLanded?() }
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
    package func follow(_ moves: [Move]) {
        for move in moves {
            let id = move.window.id
            if items[id] != nil || landing[id] != nil { cancel(id) }
            owners[id] = move.window.pid
            following.add(move)
            quietUntil[id] = CACurrentMediaTime() + 0.4
        }
        windowPresentation?.follow(moves)
        updateWindowPresentation()
        for move in moves {
            writer(move.window.pid).follow(move.window, to: move.target) { [weak self] actual in
                guard let self else { return }
                self.updateWindowPresentation()
                guard let minimum = self.following.minimum(after: move, actual: actual) else { return }
                self.onMinimumSize?(move.window.id, minimum)
            }
        }
    }

    private func updateWindowPresentation(at time: CFTimeInterval = CACurrentMediaTime()) {
        guard let windowPresentation else { return }
        let samples = items.mapValues { $0.frame(at: time, aligned: false) }
        let moving = following.frames.merging(samples) { _, frame in frame }
        windowPresentation.update(moving.merging(landing.mapValues { $0.move.target }) { frame, _ in frame })
    }

    private func prepareResizeScene(for moves: [Move], spec: MotionSpec) {
        guard makeResizeScene != nil else { return }
        guard spec.duration >= 0.08 else { endResizeScene(); return }
        if let resizeScene, !resizeScene.visible || !Set(moves.map(\.window.id)).isSubset(of: resizeScene.ids)
            || !moves.allSatisfy({ resizeScene.contains($0.target) }) {
            endResizeScene()
        }
        guard resizeScene == nil, items.isEmpty, landing.isEmpty,
              moves.contains(where: { move in
                  let frame = move.from ?? move.window.cachedFrame
                  return !frame.isNull && (abs(frame.width - move.target.width) > 2
                      || abs(frame.height - move.target.height) > 2)
              }) else { return }
        resizeScene = makeResizeScene?(moves)
        resizeScene?.onDismiss = { [weak self] in self?.endResizeScene() }
        resizeScene?.show()
    }

    private func endResizeScene() {
        guard let scene = resizeScene else { return }
        if !scene.usesLiveBuffers { scene.ids.forEach { items[$0] = nil } }
        scene.close()
        resizeScene = nil
    }

    private func finishResizeScene() {
        guard items.isEmpty, landing.isEmpty else { return }
        resizeScene?.close()
        resizeScene = nil
    }

    private func startClock() {
        guard !items.isEmpty else { return }
        let screens = backend.screens().filter { screen in
            items.values.contains { $0.move.target.intersects(screen.frame) }
        }.compactMap(\.nsScreen)
        guard let screen = screens.max(by: { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond })
            ?? NSScreen.main else {
            let unfinished = Array(items.values)
            items.removeAll()
            unfinished.forEach { land($0.move) }
            return
        }
        if clock == nil {
            endRun = beginRun("window-move")
        }
        if clock?.displayID != screen.displayID {
            clock?.stop()
            clock = WindowFrameClock(screen: screen) { [weak self] time in self?.tick(at: time) }
        }
    }

    private func writer(_ pid: pid_t) -> AXWriter {
        if let existing = writers[pid] { return existing }
        let created = makeWriter(pid)
        writers[pid] = created
        return created
    }

    package func forget(_ id: CGWindowID) {
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

    package func terminated(_ pid: pid_t) {
        writers[pid] = nil
        focusQueues[pid] = nil
    }
}

extension Animator {
    package func retarget(_ window: Window, to frame: CGRect) -> Bool {
        guard let running = items[window.id] else { return false }
        if resizeScene?.contains(frame) == false { endResizeScene(); return false }
        let target = [frame.minX, frame.minY, frame.width, frame.height]
        let tracks = zip(running.tracks, target).map { $0.retargeted(to: $1) }
        items[window.id] = Item(move: .init(window: window, to: frame, bounds: frame), tracks: tracks,
                                start: running.start, duration: running.duration)
        if let sizing = running.colorSizing, frame.minY == sizing.source.minY {
            items[window.id]?.colorSizing = ColorFillSizing(source: sizing.source, target: frame)
        }
        if resizeScene?.visible == true, let item = items[window.id] {
            nextEpoch(for: window.id)
            land(item.move)
        }
        return true
    }
}
