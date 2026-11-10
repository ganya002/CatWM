import AppKit
import CatWMKit
import SwiftUI

struct ModeFXView: View {
    @ObservedObject var model: ModeFXModel
    @ObservedObject var screen: ModeFXScreen
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

    private var radius: CGFloat { screen.shape.topRadius }
    private var origin: CGPoint { screen.origin }
    private var notchHalfWidth: CGFloat { screen.shape.notchHalfWidth }
    private var notchHeight: CGFloat { screen.shape.notchHeight }
    private var topInset: CGFloat { screen.shape.topInset }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .circular)
    }
    private var tuck: CGFloat { notchHalfWidth > 0 ? 6 : 0 }
    private var notchCutout: some View {
        NotchCutout(halfWidth: notchHalfWidth, height: notchHeight).fill(style: FillStyle(eoFill: true))
    }
    private var notchFill: some View {
        NotchFill(halfWidth: notchHalfWidth, height: notchHeight).fill(.black)
    }
    private var color: Color { model.color }
    private var isOn: Bool { model.active }

    private func border(width: CGFloat) -> some View {
        ZStack {
            ForEach([false, true], id: \.self) { mirrored in
                DrawnHalf(radius: radius, inset: (width - tuck) / 2,
                          notchHalfWidth: notchHalfWidth, notchHeight: notchHeight)
                    .stroke(color, style: StrokeStyle(lineWidth: width + tuck, lineCap: .butt, lineJoin: .miter))
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            }
            notchFill
        }
        .compositingGroup()
    }

    @ViewBuilder private func effect(size: CGSize) -> some View {
        if reduceMotion && model.style != .none {
            border(width: 4)
                .opacity(isOn ? 1 : 0).animation(Motion.fade, value: isOn)
        } else {
            animated(size: size)
        }
    }

    @ViewBuilder private func animated(size: CGSize) -> some View {
        switch model.style {
        case .ripple:
            ripple(size: size)
        case .corners:
            corners(size: size)
        case .draw:
            draw
        case .none:
            EmptyView()
        }
    }

    private func ripple(size: CGSize) -> some View {
        let point = CGPoint(x: model.cursor.x - origin.x, y: size.height - (model.cursor.y - origin.y))
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0),
                       CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        let reach = corners.map { hypot($0.x - point.x, $0.y - point.y) }.max() ?? 1000
        return Color.clear.keyframeAnimator(initialValue: Ripple(), trigger: model.enters) { _, value in
            ZStack {
                Circle().strokeBorder(color.opacity(0.85), lineWidth: max(1, 30 * (1 - value.progress)))
                    .blur(radius: 6)
                    .frame(width: reach * 2 * value.progress, height: reach * 2 * value.progress)
                    .position(point)
                    .opacity(value.progress >= 1 ? 0 : 1 - value.progress * 0.6)
                    .mask(notchCutout)
                border(width: 3.5).opacity(value.edge)
            }
            .clipShape(shape)
        } keyframes: { _ in
            KeyframeTrack(\.progress) {
                CubicKeyframe(0, duration: 0.001)
                CubicKeyframe(1, duration: 0.55)
            }
            KeyframeTrack(\.edge) {
                CubicKeyframe(0, duration: 0.3)
                CubicKeyframe(1, duration: 0.2)
            }
        }
        .opacity(isOn ? 1 : 0).animation(Motion.release(isOn), value: isOn)
    }

    private func corners(size: CGSize) -> some View {
        Color.clear.keyframeAnimator(initialValue: 0.0, trigger: model.enters) { _, progress in
            ZStack {
                ForEach(0..<4) { i in
                    Bracket(radius: 6)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .offset(x: -40 * (1 - progress), y: -40 * (1 - progress))
                        .rotationEffect(.degrees(Double(i) * 90))
                        .frame(width: 70, height: 70)
                        .position(corner(i, size))
                }
            }
            .opacity(min(1, progress * 1.5))
            .mask(notchCutout)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0, duration: 0.001)
                SpringKeyframe(1, duration: 0.5, spring: Spring(response: 0.32, dampingRatio: 0.6))
            }
        }
        .opacity(isOn ? 1 : 0).animation(Motion.release(isOn), value: isOn)
    }

    private var draw: some View {
        Color.clear.keyframeAnimator(initialValue: 0.0, trigger: model.enters) { _, progress in
            ZStack {
                ForEach([false, true], id: \.self) { mirrored in
                    let half = DrawnHalf(radius: radius, inset: (4 - tuck) / 2,
                                         notchHalfWidth: notchHalfWidth, notchHeight: notchHeight)
                    ZStack {
                        half.trim(from: 0, to: progress)
                            .stroke(color, style: StrokeStyle(lineWidth: 4 + tuck, lineCap: .round, lineJoin: .miter))
                        half.trim(from: max(0, progress - 0.06), to: progress)
                            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round)).blur(radius: 8)
                            .opacity(progress >= 1 ? 0 : 1)
                    }
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                }
                notchFill
            }
            .compositingGroup()
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0, duration: 0.001)
                CubicKeyframe(1, duration: 0.45)
            }
        }
        .opacity(isOn ? 1 : 0).animation(Motion.release(isOn), value: isOn)
    }

    private func corner(_ i: Int, _ size: CGSize) -> CGPoint {
        let margin: CGFloat = 35 + 8
        return [CGPoint(x: margin, y: margin),
                CGPoint(x: size.width - margin, y: margin),
                CGPoint(x: size.width - margin, y: size.height - margin),
                CGPoint(x: margin, y: size.height - margin)][i]
    }

    private struct Ripple {
        var progress: CGFloat = 0
        var edge: Double = 0
    }
}
