import AppKit
import CatWMKit
import CoreText
import SwiftUI

struct Squish<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let delay: Double
    let anchor: UnitPoint
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = enabled && !reduceMotion, delay = delay
        return content.keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: trigger) { view, scale in
            view.scaleEffect(x: active ? scale.width : 1, y: active ? scale.height : 1, anchor: anchor)
        } keyframes: { _ in
            let wobble = Spring(response: 0.38, dampingRatio: 0.42)
            KeyframeTrack(\.width) {
                LinearKeyframe(1, duration: max(delay, 0.001))
                CubicKeyframe(1.09, duration: 0.07)
                SpringKeyframe(1, duration: 0.5, spring: wobble)
            }
            KeyframeTrack(\.height) {
                LinearKeyframe(1, duration: max(delay, 0.001))
                CubicKeyframe(0.9, duration: 0.07)
                SpringKeyframe(1, duration: 0.5, spring: wobble)
            }
        }
    }
}

extension View {
    func squish<T: Equatable>(
        on trigger: T, when: Bool = true, delay: Double = 0, anchor: UnitPoint = .bottom
    ) -> some View {
        modifier(Squish(trigger: trigger, delay: delay, anchor: anchor, enabled: when))
    }
}
