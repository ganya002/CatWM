import AppKit
import SwiftUI

struct SliderScale {
    let range: ClosedRange<Double>
    var step: Double = 0
    var ticks: [Double] = []

    var span: Double { range.upperBound - range.lowerBound }
    var unit: Double { step > 0 ? step : span / 100 }
    func fraction(of v: Double) -> Double { span == 0 ? 0 : (v - range.lowerBound) / span }
    func value(at fraction: Double) -> Double { snapped(range.lowerBound + min(max(fraction, 0), 1) * span) }

    func snapped(_ raw: Double) -> Double {
        var v = min(max(raw, range.lowerBound), range.upperBound)
        if let t = ticks.min(by: { abs($0 - v) < abs($1 - v) }), abs(t - v) <= span * 0.025 { return t }
        if step > 0 { v = (v / step).rounded() * step }
        return min(max(v, range.lowerBound), range.upperBound)
    }
}
