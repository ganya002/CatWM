// Settings: the Motion pane (animation curves, presets and their previews).
import AppKit
import SwiftUI

// MARK: - Motion

struct MotionPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    /// The preview's two windows: a random pair, one light and one dark so they never blend.
    static let previewApps = [DemoApp.all.filter(\.dark).randomElement()!, DemoApp.all.filter { !$0.dark }.randomElement()!].shuffled()

    struct Preset {
        let name: String
        var animate = true
        var curve: AnimationCurve = .easeOut
        var duration = 0.2
        var bounce = 0.5
    }

    static let presets: [Preset] = [
        Preset(name: "None", animate: false),
        Preset(name: "Snappy", duration: 0.12),
        Preset(name: "Smooth", duration: 0.2),
        Preset(name: "Relaxed", curve: .easeInOut, duration: 0.35),
        Preset(name: "Springy", curve: .spring, duration: 0.5, bounce: 0.55),
        Preset(name: "Wobbly", curve: .spring, duration: 0.8, bounce: 0.85),
        Preset(name: "Bouncy", curve: .bounce, duration: 0.6, bounce: 0.5),
        Preset(name: "Playful", curve: .overshoot, duration: 0.35, bounce: 0.6),
    ]

    private func matches(_ p: Preset, _ c: Config) -> Bool {
        guard p.animate else { return !c.animate }
        return c.animate && c.animationCurve == p.curve && abs(c.animationDuration - p.duration) < 0.005
            && (!p.curve.usesBounce || abs(c.animationBounce - p.bounce) < 0.005)
    }

    var body: some View {
        let c = doc.config
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Style") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.presets, id: \.name) { p in
                        PresetTile(preset: p, selected: matches(p, c)) {
                            doc.config.animate = p.animate
                            if p.animate {
                                doc.config.animationCurve = p.curve
                                doc.config.animationDuration = p.duration
                                if p.curve.usesBounce { doc.config.animationBounce = p.bounce }
                            }
                            play() // feel it right away
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .setting("motion.style", ui)

            OGroup("Preview") {
                preview
                    .frame(height: 150)
                    .padding(.vertical, 10)
                ORow("Play it again", description: "Plays with exactly the curve windows use") {
                    OButton("Play", icon: "play.fill", size: .sm, action: play)
                }
            }
            .setting("motion.preview", ui)

            OGroup("Feel") {
                OptionSwitch(\.animate, doc: doc, ui: ui)
                let duration = ConfigOption.at(\Config.animationDuration).ui
                OBarSlider(value: Binding(get: { c.animationDuration }, set: { doc.config.animationDuration = ($0 * 100).rounded() / 100 }),
                           range: duration.range ?? 0...1, step: 0.01, label: duration.label, symbol: "timer",
                           format: { "\(Int(($0 * 1000).rounded())) ms" }, onCommit: play)
                    .padding(.vertical, 12)
                    .disabled(!c.animate)
                    .setting(duration.id, ui)
            }

            AdvancedSection(pane: .motion, ui: ui) {
                OGroup("Curve") {
                    OptionRow(\Config.animationCurve, ui: ui) { label in
                        OMenuPicker(title: label,
                                    options: AnimationCurve.named.map { ($0.name, $0.title) } + [("bezier", AnimationCurve.bezier(0, 0, 0, 0).title)],
                                    selection: Binding(get: { c.animationCurve.isBezier ? "bezier" : c.animationCurve.name }, set: { name in
                                        if name == "bezier" {
                                            if !c.animationCurve.isBezier { doc.config.animationCurve = .bezier(0.34, 1.56, 0.64, 1) }
                                        } else if let curve = AnimationCurve(name) {
                                            doc.config.animationCurve = curve
                                        }
                                        play()
                                    }))
                    }
                    .disabled(!c.animate)
                    if case let .bezier(x1, y1, x2, y2) = c.animationCurve {
                        ORow("Control points", description: "x1, y1, x2, y2 as in CSS; y past 1 overshoots") {
                            OTextField(placeholder: "0.34, 1.56, 0.64, 1", text: $ui.bezierText, mono: true, onSubmit: play)
                                .frame(width: 170)
                                .onAppear { ui.bezierText = Self.points(x1, y1, x2, y2) }
                                .onChange(of: c.animationCurve) { _, new in
                                    if case let .bezier(a, b, c, d) = new, AnimationCurve(ui.bezierText) != new { ui.bezierText = Self.points(a, b, c, d) }
                                }
                                .onChange(of: ui.bezierText) { _, text in
                                    if let curve = AnimationCurve(text), curve.isBezier { doc.config.animationCurve = curve }
                                }
                        }
                        .disabled(!c.animate)
                        .setting("motion.bezier", ui)
                    }
                    let bounce = ConfigOption.at(\Config.animationBounce).ui
                    OBarSlider(value: Binding(get: { c.animationBounce }, set: { doc.config.animationBounce = ($0 * 100).rounded() / 100 }),
                               range: bounce.range ?? 0...1, step: 0.01, label: bounce.label, symbol: "sparkles",
                               format: { "\(Int(($0 * 100).rounded()))%" }, onCommit: play)
                        .padding(.vertical, 12)
                        .disabled(!c.animate || !c.animationCurve.usesBounce)
                        .tooltip(bounce.help ?? "")
                        .setting(bounce.id, ui)
                }
                OGroup("Panels and window mode") {
                    OptionRow(\Config.panelAnimation, ui: ui) { label in
                        HStack(spacing: 8) {
                            OMenuPicker(title: label, options: PanelMotion.allCases.map { ($0.rawValue, $0.title) },
                                        selection: Binding(get: { c.panelAnimation.rawValue }, set: { raw in
                                            guard let m = PanelMotion(rawValue: raw) else { return }
                                            doc.config.panelAnimation = m
                                            PanelMotionDemo.play([m], keyboardOnly: true)
                                        }))
                            OButton("Play", icon: "play.fill", size: .sm) { PanelMotionDemo.play([c.panelAnimation], keyboardOnly: true) }
                        }
                    }
                    OptionRow(\Config.modeEffect, ui: ui) { label in
                        HStack(spacing: 8) {
                            OMenuPicker(title: label, options: ModeFX.Style.allCases.map { ($0.rawValue, $0.title) },
                                        selection: Binding(get: { c.modeEffect.rawValue }, set: { raw in
                                            guard let s = ModeFX.Style(rawValue: raw) else { return }
                                            doc.config.modeEffect = s
                                            ModeFX.shared.command([s.rawValue])
                                        }))
                            OButton("Play", icon: "play.fill", size: .sm) { ModeFX.shared.command([c.modeEffect.rawValue]) }
                                .disabled(c.modeEffect == .none)
                        }
                    }
                }
            }
        }
    }

    private var preview: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, flipped = ui.previewFlipped
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GapsPreview.wallpaper)
                DemoWindow(app: Self.previewApps[0], main: true, corner: 5)
                    .frame(width: max(1, (flipped ? w * 0.35 : w * 0.6) - 12), height: h - 16)
                    .offset(x: flipped ? w * 0.65 + 4 : 8, y: 8)
                DemoWindow(app: Self.previewApps[1], corner: 5)
                    .frame(width: max(1, (flipped ? w * 0.65 : w * 0.4) - 12), height: h - 16)
                    .offset(x: flipped ? 8 : w * 0.6 + 4, y: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: play)
        }
        .accessibilityHidden(true)
    }

    private static func points(_ v: Double...) -> String { v.map { String(format: "%g", $0) }.joined(separator: ", ") }

    private func play() {
        let c = doc.config
        // Exactly the curve the real animator uses.
        withAnimation(c.animate ? Animation(CurveAnimation(curve: c.animationCurve, bounce: c.animationBounce, duration: c.animationDuration)) : nil) {
            ui.previewFlipped.toggle()
        }
    }
}

