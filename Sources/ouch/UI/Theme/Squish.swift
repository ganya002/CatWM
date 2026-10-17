import AppKit
import CoreText
import SwiftUI

struct Squish<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let delay: Double
    let anchor: UnitPoint
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let on = enabled && !reduceMotion, delay = delay
        return content.keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: trigger) { view, s in
            view.scaleEffect(x: on ? s.width : 1, y: on ? s.height : 1, anchor: anchor)
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
