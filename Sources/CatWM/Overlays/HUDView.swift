import AppKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var model: HUDModel
    let margin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduceMotion = reduceMotion
        Group {
            if model.warning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(Theme.symbol(Theme.Icon.large, .semibold))
                        .foregroundStyle(Theme.warning)
                        .wiggleEffect(value: model.pops)
                    Text(model.text).font(Theme.body(14, .medium)).oneLine().fixedSize()
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .floatingGlass(Capsule())
            } else {
                VStack(spacing: 12) {
                    if let layout = model.layout {
                        LayoutThumbnail(layout: layout, selected: true).frame(width: 120)
                    }
                    Text(model.text).textStyle(.title).oneLine().fixedSize()
                }
                .padding(.horizontal, 24).padding(.top, model.layout == nil ? 16 : 20).padding(.bottom, 16)
                .floatingGlass(RoundedRectangle(cornerRadius: Theme.Radius.hud, style: .continuous))
            }
        }
        .foregroundStyle(Theme.ink)
        .keyframeAnimator(initialValue: 1.0, trigger: model.pops) { view, scale in
            view.scaleEffect(reduceMotion ? 1 : scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.9, duration: 0.001)
                SpringKeyframe(1, duration: 0.45, spring: Spring(response: 0.3, dampingRatio: 0.6))
            }
        }
        .padding(margin)
    }
}
