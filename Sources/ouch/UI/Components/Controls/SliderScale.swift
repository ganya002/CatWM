import AppKit
import SwiftUI

struct SliderScale {
    let range: ClosedRange<Double>
    var step: Double = 0
    var ticks: [Double] = []

    var span: Double { range.upperBound - range.lowerBound }
    var unit: Double { step > 0 ? step : span / 100 }
    func fraction(of value: Double) -> Double { span == 0 ? 0 : (value - range.lowerBound) / span }
    func value(at fraction: Double) -> Double { snapped(range.lowerBound + min(max(fraction, 0), 1) * span) }

    func snapped(_ raw: Double) -> Double {
        var value = min(max(raw, range.lowerBound), range.upperBound)
        if let tick = ticks.min(by: { abs($0 - value) < abs($1 - value) }), abs(tick - value) <= span * 0.025 {
            return tick
        }
        if step > 0 { value = (value / step).rounded() * step }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
