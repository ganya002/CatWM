import AppKit
import CatWMKit
import CryptoKit
import QuartzCore

final class FrameRun: NSObject {
    struct Stats { let frames: Int; let duration, period, p95, slowShare: Double }

    let kind: String
    private(set) var tags: Set<String> = []
    let refreshRate: Int
    private var link: CADisplayLink?
    private let started = CACurrentMediaTime()
    private var last = 0.0, period = 1.0 / 60
    private var gaps: [Double] = []
    private var ended = false

    init(kind: String, screen: NSScreen) {
        self.kind = kind
        refreshRate = screen.maximumFramesPerSecond
        super.init()
        let info = ProcessInfo.processInfo
        if info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { tags.insert("thermal") }
        if info.isLowPowerModeEnabled { tags.insert("lowpower") }
        link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func frame(_ displayLink: CADisplayLink) {
        period = max(0.001, displayLink.targetTimestamp - displayLink.timestamp)
        defer { last = displayLink.timestamp }
        guard last > 0 else { return }
        let gap = displayLink.timestamp - last
        if gap > 0.5 { tags.insert("gap") } else { gaps.append(gap) }
    }

    var stats: Stats? {
        guard !gaps.isEmpty else { return nil }
        let sorted = gaps.sorted()
        return Stats(frames: gaps.count, duration: CACurrentMediaTime() - started, period: period,
                     p95: sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
                     slowShare: Double(gaps.filter { $0 > period * 1.5 }.count) / Double(gaps.count))
    }

    func end(apps: [SlowApp] = []) {
        guard !ended else { return }
        ended = true
        link?.invalidate()
        link = nil
        PerfMonitor.shared.finish(self, apps: apps)
    }
}