/// SwiftUI animation that follows an `AnimationCurve`, so the preview moves like real windows do.
struct CurveAnimation: CustomAnimation {
    let curve: AnimationCurve
    let bounce: Double
    let duration: Double

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: curve.progress(time / duration, bounce: bounce))
    }
}

/// Plot of a curve's progress over time: a soft gradient under a rounded line, ending in a dot.
private struct CurveGraph: View {
    let curve: AnimationCurve
    let bounce: Double
    var instant = false
    var lineWidth: CGFloat = 2
    var color: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            // Leave headroom above and below for overshoot and anticipation, and room for the end dot.
            let inset: CGFloat = 4
            let w = size.width - inset * 2, h = size.height - inset * 2
            let samples = (0...120).map { Double($0) / 120 }
            let values = samples.map { instant ? ($0 > 0 ? 1 : 0) : curve.progress($0, bounce: bounce) }
            let lo = min(0, values.min() ?? 0), hi = max(1, values.max() ?? 1)
            func y(_ v: Double) -> CGFloat { inset + h - CGFloat((v - lo) / (hi - lo)) * h }
            let points = zip(samples, values).map { CGPoint(x: inset + CGFloat($0) * w, y: y($1)) }
            var line = Path()
            for (i, p) in points.enumerated() { if i == 0 { line.move(to: p) } else { line.addLine(to: p) } }
            var area = line
            area.addLine(to: CGPoint(x: inset + w, y: y(0)))
            area.addLine(to: CGPoint(x: inset, y: y(0)))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: inset), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if let end = points.last {
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }
}

/// A preset as a tile with its curve: outlined in `accent` when it's the current style.
private struct PresetTile: View {
    let preset: MotionPane.Preset
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                CurveGraph(curve: preset.animate ? preset.curve : .linear, bounce: preset.bounce, instant: !preset.animate,
                           lineWidth: 2, color: Theme.accent)
                    .frame(height: 34)
                    .padding(.horizontal, 8)
                Text(preset.name).font(Theme.body(12.5, selected ? .medium : .regular)).oneLine()
                    .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
            }
            .padding(.vertical, 12).padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(selected ? Theme.accentSoft : hover.on ? Theme.wellHover : Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5).opacity(selected ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.medium), value: selected)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
