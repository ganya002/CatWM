import AppKit
import CatWMKit
import CoreText
import SwiftUI

enum Motion {
    static let easeOut = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: Theme.medium)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let snap = Animation.spring(response: 0.34, dampingFraction: 0.7)
    static func snap(_ reduce: Bool) -> Animation { reduce ? fade : snap }
    static let fade = Animation.easeOut(duration: Theme.fast)
    static let fadeMedium = Animation.easeOut(duration: Theme.medium)
    static let fadeSlow = Animation.easeOut(duration: Theme.slow)
    static let fadeAway = Animation.easeOut(duration: Theme.linger)
    static let exit = Animation.easeIn(duration: Theme.fast)
    static let pop = Animation.spring(response: 0.36, dampingFraction: 0.8)
    static let reveal = Animation.snappy(duration: Theme.medium)
    static let drop = Animation.easeIn(duration: 0.22)
    static let introReveal = Animation.easeOut(duration: 0.9)
    static let draw = Animation.linear(duration: Theme.linger)

    static func release(_ isOn: Bool) -> Animation { isOn ? .easeOut(duration: 0) : fadeSlow }
    static func tile(duration: Double) -> Animation { .linear(duration: duration) }
    static func panelExit(duration: Double) -> Animation { .timingCurve(0.4, 0, 1, 1, duration: duration) }
    static func feeling(_ spring: Spring, reduce: Bool) -> Animation { reduce ? fade : .spring(spring) }
    static func window(curve: AnimationCurve, bounce: Double, duration: Double) -> Animation {
        Animation(CurveAnimation(curve: curve, bounce: bounce, duration: duration))
    }

    static var user: Animation? {
        let config = WindowManager.shared.config
        guard config.animate else { return nil }
        return window(curve: config.animationCurve, bounce: config.animationBounce, duration: config.animationDuration)
    }

    static func user(reduceMotion: Bool) -> Animation? {
        guard let animation = user else { return nil }
        return reduceMotion ? fade : animation
    }

    static func panel(_ style: PanelMotion, in shown: Bool) -> Animation? { style.animation(in: shown) }

    static var tabStrip: Animation? { TabStrip.motion }

    static func tabFade(_ animation: Animation) -> Animation? { TabStrip.animated ? animation : nil }

    enum Curve {
        static let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        static let settle = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
        static let exit = CAMediaTimingFunction(name: .easeIn)
        static let fade = CAMediaTimingFunction(name: .easeOut)
    }
}

struct CurveAnimation: CustomAnimation {
    let curve: AnimationCurve
    let bounce: Double
    let duration: Double

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context _: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: curve.progress(time / duration, bounce: bounce))
    }
}

#if DEBUG
extension GalleryExamples {
    static let motion = GalleryExample(order: 14) { AnyView(GalleryContent(model: $0).motion) }
}

extension GalleryContent {
    @ViewBuilder var motion: some View {
        block("Motion") {
            HStack(spacing: Theme.Space.extraLarge) {
                ForEach([("easeOut", Motion.easeOut), ("spring", Motion.spring),
                         ("snap", Motion.snap), ("pop", Motion.pop),
                         ("reveal", Motion.reveal), ("drop", Motion.drop), ("draw", Motion.draw),
                         ("fade", Motion.fade), ("fadeMedium", Motion.fadeMedium), ("fadeSlow", Motion.fadeSlow),
                         ("introReveal", Motion.introReveal)], id: \.0) { name, animation in
                    VStack(alignment: .leading, spacing: Theme.Space.extraSmall) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.well).frame(width: 96, height: 20)
                            Circle().fill(Theme.accent).frame(width: 16, height: 16).offset(x: model.moved ? 78 : 2)
                                .animation(animation, value: model.moved)
                        }
                        Text(name).textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
                OButton("Play") { model.moved.toggle() }
            }
        }
    }
}
#endif
