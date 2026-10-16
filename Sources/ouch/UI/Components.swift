// UI: design-system controls (buttons, switches, sliders, segmented, rows, groups).
import AppKit
import SwiftUI

// The design system's controls. View state lives in small ObservableObjects instead of @State: the
// Command Line Tools ship without SwiftUI's macro plugin.

/// Hover or press state for one view.
final class Flag: ObservableObject { @Published var on = false }

// MARK: - Button

enum ButtonVariant { case primary, secondary, ghost, danger, ghostDanger }
enum ButtonSize { case sm, regular, lg }

/// The one push button. One `primary` per surface; `ghost` for ways out; `danger` only for destructive
/// verbs, `ghostDanger` for one that sits quietly beside the others.
struct OButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        OButtonBody(configuration: configuration, style: self)
    }

    var height: CGFloat { size == .sm ? 26 : size == .lg ? 36 : Theme.controlHeight }
}

private struct OButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: OButtonStyle
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let s = style
        configuration.label
            .font(Theme.body(s.size == .sm ? 12.5 : s.size == .lg ? 14 : 13, .medium))
            .oneLine()
            .foregroundStyle(ink)
            .padding(.horizontal, s.iconOnly ? 0 : s.size == .sm ? 11 : s.size == .lg ? 18 : 14)
            .frame(width: s.iconOnly ? s.height : nil, height: s.height)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.spring, value: configuration.isPressed)
            .animation(.easeOut(duration: Theme.fast), value: lit)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hover.on = $0 }
    }

    /// Hover lights only a button that can be pressed.
    private var lit: Bool { hover.on && enabled }

    private var ink: Color {
        switch style.variant {
        case .primary: Theme.onAccent
        case .secondary: Theme.ink
        case .ghost: lit ? Theme.ink : Theme.inkMuted
        case .danger, .ghostDanger: Theme.danger
        }
    }

    private var fill: Color {
        switch style.variant {
        case .primary: lit ? Theme.accentHover : Theme.accent
        // A translucent well, not `surface-sunken`: on a raised surface or glass that reads as a black hole.
        case .secondary: lit ? Theme.wellHover : Theme.well
        case .ghost: lit ? Theme.hover : .clear
        case .danger: Theme.dangerSoft
        case .ghostDanger: lit ? Theme.dangerSoft : .clear
        }
    }
}

/// A labelled button with an optional SF Symbol and shortcut hint.
struct OButton: View {
    let title: String
    var icon: String? = nil
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    /// Keycaps shown after the label, e.g. ["↩"].
    var shortcut: [String] = []
    let action: () -> Void

    init(_ title: String, icon: String? = nil, variant: ButtonVariant = .secondary, size: ButtonSize = .regular,
         shortcut: [String] = [], action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.variant = variant; self.size = size
        self.shortcut = shortcut; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: size == .sm ? 11.5 : 13, weight: .medium)) }
                Text(title)
                if !shortcut.isEmpty {
                    Text(shortcut.joined()).font(Theme.keys(12, .medium)).opacity(0.8).padding(.trailing, -4)
                }
            }
        }
        .buttonStyle(OButtonStyle(variant: variant, size: size))
    }
}

