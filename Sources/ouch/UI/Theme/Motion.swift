import AppKit
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

    enum Curve {
        static let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        static let settle = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
        static let exit = CAMediaTimingFunction(name: .easeIn)
        static let fade = CAMediaTimingFunction(name: .easeOut)
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
                         ("snap", Motion.snap), ("pop", Motion.pop)], id: \.0) { name, animation in
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
