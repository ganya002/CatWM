import AppKit
import SwiftUI

struct OBarSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let label: String
    var symbol: String? = nil
    let format: (Double) -> String
    var onCommit: () -> Void = {}
    @StateObject private var s = SliderState()
    @Environment(\.isEnabled) private var enabled

    private var scale: SliderScale { SliderScale(range: range, step: step) }

    var body: some View {
        let scale = scale
        let f = s.fraction ?? scale.fraction(of: value)
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(s.dragging || s.hovering ? Theme.wellHover : Theme.well)
                Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                Rectangle().fill(Theme.accent).frame(width: w * f)
                    .overlay(alignment: .trailing) {
                        Capsule().fill(Theme.onAccent).frame(width: 3, height: s.dragging ? 18 : 12)
                            .opacity(s.dragging ? 0.95 : 0.5).padding(.trailing, 7)
                            .opacity(w * f > 44 ? 1 : 0)
                    }
                content(Theme.ink)
                content(Theme.onAccent).mask(alignment: .leading) { Rectangle().frame(width: w * f) }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(x: 1 + abs(s.stretch) / max(w, 1), y: 1, anchor: s.stretch < 0 ? .trailing : .leading)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { s.drag($0, width: w, scale: scale, value: $value, relative: true) }
                .onEnded { s.end($0, width: w, scale: scale, value: $value); onCommit() })
        }
        .frame(height: 34)
        .frame(minWidth: 180)
        .onHover { s.hovering = $0 }
        .animation(Motion.fade, value: s.hovering)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { dir in
            value = scale.snapped(value + (dir == .increment ? scale.unit : -scale.unit))
        }
    }

    private func content(_ color: Color) -> some View {
        HStack(spacing: Theme.Space.sm) {
            if let symbol { Image(systemName: symbol).font(Theme.symbol()) }
            Text(label).oneLine()
            Spacer(minLength: Theme.Space.sm)
            Text(format(value)).monospacedDigit().oneLine()
        }
        .font(Theme.body(13.5, .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .allowsHitTesting(false)
    }
}
