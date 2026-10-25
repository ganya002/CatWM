import AppKit
import SwiftUI

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
