import AppKit

extension Animator {
    package func useSnapshotScenes(_ enabled: Bool, excluding: @escaping @MainActor () -> Set<CGWindowID>) {
        guard enabled else { makeResizeScene = nil; return }
        guard makeResizeScene == nil else { return }
        makeResizeScene = { moves in
            let screens = Screen.all()
            guard moves.allSatisfy({ move in
                screens.contains { $0.frame.contains(move.target) && $0.frame.contains(move.window.cachedFrame) }
            }) else { return nil }
            let frames = Dictionary(moves.map { ($0.window.id, $0.from ?? $0.window.cachedFrame) },
                                    uniquingKeysWith: { _, latest in latest })
            let regions = moves.map { ($0.from ?? $0.window.cachedFrame).union($0.target) }
            let excluded = excluding()
            guard WindowSceneCapture.canPresent(regions, participants: Set(frames.keys),
                                                excluding: excluded) else { return nil }
            let started = CACurrentMediaTime()
            guard let capture = WindowSceneCapture.take(frames: frames, screens: screens,
                                                      excluding: excluded) else { return nil }
            Log.debug(String(format: "window-scene: captured %d windows in %.1fms", frames.count,
                             (CACurrentMediaTime() - started) * 1000))
            return WindowResizeScene(capture: capture, frames: frames)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            Log.debug("window-scene: prewarm \(WindowSceneCapture.prepare())")
        }
    }
}
