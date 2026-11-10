import AppKit
import CatWMKit
import SwiftUI

struct DrawEntrance: ViewModifier {
    let shown: Bool
    let radius: CGFloat

    private struct State { var draw = 0.0, glass = 0.0, line = 0.0 }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: State(), trigger: shown) { view, state in
            view
                .opacity(state.glass)
                .scaleEffect(0.985 + 0.015 * state.glass, anchor: .bottom)
                .overlay {
                    ZStack {
                        ForEach([false, true], id: \.self) { mirrored in
                            let half = OutlineHalf(radius: radius)
                            ZStack {
                                half.trim(from: 0, to: state.draw)
                                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                half.trim(from: max(0, state.draw - 0.08), to: state.draw)
                                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .blur(radius: 7)
                                    .opacity(state.draw >= 1 ? 0 : 1)
                            }
                            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        }
                    }
                    .opacity(state.line)
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

struct OutlineHalf: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let inner = rect.insetBy(dx: 1, dy: 1), rad = max(0, radius - 1)
        var path = Path()
        path.move(to: CGPoint(x: inner.midX, y: inner.minY))
        path.addArc(tangent1End: CGPoint(x: inner.maxX, y: inner.minY),
                    tangent2End: CGPoint(x: inner.maxX, y: inner.maxY), radius: rad)
        path.addArc(tangent1End: CGPoint(x: inner.maxX, y: inner.maxY),
                    tangent2End: CGPoint(x: inner.minX, y: inner.maxY), radius: rad)
        path.addLine(to: CGPoint(x: inner.midX, y: inner.maxY))
        return path
    }
}
