import AppKit
import SwiftUI

extension SliderState {
    func drag(_ g: DragGesture.Value, width w: CGFloat, scale: SliderScale, value: Binding<Double>, relative: Bool) {
        guard w > 0 else { return }
        if !dragging {
            dragging = true
            moved = false
            start = scale.fraction(of: value.wrappedValue)
        }
        if abs(g.translation.width) > 2 { moved = true }
        guard moved else { return }
        let fine = NSEvent.modifierFlags.contains(.option)
        let raw = relative || fine ? start + Double(g.translation.width / w) * (fine ? 0.1 : 1) : Double(g.location.x / w)
        let over = raw < 0 ? raw * Double(w) : raw > 1 ? (raw - 1) * Double(w) : 0
        stretch = CGFloat(over > 0 ? min(over * 0.25, 6) : max(over * 0.25, -6))
        let clamped = min(max(raw, 0), 1)
        fraction = clamped
        let v = scale.value(at: clamped)
        if v != value.wrappedValue { value.wrappedValue = v }
    }

    func end(_ g: DragGesture.Value, width w: CGFloat, scale: SliderScale, value: Binding<Double>) {
        if !moved, w > 0 {
            let v = scale.value(at: Double(g.location.x / w))
            withAnimation(Motion.spring) { value.wrappedValue = v }
        }
        withAnimation(Motion.spring) {
            fraction = nil
            stretch = 0
            dragging = false
        }
    }
}
