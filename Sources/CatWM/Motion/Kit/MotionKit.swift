import AppKit
import CatWMKit

extension Motion {
    static func group(_ duration: Double, curve: CAMediaTimingFunction = Curve.settle, label: String = #fileID,
                      changes: () -> Void, completion: (() -> Void)? = nil) {
        PerfMonitor.shared.track("ui:" + label, for: duration)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = curve
            context.allowsImplicitAnimation = true
            changes()
        }, completionHandler: completion)
    }

    static func setAlpha(_ alpha: CGFloat, on window: NSWindow) { window.animator().alphaValue = alpha }
    static func setAlpha(_ alpha: CGFloat, on view: NSView) { view.animator().alphaValue = alpha }
    static func setFrame(_ frame: NSRect, on window: NSWindow) { window.animator().setFrame(frame, display: true) }

    static func fade(_ window: NSWindow, to alpha: CGFloat, duration: Double = Theme.medium,
                     curve: CAMediaTimingFunction = Curve.easeOut, then completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = curve
            window.animator().alphaValue = alpha
        }, completionHandler: completion)
    }
}

final class PanelGlide {
    private var timer: Timer?
    private var tracks: [Trajectory] = []
    private var start: CFTimeInterval = 0
    private weak var panel: NSPanel?

    var isRunning: Bool { timer != nil }

    func to(_ frame: NSRect, on panel: NSPanel, spec: MotionSpec) {
        let now = CACurrentMediaTime()
        let current = panel.frame
        let inherited = timer == nil ? nil : tracks.map { $0.velocity(at: now - start) }
        stop()
        guard spec.duration > 0 else { panel.setFrame(frame, display: true); return }
        self.panel = panel
        start = now
        let pairs = [(current.minX, frame.minX), (current.minY, frame.minY),
                     (current.width, frame.width), (current.height, frame.height)]
        tracks = pairs.enumerated().map { index, pair in
            Trajectory(from: pair.0, to: pair.1, spec: spec, velocity: inherited?[index])
        }
        let duration = spec.duration
        let newTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.step(until: duration)
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step(until duration: Double) {
        guard let panel else { return stop() }
        let elapsed = CACurrentMediaTime() - start
        let values = tracks.map { $0.value(at: elapsed) }
        panel.setFrame(NSRect(x: values[0], y: values[1], width: values[2], height: values[3]).integral,
                       display: true)
        if elapsed >= duration { stop() }
    }
}
