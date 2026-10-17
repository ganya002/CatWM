import AppKit
import SwiftUI

struct ModeFXView: View {
    @ObservedObject var model: ModeFXModel
    let radius: CGFloat
    let origin: CGPoint
    var notchHalfWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    var topInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: max(0, geo.size.height - topInset))
            effect(size: size)
                .frame(width: size.width, height: size.height)
                .offset(y: topInset)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .circular)
    }
    private var tuck: CGFloat { notchHalfWidth > 0 ? 6 : 0 }
    private var notchCutout: some View {
        NotchCutout(halfWidth: notchHalfWidth, height: notchHeight).fill(style: FillStyle(eoFill: true))
    }
    private var c: Color { model.color }
    private var on: Bool { model.active }

    private func border(width: CGFloat) -> some View {
        ZStack {
            ForEach([false, true], id: \.self) { mirrored in
                DrawnHalf(radius: radius, inset: (width - tuck) / 2, notchHalfWidth: notchHalfWidth, notchHeight: notchHeight)
                    .stroke(c, style: StrokeStyle(lineWidth: width + tuck, lineCap: .butt, lineJoin: .miter))
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            }
        }
    }

    @ViewBuilder private func effect(size: CGSize) -> some View {
        if reduceMotion && model.style != .none {
            border(width: 4)
                .opacity(on ? 1 : 0).animation(Motion.fade, value: on)
        } else {
            animated(size: size)
        }
    }

    @ViewBuilder private func animated(size: CGSize) -> some View {
        switch model.style {
        case .ripple:
            let p = CGPoint(x: model.cursor.x - origin.x, y: size.height - (model.cursor.y - origin.y))
            let reach = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
                .map { hypot($0.x - p.x, $0.y - p.y) }.max() ?? 1000
            Color.clear.keyframeAnimator(initialValue: Ripple(), trigger: model.enters) { _, v in
                ZStack {
                    Circle().strokeBorder(c.opacity(0.85), lineWidth: max(1, 30 * (1 - v.t)))
                        .blur(radius: 6)
                        .frame(width: reach * 2 * v.t, height: reach * 2 * v.t)
                        .position(p)
                        .opacity(v.t >= 1 ? 0 : 1 - v.t * 0.6)
                        .mask(notchCutout)
                    border(width: 3.5).opacity(v.edge)
                }
                .clipShape(shape)
            } keyframes: { _ in
                KeyframeTrack(\.t) {
                    CubicKeyframe(0, duration: 0.001)
                    CubicKeyframe(1, duration: 0.55)
                }
                KeyframeTrack(\.edge) {
                    CubicKeyframe(0, duration: 0.3)
                    CubicKeyframe(1, duration: 0.2)
                }
            }
            .opacity(on ? 1 : 0).animation(.easeOut(duration: on ? 0 : 0.25), value: on)

        case .corners:
            Color.clear.keyframeAnimator(initialValue: 0.0, trigger: model.enters) { _, k in
                ZStack {
                    ForEach(0..<4) { i in
                        Bracket(radius: 6)
                            .stroke(c, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 70, height: 70)
                            .offset(x: -40 * (1 - k), y: -40 * (1 - k))
                            .rotationEffect(.degrees(Double(i) * 90))
                            .frame(width: 70, height: 70)
                            .position(corner(i, size))
                    }
                }
                .opacity(min(1, k * 1.5))
                .mask(notchCutout)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0, duration: 0.001)
                    SpringKeyframe(1, duration: 0.5, spring: Spring(response: 0.32, dampingRatio: 0.6))
                }
            }
            .opacity(on ? 1 : 0).animation(.easeOut(duration: on ? 0 : 0.2), value: on)

        case .draw:
            Color.clear.keyframeAnimator(initialValue: 0.0, trigger: model.enters) { _, k in
                ZStack {
                    ForEach([false, true], id: \.self) { mirrored in
                        let half = DrawnHalf(radius: radius, inset: (4 - tuck) / 2, notchHalfWidth: notchHalfWidth, notchHeight: notchHeight)
                        ZStack {
                            half.trim(from: 0, to: k).stroke(c, style: StrokeStyle(lineWidth: 4 + tuck, lineCap: .round, lineJoin: .miter))
                            half.trim(from: max(0, k - 0.06), to: k)
                                .stroke(c, style: StrokeStyle(lineWidth: 14, lineCap: .round)).blur(radius: 8)
                                .opacity(k >= 1 ? 0 : 1)
                        }
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    }
                }
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0, duration: 0.001)
                    CubicKeyframe(1, duration: 0.45)
                }
            }
            .opacity(on ? 1 : 0).animation(.easeOut(duration: on ? 0 : 0.25), value: on)

        case .none:
            EmptyView()
        }
    }

    private func corner(_ i: Int, _ s: CGSize) -> CGPoint {
        let m: CGFloat = 35 + 8
        return [CGPoint(x: m, y: m), CGPoint(x: s.width - m, y: m),
                CGPoint(x: s.width - m, y: s.height - m), CGPoint(x: m, y: s.height - m)][i]
    }

    private struct Ripple { var t: CGFloat = 0; var edge: Double = 0 }
}
