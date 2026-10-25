import AppKit
import QuartzCore

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