/// Icon-only button; always carries a tooltip and an accessibility label.
struct OIconButton: View {
    let symbol: String
    let label: String
    var size: ButtonSize = .sm
    var variant: ButtonVariant = .ghost
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size == .sm ? 13 : 15, weight: .medium))
        }
        .buttonStyle(OButtonStyle(variant: variant, size: size, iconOnly: true))
        .tooltip(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Switch

/// Toggles one setting immediately. Off is a `border-control` outline on `surface-sunken`; on is
/// `accent` with an `on-accent` thumb that springs across and stretches while pressed. The thumb can be
/// dragged; it follows the pointer and settles on the nearer side.
struct OSwitch: View {
    @Binding var isOn: Bool
    let label: String
    @StateObject private var state = SwitchState()
    @Environment(\.isEnabled) private var enabled

    final class SwitchState: ObservableObject {
        @Published var pressed = false
        /// Thumb offset (0...14) while dragged.
        @Published var drag: CGFloat?
    }

    var body: some View {
        let shownOn = state.drag.map { $0 > 7 } ?? isOn
        let width: CGFloat = state.pressed ? 18 : 14
        let x = state.drag.map { min($0, 14 - (width - 14)) } ?? (isOn ? 14 - (width - 14) : 0)
        ZStack(alignment: .leading) {
            Capsule().fill(shownOn ? Theme.accent : Theme.well)
            Capsule().strokeBorder(Theme.borderControl, lineWidth: 1).opacity(shownOn ? 0 : 1)
            Capsule().fill(shownOn ? Theme.onAccent : Theme.borderControl)
                .frame(width: width, height: 14)
                .offset(x: 3 + x)
        }
        .frame(width: 34, height: 20)
        .contentShape(Capsule())
        .animation(Motion.spring, value: isOn)
        .animation(Motion.spring, value: state.pressed)
        .animation(.easeOut(duration: Theme.fast), value: shownOn)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !state.pressed { state.pressed = true }
                if abs(v.translation.width) > 3 || state.drag != nil {
                    state.drag = min(max((isOn ? 14 : 0) + v.translation.width, 0), 14)
                }
            }
            .onEnded { _ in
                if let d = state.drag { isOn = d > 7 } else { isOn.toggle() }
                state.drag = nil
                state.pressed = false
            })
        .focusable()
        .onKeyPress(keys: [.space, .return]) { _ in isOn.toggle(); return .handled }
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { isOn.toggle() }
    }
}

// MARK: - Segmented

/// Picks one of two to four options with a sliding `accent` thumb.
struct OSegmented<T: Hashable>: View {
    /// Spoken by VoiceOver; not shown.
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button { withAnimation(Motion.spring) { selection = o.value } } label: {
                    Text(o.label)
                        .font(Theme.body(12.5, on ? .medium : .regular)).oneLine()
                        .foregroundStyle(on ? Theme.onAccent : Theme.inkMuted)
                        .padding(.horizontal, 12).frame(height: 24)
                        .background {
                            if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "thumb", in: thumb) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.well))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Slider (line)

final class SliderState: ObservableObject {
    @Published var dragging = false
    /// Fill position while dragging, 0...1; follows the pointer exactly while the value rounds to the step.
    @Published var fraction: Double?
    /// Rubber-band stretch past either end, in points (negative: past the start).
    @Published var stretch: CGFloat = 0
    @Published var hovering = false
    var start: Double = 0
    var moved = false
}

