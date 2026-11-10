import AppKit
import CatWMKit
import SwiftUI

struct OBarSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let label: String
    var symbol: String?
    let format: (Double) -> String
    var onCommit: () -> Void = {}
    @StateObject private var slider = SliderState()
    @Environment(\.isEnabled) private var enabled

    private var scale: SliderScale { SliderScale(range: range, step: step) }

    var body: some View {
        let scale = scale
        let fraction = slider.fraction ?? scale.fraction(of: value)
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(slider.dragging || slider.hovering ? Theme.wellHover : Theme.well)
                Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                Rectangle().fill(Theme.accent).frame(width: trackWidth * fraction)
                    .overlay(alignment: .trailing) {
                        Capsule().fill(Theme.onAccent).frame(width: 3, height: slider.dragging ? 18 : 12)
                            .opacity(slider.dragging ? 0.95 : 0.5).padding(.trailing, Theme.Space.small)
                            .opacity(trackWidth * fraction > 44 ? 1 : 0)
                    }
                content(Theme.ink)
                content(Theme.onAccent).mask(alignment: .leading) { Rectangle().frame(width: trackWidth * fraction) }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(x: 1 + abs(slider.stretch) / max(trackWidth, 1), y: 1,
                         anchor: slider.stretch < 0 ? .trailing : .leading)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { slider.drag($0, width: trackWidth, scale: scale, value: $value, relative: true) }
                .onEnded { slider.end($0, width: trackWidth, scale: scale, value: $value); onCommit() })
        }
        .frame(height: 34)
        .frame(minWidth: 180)
        .onHover { slider.hovering = $0 }
        .animation(Motion.fade, value: slider.hovering)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { dir in
            value = scale.stepping(value, by: dir == .increment ? 1 : -1)
        }
    }

    private func content(_ color: Color) -> some View {
        HStack(spacing: Theme.Space.small) {
            if let symbol { Image(systemName: symbol).font(Theme.symbol()) }
            Text(label).oneLine()
            Spacer(minLength: Theme.Space.small)
            Text(format(value)).monospacedDigit().oneLine()
        }
        .font(Theme.body(13.5, .medium))
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Space.medium)
        .allowsHitTesting(false)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var barSliderExample: some View {
        OBarSlider(value: $model.speed, range: 0...1, step: 0.01, label: "Speed", symbol: "wand.and.stars",
                   format: { "\(Int($0 * 100))%" })
            .frame(width: 320)
    }
}
#endif
