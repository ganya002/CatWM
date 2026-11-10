import AppKit
import CatWMKit
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
        Preset(name: "Relaxed", curve: .easeInOut, duration: 0.35)
    ]

    private func matches(_ preset: Preset, _ config: Config) -> Bool {
        guard preset.animate else { return !config.animate }
        return config.animate && config.animationCurve == preset.curve
            && abs(config.animationDuration - preset.duration) < 0.005
            && (!preset.curve.usesBounce || abs(config.animationBounce - preset.bounce) < 0.005)
    }

    var body: some View {
        let config = doc.config
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            OGroup("Style") {
                HStack(spacing: 12) {
                    VStack(spacing: 8) {
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
                    .frame(width: 190)
                    .setting(MotionPane.searchStyle.id, settingsUI)
                    preview
                        .setting(MotionPane.searchPreview.id, settingsUI)
                }
                .frame(height: 170)
                .padding(.vertical, Theme.Space.small)
                ORow("Play it again", description: "Plays with exactly the curve windows use") {
                    OButton("Play", icon: "play.fill", size: .small, action: play)
                }
            }

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
                DemoWindow(app: Self.previewApps[0], main: true, corner: Theme.Radius.extraSmall)
                    .frame(width: max(1, (flipped ? width * 0.35 : width * 0.6) - 12), height: height - 16)
                    .offset(x: flipped ? width * 0.65 + 4 : 8, y: 8)
                DemoWindow(app: Self.previewApps[1], corner: Theme.Radius.extraSmall)
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
        withAnimation(Motion.user) {
            settingsUI.previewFlipped.toggle()
        }
    }
}

extension MotionPane {
    static let searchStyle = SettingEntry(id: "motion.style", title: "Animation style", pane: .motion,
                                          keywords: "preset snappy relaxed none")
    static let searchPreview = SettingEntry(id: "motion.preview", title: "Animation preview", pane: .motion,
                                            keywords: "play")
    static let searchBezier = SettingEntry(id: "motion.bezier", title: "Bezier control points", pane: .motion,
                                           advanced: true, keywords: "cubic custom curve")
}