/// Sets a number by dragging. Tap to jump, drag to adjust, ⌥ for fine control, double-click to reset.
/// Within 2.5% of a tick the value snaps to it; past either end the track stretches and springs back.
struct OSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var ticks: [Double] = []
    var resetValue: Double? = nil
    var width: CGFloat = 200
    let label: String
    let format: (Double) -> String
    /// Called when a drag or tap ends, e.g. to play a preview.
    var onCommit: () -> Void = {}
    @StateObject private var s = SliderState()
    @Environment(\.isEnabled) private var enabled

    private var span: Double { range.upperBound - range.lowerBound }
    private func fraction(of v: Double) -> Double { span == 0 ? 0 : (v - range.lowerBound) / span }

    private func snapped(_ raw: Double) -> Double {
        var v = min(max(raw, range.lowerBound), range.upperBound)
        if let t = ticks.min(by: { abs($0 - v) < abs($1 - v) }), abs(t - v) <= span * 0.025 { return t }
        if step > 0 { v = (v / step).rounded() * step }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 12) {
            track
            Text(format(value))
                .font(Theme.body(13, .medium)).monospacedDigit().oneLine().fixedSize()
                .foregroundStyle(s.dragging ? Theme.accentInk : Theme.inkMuted)
                .frame(minWidth: 56, alignment: .trailing) // grows rather than truncating "8 windows"
        }
        .opacity(enabled ? 1 : 0.45)
    }

    private var track: some View {
        let f = s.fraction ?? fraction(of: value)
        return GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderControl.opacity(0.4)).frame(height: 6)
                Capsule().fill(Theme.accent).frame(width: max(0, w * f), height: 6)
                ForEach(ticks, id: \.self) { t in
                    Circle().fill(fraction(of: t) <= f ? Theme.onAccent.opacity(0.7) : Theme.borderControl)
                        .frame(width: 4, height: 4).offset(x: w * fraction(of: t) - 2)
                }
                thumb.offset(x: w * f - 10)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .scaleEffect(x: 1 + abs(s.stretch) / max(w, 1), y: 1 - abs(s.stretch) / 60,
                         anchor: s.stretch < 0 ? .trailing : .leading)
            .gesture(drag(width: w))
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                withAnimation(Motion.spring) { value = resetValue ?? range.lowerBound }
                onCommit()
            })
        }
        .frame(width: width, height: 24)
        .onHover { s.hovering = $0 }
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end]) { press in
            let unit = step > 0 ? step : span / 100
            let n = press.modifiers.contains(.shift) ? 10.0 : 1.0
            withAnimation(Motion.spring) {
                switch press.key {
                case .leftArrow, .downArrow: value = snapped(value - unit * n)
                case .rightArrow, .upArrow: value = snapped(value + unit * n)
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
            let unit = step > 0 ? step : span / 100
            value = snapped(value + (dir == .increment ? unit : -unit))
        }
    }

    private var thumb: some View {
        ZStack {
            Circle().fill(Theme.surfaceRaised)
                .elevation(.sm, in: Circle())
                .overlay(Circle().strokeBorder(Theme.borderControl.opacity(0.75), lineWidth: 1))
            Circle().fill(Theme.accent).frame(width: 6, height: 6).scaleEffect(s.dragging ? 1 : 0)
        }
        .frame(width: 20, height: 20)
        .scaleEffect(s.dragging ? 1.2 : s.hovering ? 1.08 : 1)
        .overlay(alignment: .top) {
            Text(format(value)).font(Theme.body(11.5, .medium)).monospacedDigit().oneLine()
                .foregroundStyle(Theme.surface)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.ink))
                .fixedSize()
                .offset(y: -30)
                .opacity(s.dragging ? 1 : 0)
                .scaleEffect(s.dragging ? 1 / 1.2 : 0.85, anchor: .bottom)
        }
        .animation(Motion.spring, value: s.dragging)
        .animation(.easeOut(duration: Theme.fast), value: s.hovering)
    }

    private func drag(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard w > 0 else { return }
                if !s.dragging {
                    s.dragging = true
                    s.moved = false
                    s.start = fraction(of: value)
                }
                if abs(g.translation.width) > 2 { s.moved = true }
                let fine = NSEvent.modifierFlags.contains(.option)
                let raw = fine ? s.start + Double(g.translation.width / w) * 0.1 : Double(g.location.x / w)
                guard s.moved else { return }
                let over = raw < 0 ? raw * Double(w) : raw > 1 ? (raw - 1) * Double(w) : 0
                s.stretch = CGFloat(over > 0 ? min(over * 0.25, 6) : max(over * 0.25, -6))
                let clamped = min(max(raw, 0), 1)
                s.fraction = clamped
                let v = snapped(range.lowerBound + clamped * span)
                if v != value { value = v }
            }
            .onEnded { g in
                if !s.moved, w > 0 { // a tap jumps there and springs
                    let v = snapped(range.lowerBound + min(max(Double(g.location.x / w), 0), 1) * span)
                    withAnimation(Motion.spring) { value = v }
                }
                withAnimation(Motion.spring) {
                    s.fraction = nil
                    s.stretch = 0
                    s.dragging = false
                }
                onCommit()
            }
    }
}

// MARK: - Slider (bar)

