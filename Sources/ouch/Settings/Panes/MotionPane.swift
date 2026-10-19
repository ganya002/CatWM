import AppKit
import SwiftUI

struct MotionPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    static let previewApps = [
        DemoApp.all.filter(\.dark).randomElement() ?? DemoApp.all[0],
        DemoApp.all.filter { !$0.dark }.randomElement() ?? DemoApp.all[0]
    ].shuffled()

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
        Preset(name: "Playful", curve: .overshoot, duration: 0.35, bounce: 0.6)
    ]

    private func matches(_ preset: Preset, _ config: Config) -> Bool {
        guard preset.animate else { return !config.animate }
        return config.animate && config.animationCurve == preset.curve
            && abs(config.animationDuration - preset.duration) < 0.005
            && (!preset.curve.usesBounce || abs(config.animationBounce - preset.bounce) < 0.005)
    }

    var body: some View {
        let config = doc.config
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Style") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.presets, id: \.name) { preset in
                        PresetTile(preset: preset, selected: matches(preset, config)) {
                            doc.config.animate = preset.animate
                            if preset.animate {
                                doc.config.animationCurve = preset.curve
                                doc.config.animationDuration = preset.duration
                                if preset.curve.usesBounce { doc.config.animationBounce = preset.bounce }
                            }
                            play()
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .setting(MotionPane.searchStyle.id, settingsUI)

            OGroup("Preview") {
                preview
                    .frame(height: 150)
                    .padding(.vertical, 10)
                ORow("Play it again", description: "Plays with exactly the curve windows use") {
                    OButton("Play", icon: "play.fill", size: .small, action: play)
                }
            }
            .setting(MotionPane.searchPreview.id, settingsUI)

            OGroup("Feel") {
                OptionRows(pane: .motion, section: "Feel", doc: doc, settingsUI: settingsUI, onCommit: play)
            }

            AdditionalOptionGroups(pane: .motion, doc: doc, settingsUI: settingsUI, onCommit: play)

            AdvancedSection(pane: .motion, settingsUI: settingsUI) {
                OGroup("Curve") {
                    OptionRows(pane: .motion, section: "Curve", advanced: true, doc: doc, settingsUI: settingsUI,
                               onCommit: play)
                }
                OGroup("Panels and window mode") {
                    OptionRows(pane: .motion, section: "Panels and window mode", advanced: true, doc: doc,
                               settingsUI: settingsUI)
                }
                AdditionalOptionGroups(pane: .motion, advanced: true, doc: doc, settingsUI: settingsUI, onCommit: play)
            }
        }
    }

    private var preview: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height, flipped = settingsUI.previewFlipped
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(GapsPreview.wallpaper)
                DemoWindow(app: Self.previewApps[0], main: true, corner: 5)
                    .frame(width: max(1, (flipped ? width * 0.35 : width * 0.6) - 12), height: height - 16)
                    .offset(x: flipped ? width * 0.65 + 4 : 8, y: 8)
                DemoWindow(app: Self.previewApps[1], corner: 5)
                    .frame(width: max(1, (flipped ? width * 0.65 : width * 0.4) - 12), height: height - 16)
                    .offset(x: flipped ? 8 : width * 0.6 + 4, y: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: play)
        }
        .accessibilityHidden(true)
    }

    private static func points(_ values: Double...) -> String {
        values.map { String(format: "%g", $0) }.joined(separator: ", ")
    }

    private func play() {
        let config = doc.config
        let curve = CurveAnimation(curve: config.animationCurve, bounce: config.animationBounce,
                                   duration: config.animationDuration)
        withAnimation(config.animate ? Animation(curve) : nil) {
            settingsUI.previewFlipped.toggle()
        }
    }
}

extension MotionPane {
    static let searchStyle = SettingEntry(id: "motion.style", title: "Animation style", pane: .motion,
                                          keywords: "preset snappy smooth springy bouncy")
    static let searchPreview = SettingEntry(id: "motion.preview", title: "Animation preview", pane: .motion,
                                            keywords: "play")
    static let searchBezier = SettingEntry(id: "motion.bezier", title: "Bezier control points", pane: .motion,
                                           advanced: true, keywords: "cubic custom curve")
}
