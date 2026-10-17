import AppKit
import SwiftUI

final class SliderState: ObservableObject {
    @Published var dragging = false
    @Published var fraction: Double?
    @Published var stretch: CGFloat = 0
    @Published var hovering = false
    var start: Double = 0
    var moved = false
}

struct SliderScale {
    let range: ClosedRange<Double>
    var step: Double = 0
    var ticks: [Double] = []

    var span: Double { range.upperBound - range.lowerBound }
    var unit: Double { step > 0 ? step : span / 100 }
    func fraction(of v: Double) -> Double { span == 0 ? 0 : (v - range.lowerBound) / span }
    func value(at fraction: Double) -> Double { snapped(range.lowerBound + min(max(fraction, 0), 1) * span) }

    func snapped(_ raw: Double) -> Double {
        var v = min(max(raw, range.lowerBound), range.upperBound)
        if let t = ticks.min(by: { abs($0 - v) < abs($1 - v) }), abs(t - v) <= span * 0.025 { return t }
        if step > 0 { v = (v / step).rounded() * step }
        return min(max(v, range.lowerBound), range.upperBound)
    }
}

extension SliderState {
    func drag(_ g: DragGesture.Value, width w: CGFloat, scale: SliderScale, value: Binding<Double>, relative: Bool) {
        guard w > 0 else { return }
        if !dragging {
            dragging = true
            moved = false
            start = scale.fraction(of: value.wrappedValue)
        }
        if abs(g.translation.width) > 2 { moved = true }
        guard moved else { return }
        let fine = NSEvent.modifierFlags.contains(.option)
        let raw = relative || fine ? start + Double(g.translation.width / w) * (fine ? 0.1 : 1) : Double(g.location.x / w)
        let over = raw < 0 ? raw * Double(w) : raw > 1 ? (raw - 1) * Double(w) : 0
        stretch = CGFloat(over > 0 ? min(over * 0.25, 6) : max(over * 0.25, -6))
        let clamped = min(max(raw, 0), 1)
        fraction = clamped
        let v = scale.value(at: clamped)
        if v != value.wrappedValue { value.wrappedValue = v }
    }

    func end(_ g: DragGesture.Value, width w: CGFloat, scale: SliderScale, value: Binding<Double>) {
        if !moved, w > 0 {
            let v = scale.value(at: Double(g.location.x / w))
            withAnimation(Motion.spring) { value.wrappedValue = v }
        }
        withAnimation(Motion.spring) {
            fraction = nil
            stretch = 0
            dragging = false
        }
    }
}

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

struct OKnob: View {
    var color: Color? = nil
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let color {
                Circle().fill(color).overlay(Circle().strokeBorder(.white, lineWidth: 2)).elevation(.knob, in: Circle())
            } else {
                Circle().fill(Theme.surfaceRaised)
                    .elevation(.sm, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.borderControl.opacity(0.75), lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
    }
}

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