/// Control Center style pill whose fill is the indicator, with its label inside. For stacks of related
/// values. Dragging moves relative to where you grabbed it, so grabbing never makes it jump.
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

    private var span: Double { range.upperBound - range.lowerBound }
    private func fraction(of v: Double) -> Double { span == 0 ? 0 : (v - range.lowerBound) / span }
    private func snapped(_ raw: Double) -> Double {
        var v = min(max(raw, range.lowerBound), range.upperBound)
        if step > 0 { v = (v / step).rounded() * step }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    var body: some View {
        let f = s.fraction ?? fraction(of: value)
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(s.dragging || s.hovering ? Theme.wellHover : Theme.well)
                Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                Rectangle().fill(Theme.accent).frame(width: w * f)
                    .overlay(alignment: .trailing) {
                        Capsule().fill(Theme.onAccent).frame(width: 3, height: s.dragging ? 18 : 12)
                            .opacity(s.dragging ? 0.95 : 0.5).padding(.trailing, 7)
                            .opacity(w * f > 44 ? 1 : 0) // only once the fill clears the label
                    }
                content(Theme.ink)
                content(Theme.onAccent).mask(alignment: .leading) { Rectangle().frame(width: w * f) }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(x: 1 + abs(s.stretch) / max(w, 1), y: 1, anchor: s.stretch < 0 ? .trailing : .leading)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard w > 0 else { return }
                    if !s.dragging { s.dragging = true; s.moved = false; s.start = fraction(of: value) }
                    if abs(g.translation.width) > 2 { s.moved = true }
                    guard s.moved else { return }
                    let speed = NSEvent.modifierFlags.contains(.option) ? 0.1 : 1.0
                    let raw = s.start + Double(g.translation.width / w) * speed
                    let over = raw < 0 ? raw * Double(w) : raw > 1 ? (raw - 1) * Double(w) : 0
                    s.stretch = CGFloat(over > 0 ? min(over * 0.25, 6) : max(over * 0.25, -6))
                    s.fraction = min(max(raw, 0), 1)
                    let v = snapped(range.lowerBound + (s.fraction ?? 0) * span)
                    if v != value { value = v }
                }
                .onEnded { g in
                    if !s.moved, w > 0 {
                        let v = snapped(range.lowerBound + min(max(Double(g.location.x / w), 0), 1) * span)
                        withAnimation(Motion.spring) { value = v }
                    }
                    withAnimation(Motion.spring) { s.fraction = nil; s.stretch = 0; s.dragging = false }
                    onCommit()
                })
        }
        .frame(height: 34)
        .frame(minWidth: 180)
        .onHover { s.hovering = $0 }
        .animation(.easeOut(duration: Theme.fast), value: s.hovering)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { dir in
            let unit = step > 0 ? step : span / 100
            value = snapped(value + (dir == .increment ? unit : -unit))
        }
    }

    private func content(_ color: Color) -> some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .medium)) }
            Text(label).oneLine()
            Spacer(minLength: 8)
            Text(format(value)).monospacedDigit().oneLine()
        }
        .font(Theme.body(13.5, .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .allowsHitTesting(false)
    }
}

// MARK: - Keycaps

/// Keycaps for a shortcut. Small caps (20pt) for hints; large ones (40pt) only on tour cards, where the
/// real key press pushes them down into `accent`.
struct Kbd: View {
    let keys: [String]
    var large = false
    var pressed = false

    var body: some View {
        HStack(spacing: large ? 6 : 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in cap(k) }
        }
    }

    @ViewBuilder private func cap(_ k: String) -> some View {
        if large {
            let wide = k.count > 2
            Text(k)
                .font(Theme.keys(wide ? 14 : 17, .medium)).oneLine().fixedSize()
                .foregroundStyle(pressed ? Theme.onAccent : Theme.ink)
                .padding(.horizontal, 12)
                .frame(minWidth: 40, minHeight: 40)
                .background {
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    if pressed {
                        shape.fill(Theme.accent)
                    } else {
                        shape.fill(Theme.surface)
                            .overlay(alignment: .bottom) {
                                shape.fill(Theme.surfaceSunken).frame(height: 3)
                                    .mask(shape)
                            }
                            .elevation(.sm, in: shape)
                    }
                }
                .offset(y: pressed ? 2 : 0)
                .animation(.easeOut(duration: Theme.fast), value: pressed)
        } else {
            Text(k)
                .font(Theme.keys(11.5, .medium)).oneLine()
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 5)
                .frame(minWidth: 20, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).fill(Theme.well))
        }
    }
}

/// The tooltip: a plain raised xs Surface with a caret, a one-line description and its keys as small
/// caps. Each chord after the first reads "then", e.g. "⌘⇪ then L". Show it after `delay`.
struct OTooltip: View {
    static let delay = 0.5
    let text: String
    var chords: [[String]] = []
    var caret: Caret = .bottom

    var body: some View {
        HStack(spacing: 10) {
            // One line; a long message (a config problem) wraps rather than running across the screen.
            Text(text).font(Theme.body(12.5)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
            if !chords.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").font(Theme.body(11.5)).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .fixedSize()
            }
        }
        .surface(.xs, caret: caret)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row and Group

/// An open list: a title in `accent-ink`, rows separated by hairlines, no surrounding box.
struct OGroup<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(Theme.body(12, .medium)).tracking(0.24).foregroundStyle(Theme.accentInk).oneLine()
                    .padding(.bottom, 4)
            }
            _VariadicView.Tree(Separated()) { content }
            if let footer {
                Text(footer).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine().padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Separated: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    child.overlay(alignment: .top) {
                        if child.id != children.first?.id { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    }
                }
            }
        }
    }
}

