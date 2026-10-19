import AppKit
import SwiftUI

struct MotionPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
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
        Preset(name: "Relaxed", curve: .easeInOut, duration: 0.35),
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
                HStack(spacing: 12) {
                    VStack(spacing: 8) {
                        ForEach(Self.presets, id: \.name) { p in
                            PresetTile(preset: p, selected: matches(p, c)) {
                                doc.config.animate = p.animate
                                if p.animate {
                                    doc.config.animationCurve = p.curve
                                    doc.config.animationDuration = p.duration
                                    if p.curve.usesBounce { doc.config.animationBounce = p.bounce }
                                }
                                play()
                            }
                        }
                    }
                    .frame(width: 190)
                    .setting(MotionPane.searchStyle.id, ui)
                    preview
                        .setting(MotionPane.searchPreview.id, ui)
                }
                .frame(height: 170)
                .padding(.vertical, 10)
                ORow("Play it again", description: "Plays with exactly the curve windows use") {
                    OButton("Play", icon: "play.fill", size: .sm, action: play)
                }
            }

            OGroup("Feel") {
                OptionRows(pane: .motion, section: "Feel", doc: doc, ui: ui, onCommit: play)
            }

            AdditionalOptionGroups(pane: .motion, doc: doc, ui: ui, onCommit: play)

            AdvancedSection(pane: .motion, ui: ui) {
                OGroup("Curve") {
                    OptionRows(pane: .motion, section: "Curve", advanced: true, doc: doc, ui: ui, onCommit: play)
                }
                OGroup("Panels and window mode") {
                    OptionRows(pane: .motion, section: "Panels and window mode", advanced: true, doc: doc, ui: ui)
                }
                AdditionalOptionGroups(pane: .motion, advanced: true, doc: doc, ui: ui, onCommit: play)
            }
        }
    }

    private var preview: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, flipped = ui.previewFlipped
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(GapsPreview.wallpaper)
                DemoWindow(app: Self.previewApps[0], main: true, corner: 5)
                    .frame(width: max(1, (flipped ? w * 0.35 : w * 0.6) - 12), height: h - 16)
                    .offset(x: flipped ? w * 0.65 + 4 : 8, y: 8)
                DemoWindow(app: Self.previewApps[1], corner: 5)
                    .frame(width: max(1, (flipped ? w * 0.65 : w * 0.4) - 12), height: h - 16)
                    .offset(x: flipped ? 8 : w * 0.6 + 4, y: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: play)
        }
        .accessibilityHidden(true)
    }

    private static func points(_ v: Double...) -> String { v.map { String(format: "%g", $0) }.joined(separator: ", ") }

    private func play() {
        withAnimation(PanelMotion.windowAnimation) {
            ui.previewFlipped.toggle()
        }
    }
}

extension MotionPane {
    static let searchStyle = SettingEntry(id: "motion.style", title: "Animation style", pane: .motion, keywords: "preset snappy relaxed none")
    static let searchPreview = SettingEntry(id: "motion.preview", title: "Animation preview", pane: .motion, keywords: "play")
    static let searchBezier = SettingEntry(id: "motion.bezier", title: "Bezier control points", pane: .motion, advanced: true, keywords: "cubic custom curve")
}
