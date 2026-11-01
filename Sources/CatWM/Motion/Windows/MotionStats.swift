import AppKit
import Foundation
import QuartzCore

struct Stat {
    var count = 0, total = 0.0, max = 0.0
    var isEmpty: Bool { count < 1 }
    mutating func add(_ seconds: Double) { count += 1; total += seconds; max = Swift.max(max, seconds) }
    var text: String {
        isEmpty ? "-" : String(format: "avg %.2fms max %.2fms ×%d", total / Double(count) * 1000, max * 1000, count)
    }
}

struct StepCost {
    private(set) var seconds: Double?

    var lead: Double { min(seconds ?? 0, 0.05) }

    mutating func add(_ cost: Double) { seconds = seconds.map { $0 * 0.6 + cost * 0.4 } ?? cost }
}

func measure(_ body: () -> Void) -> Double {
    let start = CACurrentMediaTime()
    body()
    return CACurrentMediaTime() - start
}

struct TilingTiming {
    let name: String
    let windows: Int
    private let start = CACurrentMediaTime()

    init(_ name: String, windows: Int) {
        self.name = name
        self.windows = windows
    }

    func checkpoint(_ phase: String) {
        Log.debug(String(format: "tiling: %@ %@ +%.1fms", name, phase, (CACurrentMediaTime() - start) * 1000))
    }

    func finish() {
        let elapsed = (CACurrentMediaTime() - start) * 1000
        guard Log.verbose || elapsed > 1000.0 / 60.0 else { return }
        Log.info(String(format: "tiling: %@ windows %d %.1fms", name, windows, elapsed))
    }
}

extension Animator {
    struct Timing {
        var ticks = Stat(), gaps = Stat()
        var firstTick: CFTimeInterval?, lastTick: CFTimeInterval?

        mutating func tick(at now: CFTimeInterval) {
            if let lastTick { gaps.add(now - lastTick) }
            if firstTick == nil { firstTick = now }
            lastTick = now
        }

        func log(_ writers: [(pid_t, AXWriter.Stats)]) {
            let apps = writers.filter { $0.1.size.count + $0.1.position.count + $0.1.land.count > 0 }
            guard Log.verbose, !ticks.isEmpty else { return }
            Log.debug(String(format: "animate: %d ticks in %.0fms (timer 8.33ms) | tick %@ | gap %@",
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