/// One line of a group: optional symbol, a label, a one-line description and a control on the right.
/// Labels name the effect; units and current values go in the description.
struct ORow<Control: View>: View {
    let label: String
    var description: String? = nil
    var symbol: String? = nil
    @ViewBuilder var control: Control
    @Environment(\.isEnabled) private var enabled

    init(_ label: String, description: String? = nil, symbol: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.description = description
        self.symbol = symbol
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentInk)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Theme.body(14)).foregroundStyle(Theme.ink).oneLine()
                if let description {
                    Text(description).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
                }
            }
            .opacity(enabled ? 1 : 0.45)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { control }.fixedSize()
        }
        .frame(minHeight: 48)
        .padding(.vertical, 8)
    }
}

extension ORow where Control == EmptyView {
    init(_ label: String, description: String? = nil, symbol: String? = nil) {
        self.init(label, description: description, symbol: symbol) { EmptyView() }
    }
}

/// A switch row, the most common kind.
struct OSwitchRow: View {
    let label: String
    var description: String? = nil
    @Binding var isOn: Bool

    init(_ label: String, description: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        ORow(label, description: description) { OSwitch(isOn: $isOn, label: label) }
    }
}

// MARK: - Inputs

/// A text field on a sunken well, with a focus ring in `focus`.
struct OTextField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var onSubmit: () -> Void = {}
    /// Takes focus when it appears, so typing doesn't fall through to another field in the window.
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.inkFaint))
            .textFieldStyle(.plain)
            .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
            .font(mono ? Theme.mono(12, .regular) : Theme.body(13))
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10).frame(height: Theme.controlHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.focus, lineWidth: focused ? 2 : 0))
            .accessibilityLabel(placeholder)
    }
}

/// Search pill: magnifier, field and the shortcut that focuses it.
struct OSearchField: View {
    let placeholder: String
    @Binding var text: String
    var shortcut: [String] = []
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkMuted)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink)
                .focused(focus)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else if !shortcut.isEmpty {
                Kbd(keys: shortcut)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Ouch pieces

/// Workspaces as pills: the current one filled `accent`, a short `accent-2` mark under ones with windows.
struct WorkspaceStrip: View {
    let names: [String]
    let current: String?
    let occupied: Set<String>
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(names, id: \.self) { n in WorkspacePill(name: n, current: n == current, occupied: occupied.contains(n)) { pick(n) } }
        }
    }
}

private struct WorkspacePill: View {
    let name: String
    let current: Bool
    let occupied: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            Text(name).font(Theme.body(12, .medium)).oneLine()
                .foregroundStyle(current ? Theme.onAccent : hover.on ? Theme.ink : Theme.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(current ? Theme.accent : hover.on ? Theme.wellHover : .clear))
                .opacity(occupied || current || hover.on ? 1 : 0.35)
                .scaleEffect(current ? 1.04 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale(scale: 0.88))
        .onHover { hover.on = $0 }
        .animation(Motion.spring, value: current)
        .animation(Motion.spring, value: occupied)
        .tooltip("Workspace \(name)")
        .accessibilityLabel("Workspace \(name)\(occupied ? ", has windows" : "")")
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// Dips while held and springs back.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.spring, value: configuration.isPressed)
    }
}

/// Chooses a layout from a grid of thumbnails, with the hovered layout's name and description on one line below.
struct LayoutPicker: View {
    let layouts: [Layout]
    let selection: Layout?
    var columns = 4
    let pick: (Layout) -> Void
    @StateObject private var model = Model()

    final class Model: ObservableObject { @Published var hovered: Layout? }

