import AppKit
import QuartzCore

@MainActor package final class WindowResizeFills: WindowPresentation {
    private struct Stats {
        var samples = 0, visible = 0, caughtUp = 0, movedTop = 0
    }
    private struct Cached {
        let appearance: WindowFillAppearance
        let frame: CGRect
        let time: CFTimeInterval
    }
    private let captureQueue = DispatchQueue(label: "catwm.fill-preparation", qos: .userInitiated)
    private var cache: [CGWindowID: Cached] = [:]
    private var warming: Set<CGWindowID> = []
    private var active: Set<CGWindowID> = []
    private var fills: [CGWindowID: WindowResizeFill] = [:]
    private var stats: [CGWindowID: Stats] = [:]
    package init() {}

    package var refresh: (@MainActor () -> Void)?
    package var excluded: @MainActor () -> Set<CGWindowID> = { [] }

    package func warm(_ windows: [CGWindowID: Window], busy: @escaping @MainActor (CGWindowID) -> Bool) {
        cache = cache.filter { windows[$0.key] != nil }
        for id in windows.keys where !warming.contains(id) && !busy(id) {
            guard let frame = WindowSceneCapture.currentFrame(id), !frame.isEmpty,
                  WindowSceneCapture.canPresent([frame], participants: [id], excluding: excluded()),
                  cache[id].map({ $0.frame.size != frame.size || CACurrentMediaTime() - $0.time > 5 }) ?? true else {
                continue
            }
            warming.insert(id)
            captureQueue.async { [weak self] in
                let snapshot = WindowSceneCapture.windowImage(id)
                let appearance = snapshot.flatMap { WindowFillAppearance(image: $0.image, size: $0.frame.size) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.warming.remove(id)
                    guard let snapshot, let appearance else {
                        Log.debug("window-fill: unsupported or unavailable appearance \(id)")
                        return
                    }
                    guard !busy(id),
                          WindowSceneCapture.currentFrame(id)?
                            .approxEqual(snapshot.frame, tolerance: 0.25) == true else {
                        return
                    }
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
              let screen = Screen.all().first(where: { $0.frame.contains(from) && $0.frame.contains(move.target) }),
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
        for id in active where frames[id] == nil { cancel(id) }
        guard !active.isEmpty else { return }
        let regions = active.compactMap { frames[$0] }
        let own = Set(fills.values.map(\.windowID)).union(excluded())
        guard let order = WindowSceneCapture.windowOrder(),
              WindowSceneCapture.canPresent(regions, participants: Set(frames.keys),
                                            excluding: own, order: order) else {
            close(); return
        }
        for id in active {
            guard let desired = frames[id], let actual = WindowSceneCapture.currentFrame(id),
                  let cached = cache[id] else { cancel(id); continue }
            if fills[id] == nil {
                let fill = WindowResizeFill(window: id, appearance: cached.appearance)
                fill.onDismiss = { [weak self] in self?.cancel(id) }
                fills[id] = fill
            }
            stats[id, default: Stats()].samples += 1
            fills[id]?.update(desired: desired, actual: actual, order: order)
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
                + "native-ahead-or-ready \(stat.caughtUp) moving-top \(stat.movedTop)")
        }
    }

    package func close() {
        for id in active { cancel(id) }
    }
}
