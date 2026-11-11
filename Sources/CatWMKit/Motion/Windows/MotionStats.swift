import AppKit
import Foundation
import QuartzCore

package struct Stat {
    package var count = 0, total = 0.0, max = 0.0
    package var isEmpty: Bool { count < 1 }
    package mutating func add(_ seconds: Double) { count += 1; total += seconds; max = Swift.max(max, seconds) }
    package var text: String {
        isEmpty ? "-" : String(format: "avg %.2fms max %.2fms ×%d", total / Double(count) * 1000, max * 1000, count)
    }
}

package struct StepCost {
    package static let limit = 0.05
    private static let rise = 0.8, fall = 0.4

    package private(set) var seconds: Double?

    package var lead: Double { seconds ?? 0 }

    package mutating func add(_ cost: Double) {
        let cost = min(cost, Self.limit)
        guard let seconds else { self.seconds = cost; return }
        self.seconds = seconds + (cost > seconds ? Self.rise : Self.fall) * (cost - seconds)
    }
}

package struct WindowWriteCost: Sendable {
    private var cost = StepCost()
    private var sampledAt: CFTimeInterval?
    private static let lifetime: CFTimeInterval = 1

    package func lead(at now: CFTimeInterval) -> Double {
        guard let sampledAt, (0...Self.lifetime).contains(now - sampledAt) else { return 0 }
        return cost.lead
    }

    package mutating func add(_ seconds: Double, at now: CFTimeInterval) {
        if let sampledAt, !(0...Self.lifetime).contains(now - sampledAt) { cost = StepCost() }
        cost.add(seconds)
        sampledAt = now
    }
}

package struct TilingTiming {
    package let name: String
    package let windows: Int
    private let start = CACurrentMediaTime()

    package init(_ name: String, windows: Int) {
        self.name = name
        self.windows = windows
    }

    package func checkpoint(_ phase: String) {
        Log.debug(String(format: "tiling: %@ %@ +%.1fms", name, phase, (CACurrentMediaTime() - start) * 1000))
    }

    package func finish() {
        let elapsed = (CACurrentMediaTime() - start) * 1000
        guard Log.verbose || elapsed > 1000.0 / 60.0 else { return }
        Log.info(String(format: "tiling: %@ windows %d %.1fms", name, windows, elapsed))
    }
}

extension Animator {
    package static func slowApp(_ pid: pid_t, _ stats: AXWriter.Stats) -> SlowApp? {
        guard !stats.position.isEmpty,
              let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        let step = (stats.size.isEmpty ? 0 : stats.size.total / Double(stats.size.count))
            + stats.position.total / Double(stats.position.count)
        return .init(bundle: bundle, stepMs: step * 1000,
                     skipped: Double(stats.skipped) / Double(stats.skipped + stats.position.count))
    }

    package struct Timing {
        var ticks = Stat(), gaps = Stat()
        var firstTick: CFTimeInterval?, lastTick: CFTimeInterval?

        package mutating func tick(at now: CFTimeInterval) {
            if let lastTick { gaps.add(now - lastTick) }
            if firstTick == nil { firstTick = now }
            lastTick = now
        }

        package func log(_ writers: [(pid_t, AXWriter.Stats)]) {
            let apps = writers.filter { $0.1.size.count + $0.1.position.count + $0.1.land.count > 0 }
            guard Log.verbose, !ticks.isEmpty else { return }
            Log.debug(String(format: "animate: %d ticks in %.0fms (display link) | tick %@ | gap %@",
                             ticks.count, (CACurrentMediaTime() - (firstTick ?? 0)) * 1000, ticks.text, gaps.text))
            let sorted = apps.sorted {
                $0.1.size.total + $0.1.position.total > $1.1.size.total + $1.1.position.total
            }
            for (pid, stats) in sorted {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
                Log.debug(
                    "animate:   \(name) (\(pid)) size \(stats.size.text) | position \(stats.position.text) "
                        + "| land \(stats.land.text) | skipped \(stats.skipped)"
                )
            }
        }
    }
}