    var body: some View {
        let shown = model.hovered ?? selection
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(layouts, id: \.self) { l in
                    Button { pick(l) } label: {
                        LayoutThumbnail(layout: l, selected: l == selection)
                            .scaleEffect(model.hovered == l ? 1.06 : 1)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .fill(l == selection ? Theme.accentSoft : model.hovered == l ? Theme.wellHover : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { on in
                        if on { model.hovered = l } else if model.hovered == l { model.hovered = nil }
                    }
                    .animation(Motion.spring, value: model.hovered == l)
                    .accessibilityLabel(l.title)
                    .accessibilityAddTraits(l == selection ? .isSelected : [])
                }
            }
            if let shown {
                // The blurb only shows whole; a long name alone beats "the rest stacked on…".
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shown.title).font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink).oneLine().fixedSize()
                        Text(shown.blurb).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine().fixedSize()
                    }
                    Text(shown.title).font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink).oneLine()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 2)
            }
        }
    }
}

extension Layout {
    /// One line on what the layout does, the app's own copy.
    var blurb: String {
        switch self {
        case .tall: "Main left, the rest stacked right"
        case .tallRight: "Main right, the rest stacked left"
        case .wide: "Main on top, the rest below"
        case .middleWide: "Main in the middle, the rest beside"
        case .fullscreen: "Every window fills the screen"
        case .column: "Equal-width columns"
        case .row: "Equal-height rows"
        case .floating: "Windows stay where you put them"
        case .bsp: "Each window halves the last one"
        case .threeColumnLeft: "Main left, two columns right"
        case .threeColumnMiddle: "Main in the middle column"
        case .threeColumnRight: "Main right, two columns left"
        case .twoPane: "Main left, one window right"
        case .twoPaneRight: "Main right, one window left"
        case .widescreenTall: "Mains side by side, the rest right"
        case .widescreenTallRight: "Mains side by side, the rest left"
        }
    }
}

/// A toggle in the essentials row: a symbol over a one-word name, `accent` when on, swapping its symbol
/// with `.replace`.
struct EssentialTile: View {
    /// One word under the symbol.
    let title: String
    /// Tooltip and VoiceOver name.
    let label: String
    let symbol: String
    var offSymbol: String? = nil
    var isOn: Bool? = nil
    var shortcut: [String] = []
    var rotates = false
    let action: () -> Void
    @StateObject private var model = Model()
    @Environment(\.isEnabled) private var enabled

    final class Model: ObservableObject {
        @Published var hover = false
        @Published var count = 0
    }

    var body: some View {
        let on = isOn == true, lit = model.hover && enabled
        Button {
            model.count += 1
            action()
        } label: {
            let image = Image(systemName: isOn == false ? offSymbol ?? symbol : symbol)
                .font(.system(size: 15, weight: .medium))
                .contentTransition(.symbolEffect(.replace, options: .speed(2.2)))
            VStack(spacing: 4) {
                Group {
                    if rotates { image.rotateEffect(value: model.count) } else { image }
                }
                .frame(height: 18)
                Text(title).font(Theme.body(11.5, on ? .medium : .regular)).oneLine().minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? Theme.onAccent : lit ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(on ? Theme.accent : lit ? Theme.wellHover : Theme.well))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { model.hover = $0 }
        .animation(.easeOut(duration: Theme.medium), value: on)
        .tooltip(label, keys: shortcut)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn == nil ? [] : on ? [.isToggle, .isSelected] : .isToggle)
    }
}

/// The rounded minus used to delete a list row.
struct RemoveButton: View {
    let help: String
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                .foregroundStyle(hover.on ? Theme.danger : Theme.inkMuted)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hover.on ? Theme.dangerSoft : Theme.well))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale(scale: 0.88))
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.fast), value: hover.on)
        .tooltip(help)
        .accessibilityLabel(help)
    }
}

/// A numbered step: the number in `accent-ink` light display type, then one line of text. `**bold**`
/// marks what to click, set at 500: plain markdown bold would pick Chillax Bold, the wordmark's weight.
struct OStep: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(Theme.display(20)).foregroundStyle(Theme.accentInk).frame(width: 14, alignment: .leading)
            Text(Self.styled(text)).font(Theme.body(13.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func styled(_ markdown: String, size: CGFloat = 13.5) -> AttributedString {
        var s = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in s.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            s[run.range].inlinePresentationIntent = nil
            s[run.range].font = Theme.body(size, .medium)
        }
        return s
    }
}

/// A status line: a symbol in its colour and a word, never colour alone.
struct OStatus: View {
    enum Kind { case success, warning, danger, info }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(text).font(Theme.body(12.5, .medium)).oneLine()
        }
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }
    private var color: Color {
        switch kind {
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.danger
        case .info: Theme.accentInk
        }
    }
}
