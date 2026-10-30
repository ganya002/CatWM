import AppKit
import SwiftUI

final class SliderState: ObservableObject {
    @Published var dragging = false
    @Published var fraction: Double?
    @Published var stretch: CGFloat = 0
    @Published var hovering = false
    var start: Double = 0
    var moved = false
}

extension SliderState {
    func drag(_ gesture: DragGesture.Value, width: CGFloat, scale: SliderScale, value: Binding<Double>,
              relative: Bool) {
        guard width > 0 else { return }
        if !dragging {
            dragging = true
            moved = false
            start = scale.fraction(of: value.wrappedValue)
        }
        if abs(gesture.translation.width) > 2 { moved = true }
        guard moved else { return }
        let fine = NSEvent.modifierFlags.contains(.option)
        let raw = relative || fine
            ? start + Double(gesture.translation.width / width) * (fine ? 0.1 : 1)
            : Double(gesture.location.x / width)
        let over = raw < 0 ? raw * Double(width) : raw > 1 ? (raw - 1) * Double(width) : 0
        stretch = CGFloat(over > 0 ? min(over * 0.25, 6) : max(over * 0.25, -6))
        let clamped = min(max(raw, 0), 1)
        fraction = clamped
        let snapped = scale.value(at: clamped)
        if snapped != value.wrappedValue { value.wrappedValue = snapped }
    }

    func end(_ gesture: DragGesture.Value, width: CGFloat, scale: SliderScale, value: Binding<Double>) {
        if !moved, width > 0 {
            let snapped = scale.value(at: Double(gesture.location.x / width))
            withAnimation(Motion.spring) { value.wrappedValue = snapped }
        }
        withAnimation(Motion.spring) {
            fraction = nil
            stretch = 0
            dragging = false
        }
    }
}

struct SliderScale {
    let range: ClosedRange<Double>
    var step: Double = 0
    var ticks: [Double] = []

    var span: Double { range.upperBound - range.lowerBound }
    var unit: Double { step > 0 ? step : span / 100 }
    func fraction(of value: Double) -> Double { span == 0 ? 0 : (value - range.lowerBound) / span }
    func value(at fraction: Double) -> Double { snapped(range.lowerBound + min(max(fraction, 0), 1) * span) }

    func stepping(_ value: Double, by steps: Double) -> Double { snapped(value + unit * steps, toTicks: false) }

    private func snapped(_ raw: Double, toTicks: Bool = true) -> Double {
        var value = min(max(raw, range.lowerBound), range.upperBound)
        if toTicks, let tick = ticks.min(by: { abs($0 - value) < abs($1 - value) }), abs(tick - value) <= span * 0.025 {
            return tick
        }
        if step > 0 { value = (value / step).rounded() * step }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
