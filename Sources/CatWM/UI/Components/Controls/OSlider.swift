import AppKit
import SwiftUI

struct OSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var ticks: [Double] = []
    var resetValue: Double?
    var width: CGFloat = 200
    let label: String
    let format: (Double) -> String
    var onCommit: () -> Void = {}
    @StateObject private var slider = SliderState()
    @Environment(\.isEnabled) private var enabled

    private var scale: SliderScale { SliderScale(range: range, step: step, ticks: ticks) }

    var body: some View {
        HStack(spacing: Theme.Space.medium) {
            track
            Text(format(value))
                .font(Theme.body(13, .medium)).monospacedDigit().oneLine().fixedSize()
                .foregroundStyle(slider.dragging ? Theme.ink : Theme.inkMuted)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .opacity(enabled ? 1 : 0.45)
    }

    private var track: some View {
        let scale = scale
        let fraction = slider.fraction ?? scale.fraction(of: value)
        return GeometryReader { geometry in
            let trackWidth = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderControl.opacity(0.4)).frame(height: 6)
                Capsule().fill(Theme.accent).frame(width: max(0, trackWidth * fraction), height: 6)
                ForEach(ticks, id: \.self) { tick in
                    Circle()
                        .fill(scale.fraction(of: tick) <= fraction ? Theme.onAccent.opacity(0.7) : Theme.borderControl)
                        .frame(width: 4, height: 4).offset(x: trackWidth * scale.fraction(of: tick) - 2)
                }
                thumb.offset(x: trackWidth * fraction - 10)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .scaleEffect(x: 1 + abs(slider.stretch) / max(trackWidth, 1), y: 1 - abs(slider.stretch) / 60,
                         anchor: slider.stretch < 0 ? .trailing : .leading)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { slider.drag($0, width: trackWidth, scale: scale, value: $value, relative: false) }
                .onEnded { slider.end($0, width: trackWidth, scale: scale, value: $value); onCommit() })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                withAnimation(Motion.spring) { value = resetValue ?? range.lowerBound }
                onCommit()
            })
        }
        .frame(width: width, height: 24)
        .onHover { slider.hovering = $0 }
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end]) { press in
            let multiplier = press.modifiers.contains(.shift) ? 10.0 : 1.0
            withAnimation(Motion.spring) {
                switch press.key {
                case .leftArrow, .downArrow: value = scale.stepping(value, by: -multiplier)
                case .rightArrow, .upArrow: value = scale.stepping(value, by: multiplier)
                case .home: value = range.lowerBound
                default: value = range.upperBound
                }
            }
            onCommit()
            return .handled
        }
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { dir in
            value = scale.stepping(value, by: dir == .increment ? 1 : -1)
        }
    }

    private var thumb: some View {
        ZStack {
            OKnob()
            Circle().fill(Theme.accent).frame(width: 6, height: 6).scaleEffect(slider.dragging ? 1 : 0)
        }
        .scaleEffect(slider.dragging ? 1.2 : slider.hovering ? 1.08 : 1)
        .animation(Motion.spring, value: slider.dragging)
        .animation(Motion.fade, value: slider.hovering)
    }
}

#if DEBUG
extension GalleryExamples {
    static let controls = GalleryExample(order: 4) { AnyView(GalleryContent(model: $0).controls) }
}

extension GalleryContent {
    @ViewBuilder var controls: some View {
        block("Controls") {
            HStack(spacing: Theme.Space.extraLarge) {
                switchExamples
                segmentExamples
            }
            VStack(alignment: .leading, spacing: Theme.Space.large) {
                OSlider(value: $model.gap, range: 0...40, step: 1, ticks: [8, 16, 24, 32], resetValue: 12, width: 260,
                        label: "Window gap", format: { "\(Int($0)) px" })
                OSlider(value: $model.ratio, range: 20...80, step: 1, ticks: [50], resetValue: 50, width: 260,
                        label: "Split ratio", format: { "\(Int($0)) / \(100 - Int($0))" })
                barSliderExample
            }
            textFieldExamples
        }
    }
}
#endif

struct OKnob: View {
    var color: Color?
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let color {
                Circle().fill(color).overlay(Circle().strokeBorder(.white, lineWidth: 2)).elevation(.knob, in: Circle())
            } else {
                Circle().fill(Theme.surfaceRaised)
                    .elevation(.small, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.borderControl.opacity(0.75), lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var knobExamples: some View {
        OKnob()
        OKnob(color: Theme.accent)
    }
}
#endif
