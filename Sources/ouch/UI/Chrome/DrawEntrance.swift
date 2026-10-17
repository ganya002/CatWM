import AppKit
import SwiftUI

struct DrawEntrance: ViewModifier {
    let shown: Bool
    let radius: CGFloat

    private struct State { var draw = 0.0, glass = 0.0, line = 0.0 }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: State(), trigger: shown) { view, v in
            view
                .opacity(v.glass)
                .scaleEffect(0.985 + 0.015 * v.glass, anchor: .bottom)
                .overlay {
                    ZStack {
                        ForEach([false, true], id: \.self) { mirrored in
                            let half = OutlineHalf(radius: radius)
                            ZStack {
                                half.trim(from: 0, to: v.draw)
                                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                half.trim(from: max(0, v.draw - 0.08), to: v.draw)
                                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round)).blur(radius: 7)
                                    .opacity(v.draw >= 1 ? 0 : 1)
                            }
                            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        }
                    }
                    .opacity(v.line)
                    .allowsHitTesting(false)
                }
        } keyframes: { _ in
            KeyframeTrack(\.draw) {
                LinearKeyframe(shown ? 0 : 1, duration: 0.001)
                CubicKeyframe(1, duration: shown ? 0.45 : 0.01)
            }
            KeyframeTrack(\.glass) {
                LinearKeyframe(shown ? 0 : 1, duration: shown ? 0.1 : 0.001)
                CubicKeyframe(shown ? 1 : 0, duration: shown ? 0.38 : 0.16)
            }
            KeyframeTrack(\.line) {
                LinearKeyframe(shown ? 1 : 0, duration: shown ? 0.55 : 0.001)
                CubicKeyframe(0, duration: shown ? 0.5 : 0.01)
            }
        }
    }
}
