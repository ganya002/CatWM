import AppKit
import QuartzCore

package final class WindowResizeFills: WindowPresentation {
    private struct Stats {
        var samples = 0, visible = 0, caughtUp = 0, movedTop = 0
        var render = Stat()
    }
    private struct Cached {
        let appearance: WindowFillAppearance
        let frame: CGRect
        let time: CFTimeInterval
    }
    private let observer = WindowFillObserver()
    private var windows: [CGWindowID: Window] = [:]
    private var frames: [CGWindowID: CGRect] = [:]
    private var observation: WindowFillObservation?
    private var screens: [Screen] = []
    private let captureQueue = DispatchQueue(label: "catwm.fill-preparation", qos: .userInitiated)
    private var cache: [CGWindowID: Cached] = [:]
    private var warming: Set<CGWindowID> = []
    private var active: Set<CGWindowID> = []
    private var fills: [CGWindowID: WindowResizeFill] = [:]
    private var stats: [CGWindowID: Stats] = [:]
    package init() {}
    package var refresh: (() -> Void)?
    package var excluded: () -> Set<CGWindowID> = { [] }

    package func warm(_ windows: [CGWindowID: Window], busy: @escaping (CGWindowID) -> Bool) {
        self.windows = windows
        screens = Screen.all()
        cache = cache.filter { windows[$0.key] != nil }
        for (id, window) in windows where !warming.contains(id) && !busy(id) {
            guard cache[id].map({ $0.frame.size != window.cachedFrame.size
                || CACurrentMediaTime() - $0.time > 5 }) ?? true else { continue }
            warming.insert(id)
            let excluded = excluded()
            captureQueue.async { [weak self] in
                let visible = WindowSceneCapture.currentFrame(id).map {
                    WindowSceneCapture.canPresent([$0], participants: [id], excluding: excluded)
                } ?? false
                let snapshot = visible ? WindowSceneCapture.windowImage(id) : nil
                let appearance = snapshot.flatMap { WindowFillAppearance(image: $0.image, size: $0.frame.size) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.warming.remove(id)
                    guard let snapshot, let appearance else {
                        if visible { Log.debug("window-fill: unsupported or unavailable appearance \(id)") }
                        return
                    }
                    guard self.windows[id] === window, !busy(id),
                          window.cachedFrame.approxEqual(snapshot.frame, tolerance: 0.25) else { return }
                    self.cache[id] = Cached(appearance: appearance, frame: snapshot.frame, time: CACurrentMediaTime())
                    Log.debug("window-fill: prepared \(id)")
                }
            }
        }
    }

    package func prepare(_ moves: [Animator.Move], spec: MotionSpec) {
        guard spec.duration >= 0.08 else { moves.forEach { cancel($0.window.id) }; return }
        follow(moves)
    }

    package func sizing(for move: Animator.Move, from: CGRect, spec: MotionSpec) -> ColorFillSizing? {
        guard spec.duration >= 0.08, let cached = cache[move.window.id],
              cached.appearance.canFill(from: from, to: move.target),
              let screen = screens.first(where: { $0.frame.contains(from) && $0.frame.contains(move.target) }),
              let native = screen.nsScreen,
              abs(CGFloat(cached.appearance.rightEdge.height) / cached.appearance.sourceSize.height
                  - native.backingScaleFactor) < 0.01 else { return nil }
        return ColorFillSizing(source: from, target: move.target)
    }

    package func follow(_ moves: [Animator.Move]) {
        for move in moves {
            let id = move.window.id
            let from = move.from ?? move.window.cachedFrame
            guard let cached = cache[id], cached.appearance.canFill(from: from, to: move.target) else { continue }
            active.insert(id)
        }
    }

    package func update(_ frames: [CGWindowID: CGRect]) {
        self.frames = frames
        for id in active where frames[id] == nil { cancel(id) }
        guard !active.isEmpty else { observer.cancel(); return }
        let ids = Set(frames.keys)
        if observation?.participants == ids { present(observation) }
        observer.request(ids) { [weak self] observation in
            guard let self else { return }
            self.observation = observation
            self.present(observation)
        }
    }

    private func present(_ observation: WindowFillObservation?) {
        guard !active.isEmpty else { return }
        let regions = active.compactMap { frames[$0] }
        let own = Set(fills.values.map(\.windowID)).union(excluded())
        guard let observation, observation.canPresent(regions, excluding: own) else { close(); return }
        for id in active {
            let started = CACurrentMediaTime()
            defer { stats[id]?.render.add(CACurrentMediaTime() - started) }
            guard let desired = frames[id],
                  let actual = observation.cutout(for: id, requested: windows[id]?.cachedFrame ?? .null),
                  let cached = cache[id] else { cancel(id); continue }
            if fills[id] == nil {
                let fill = WindowResizeFill(window: id, appearance: cached.appearance)
                fill.onDismiss = { [weak self] in self?.cancel(id) }
                fills[id] = fill
            }
            stats[id, default: Stats()].samples += 1
            fills[id]?.update(desired: desired, actual: actual, order: observation.order, screens: screens)
            if fills[id]?.visible == true {
                if stats[id]?.visible == 0 { Log.debug("window-fill: visible \(id)") }
                stats[id, default: Stats()].visible += 1
            } else if actual.contains(desired) || actual.approxEqual(desired, tolerance: 0.25) {
                stats[id, default: Stats()].caughtUp += 1
            } else if actual.minY != desired.minY { stats[id, default: Stats()].movedTop += 1 }
        }
    }

    package func cancel(_ id: CGWindowID) {
        active.remove(id)
        fills.removeValue(forKey: id)?.close()
        if let stat = stats.removeValue(forKey: id) {
            Log.debug("window-fill: \(id) samples \(stat.samples) visible \(stat.visible) "
                + "native-ahead-or-ready \(stat.caughtUp) moving-top \(stat.movedTop) render \(stat.render.text)")
        }
    }

    package func close() {
        observer.cancel()
        observation = nil
        for id in active { cancel(id) }
    }
}
