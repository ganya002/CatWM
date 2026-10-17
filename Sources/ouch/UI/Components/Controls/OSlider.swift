import AppKit
import SwiftUI

struct OSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var ticks: [Double] = []
    var resetValue: Double? = nil
    var width: CGFloat = 200
    let label: String
    let format: (Double) -> String
    var onCommit: () -> Void = {}
    @StateObject private var s = SliderState()
    @Environment(\.isEnabled) private var enabled

    private var scale: SliderScale { SliderScale(range: range, step: step, ticks: ticks) }

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            track
            Text(format(value))
                .font(Theme.body(13, .medium)).monospacedDigit().oneLine().fixedSize()
                .foregroundStyle(s.dragging ? Theme.accentInk : Theme.inkMuted)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .opacity(enabled ? 1 : 0.45)
    }

    private var track: some View {
        let scale = scale
        let f = s.fraction ?? scale.fraction(of: value)
        return GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderControl.opacity(0.4)).frame(height: 6)
                Capsule().fill(Theme.accent).frame(width: max(0, w * f), height: 6)
                ForEach(ticks, id: \.self) { t in
                    Circle().fill(scale.fraction(of: t) <= f ? Theme.onAccent.opacity(0.7) : Theme.borderControl)
                        .frame(width: 4, height: 4).offset(x: w * scale.fraction(of: t) - 2)
                }
                thumb.offset(x: w * f - 10)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .scaleEffect(x: 1 + abs(s.stretch) / max(w, 1), y: 1 - abs(s.stretch) / 60,
                         anchor: s.stretch < 0 ? .trailing : .leading)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { s.drag($0, width: w, scale: scale, value: $value, relative: false) }
                .onEnded { s.end($0, width: w, scale: scale, value: $value); onCommit() })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                withAnimation(Motion.spring) { value = resetValue ?? range.lowerBound }
                onCommit()
            })
        }
        .frame(width: width, height: 24)
        .onHover { s.hovering = $0 }
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end]) { press in
            let n = press.modifiers.contains(.shift) ? 10.0 : 1.0
            withAnimation(Motion.spring) {
                switch press.key {
                case .leftArrow, .downArrow: value = scale.snapped(value - scale.unit * n)
                case .rightArrow, .upArrow: value = scale.snapped(value + scale.unit * n)
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
            value = scale.snapped(value + (dir == .increment ? scale.unit : -scale.unit))
        }
    }

    private var thumb: some View {
        ZStack {
            OKnob()
            Circle().fill(Theme.accent).frame(width: 6, height: 6).scaleEffect(s.dragging ? 1 : 0)
        }
        .scaleEffect(s.dragging ? 1.2 : s.hovering ? 1.08 : 1)
        .overlay(alignment: .top) {
            Text(format(value)).font(Theme.body(11.5, .medium)).monospacedDigit().oneLine()
                .foregroundStyle(Theme.surface)
                .padding(.horizontal, Theme.Space.sm).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.ink))
                .fixedSize()
                .offset(y: -30)
                .opacity(s.dragging ? 1 : 0)
                .scaleEffect(s.dragging ? 1 / 1.2 : 0.85, anchor: .bottom)
        }
        .animation(Motion.spring, value: s.dragging)
        .animation(Motion.fade, value: s.hovering)
    }
}

#if DEBUG
extension GalleryExamples {
    static let controls = GalleryExample(order: 4) { AnyView(GalleryContent(m: $0).controls) }
}

extension GalleryContent {
    @ViewBuilder var controls: some View {
        block("Controls") {
            HStack(spacing: Theme.Space.xl) {
                switchExamples
                segmentExamples
            }
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                OSlider(value: $m.gap, range: 0...40, step: 1, ticks: [8, 16, 24, 32], resetValue: 12, width: 260,
                        label: "Window gap", format: { "\(Int($0)) px" })
                OSlider(value: $m.ratio, range: 20...80, step: 1, ticks: [50], resetValue: 50, width: 260,
                        label: "Split ratio", format: { "\(Int($0)) / \(100 - Int($0))" })
                barSliderExample
            }
            textFieldExamples
        }
    }
}
#endif
