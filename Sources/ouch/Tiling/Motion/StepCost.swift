import Foundation

struct StepCost {
    private(set) var seconds: Double?

    var lead: Double { min(seconds ?? 0, 0.05) }

    mutating func add(_ cost: Double) { seconds = seconds.map { $0 * 0.6 + cost * 0.4 } ?? cost }
}
