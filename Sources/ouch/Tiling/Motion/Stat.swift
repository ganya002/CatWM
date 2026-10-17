import AppKit
import QuartzCore

struct Stat {
    var count = 0, total = 0.0, max = 0.0
    mutating func add(_ seconds: Double) { count += 1; total += seconds; max = Swift.max(max, seconds) }
    var text: String { count == 0 ? "-" : String(format: "avg %.2fms max %.2fms ×%d", total / Double(count) * 1000, max * 1000, count) }
}
