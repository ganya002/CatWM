import AppKit
import MacKeysCore
import SwiftUI

struct OptionRows: View {
    let pane: Pane
    let section: String
    var advanced = false
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    var onCommit: () -> Void = {}

    static func options(pane: Pane, section: String, advanced: Bool) -> [ConfigOption] {
        Options.all.enumerated().filter {
            $0.element.setting.map { $0.pane == pane && $0.section == section && $0.advanced == advanced } ?? false
        }.sorted {
            let a = $0.element.ui.order
            let b = $1.element.ui.order
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }

    static func additionalSections(pane: Pane, advanced: Bool) -> [String] {
        var sections: [String] = []
        for option in Options.all {
            guard let info = option.setting, info.pane == pane, info.advanced == advanced else { continue }
            guard !OptionPlacements.all.contains(where: { $0.pane == pane && $0.section == info.section && $0.advanced == advanced }) else {
                continue
            }
            if !sections.contains(info.section) { sections.append(info.section) }
        }
        return sections
    }

    var body: some View {
        ForEach(Self.options(pane: pane, section: section, advanced: advanced), id: \.key) { option in
            row(option).disabled(!option.ui.enabled(doc.config))
        }
    }

    @ViewBuilder private func row(_ option: ConfigOption) -> some View {
        let c = doc.config
        if option.path == \Config.floatingIsBlacklist {
            OptionRow(
                \Config.floatingIsBlacklist, ui: ui,
                description: doc.config.floatingIsBlacklist ? "Float; everything else tiles" : "Are the only ones that tile"
            ) { label in
                OSegmented(title: label, options: [(true, "Float"), (false, "Tile")], selection: $doc.config.floatingIsBlacklist)
            }
        } else if option.path == \Config.sortStrategy {
            OptionRow(\Config.sortStrategy, ui: ui) { label in
                OMenuPicker(title: label, options: SortStrategy.allCases.map { ($0, $0.title) }, selection: $doc.config.sortStrategy)
            }
            .disabled(!doc.config.virtualWorkspaces)
        } else if option.path == \Config.sortNudge {
            let nudge = ConfigOption.at(\Config.sortNudge)
            OSwitchRow(
                nudge.ui.label, description: nudge.ui.help,
                isOn: Binding(get: { doc.config.sortNudge > 0 }, set: { doc.config.sortNudge = $0 ? Int(nudge.resetValue) : 0 })
            )
            .disabled(!doc.config.virtualWorkspaces)
            .setting(nudge.ui.id, ui)
            ORow("Crowded from", description: "Windows on one workspace") {
                OSlider(
                    value: Binding(
                        get: { Double(doc.config.sortNudge) },
                        set: { doc.config.sortNudge = Int($0.rounded()) }),
                    range: nudge.sliderRange(holding: Double(doc.config.sortNudge)), step: 1, ticks: [nudge.resetValue],
                    resetValue: nudge.resetValue, width: 160, label: "Crowded from", format: { "\(Int($0)) windows" })
            }
            .disabled(!doc.config.virtualWorkspaces || doc.config.sortNudge == 0)
            .setting(WindowsPane.searchSortCrowded.id, ui)
        } else if option.path == \Config.animationDuration {
            let duration = ConfigOption.at(\Config.animationDuration).ui
            OBarSlider(
                value: Binding(get: { c.animationDuration }, set: { doc.config.animationDuration = ($0 * 100).rounded() / 100 }),
                range: duration.range ?? 0...1, step: 0.01, label: duration.label, symbol: "timer",
                format: { "\(Int(($0 * 1000).rounded())) ms" }, onCommit: onCommit
            )
            .padding(.vertical, 12)
            .disabled(!c.animate)
            .setting(duration.id, ui)
        } else if option.path == \Config.animationCurve {
            OptionRow(\Config.animationCurve, ui: ui) { label in
                OMenuPicker(
                    title: label,
                    options: AnimationCurve.named.map { ($0.name, $0.title) } + [("bezier", AnimationCurve.bezier(0, 0, 0, 0).title)],
                    selection: Binding(
                        get: { c.animationCurve.isBezier ? "bezier" : c.animationCurve.name },
                        set: { name in
                            if name == "bezier" {
                                if !c.animationCurve.isBezier { doc.config.animationCurve = .bezier(0.34, 1.56, 0.64, 1) }
                            } else if let curve = AnimationCurve(name) {
                                doc.config.animationCurve = curve
                            }
                            onCommit()
                        }))
            }
            .disabled(!c.animate)
            if case .bezier(let x1, let y1, let x2, let y2) = c.animationCurve {
                ORow("Control points", description: "x1, y1, x2, y2 as in CSS; y past 1 overshoots") {
                    OTextField(placeholder: "0.34, 1.56, 0.64, 1", text: $ui.bezierText, mono: true, onSubmit: onCommit)
                        .frame(width: 170)
                        .onAppear { ui.bezierText = Self.points(x1, y1, x2, y2) }
                        .onChange(of: c.animationCurve) { _, new in
                            if case .bezier(let a, let b, let c, let d) = new, AnimationCurve(ui.bezierText) != new {
                                ui.bezierText = Self.points(a, b, c, d)
                            }
                        }
                        .onChange(of: ui.bezierText) { _, text in
                            if let curve = AnimationCurve(text), curve.isBezier { doc.config.animationCurve = curve }
                        }
                }
                .disabled(!c.animate)
                .setting(MotionPane.searchBezier.id, ui)
            }
        } else if option.path == \Config.animationBounce {
            let bounce = ConfigOption.at(\Config.animationBounce).ui
            OBarSlider(
                value: Binding(get: { c.animationBounce }, set: { doc.config.animationBounce = ($0 * 100).rounded() / 100 }),
                range: bounce.range ?? 0...1, step: 0.01, label: bounce.label, symbol: "sparkles",
                format: { "\(Int(($0 * 100).rounded()))%" }, onCommit: onCommit
            )
            .padding(.vertical, 12)
            .disabled(!c.animate || !c.animationCurve.usesBounce)
            .tooltip(bounce.help ?? "")
            .setting(bounce.id, ui)
        } else if option.path == \Config.panelAnimation {
            OptionRow(\Config.panelAnimation, ui: ui) { label in
                HStack(spacing: 8) {
                    OMenuPicker(
                        title: label, options: PanelMotion.allCases.map { ($0.rawValue, $0.title) },
                        selection: Binding(
                            get: { c.panelAnimation.rawValue },
                            set: { raw in
                                guard let m = PanelMotion(rawValue: raw) else { return }
                                doc.config.panelAnimation = m
                                PanelMotionDemo.play([m], keyboardOnly: true)
                            }))
                    OButton("Play", icon: "play.fill", size: .sm) { PanelMotionDemo.play([c.panelAnimation], keyboardOnly: true) }
                }
            }
        } else if option.path == \Config.modeEffect {
            OptionRow(\Config.modeEffect, ui: ui) { label in
                HStack(spacing: 8) {
                    OMenuPicker(
                        title: label, options: ModeFX.Style.allCases.map { ($0.rawValue, $0.title) },
                        selection: Binding(
                            get: { c.modeEffect.rawValue },
                            set: { raw in
                                guard let s = ModeFX.Style(rawValue: raw) else { return }
                                doc.config.modeEffect = s
                                ModeFX.shared.command([s.rawValue])
                            }))
                    OButton("Play", icon: "play.fill", size: .sm) { ModeFX.shared.command([c.modeEffect.rawValue]) }
                        .disabled(c.modeEffect == .none)
                }
            }
        } else if option.path == \Config.keyboardFinish {
            OptionRow(\Config.keyboardFinish, ui: ui) { label in
                OMenuPicker(title: label, options: keyboardFinishOptions, selection: $doc.config.keyboardFinish)
            }
        } else if let path = option.path as? WritableKeyPath<Config, Bool> {
            OptionSwitch(path, doc: doc, ui: ui, description: path == \Config.keyboardHelp ? keyboardHelpHint : nil)
        } else if let path = option.path as? WritableKeyPath<Config, CGFloat> {
            OptionSlider(path, doc: doc, ui: ui, width: option.ui.width, format: { "\(Int($0))" + option.ui.unit })
        } else if !option.choices.isEmpty {
            OptionRow(option.path, ui: ui) { label in
                OMenuPicker(
                    title: label, options: option.choices,
                    selection: Binding(get: { option.text(doc.config) }, set: { _ = option.read(&doc.config, $0, option.key) }))
            }
        } else if let setNumber = option.setNumber {
            OptionRow(option.path, ui: ui) { label in
                OSlider(
                    value: Binding(
                        get: { option.number(doc.config) * option.ui.scale },
                        set: { setNumber(&doc.config, $0 / option.ui.scale) }),
                    range: option.sliderRange(holding: option.number(doc.config) * option.ui.scale),
                    step: 1, ticks: [option.resetValue], resetValue: option.resetValue,
                    width: option.ui.width, label: label, format: { "\(Int($0))" + option.ui.unit })
            }
        } else {
            OptionRow(option.path, ui: ui) { label in
                OTextField(
                    placeholder: label,
                    text: Binding(get: { option.text(doc.config) }, set: { _ = option.read(&doc.config, $0, option.key) }))
            }
        }
    }

    private static func points(_ v: Double...) -> String { v.map { String(format: "%g", $0) }.joined(separator: ", ") }

    private var keyboardFinishOptions: [(value: String, label: String)] {
        var options =
            [
                (value: "auto", label: "Auto (this Mac)"),
                (value: "macbook-pro", label: "MacBook Pro (family)"),
                (value: "macbook-air", label: "MacBook Air (family)"),
                (value: "macbook-neo", label: "MacBook Neo (family)"),
                (value: "magic-keyboard", label: "Magic Keyboard (family)"),
            ] + FinishID.allCases.map { (value: MacKeyboard.slug($0.name), label: $0.name) }
        if !options.contains(where: { $0.value == doc.config.keyboardFinish }) {
            options.append((value: doc.config.keyboardFinish, label: doc.config.keyboardFinish))
        }
        return options
    }

    private var keyboardHelpHint: String {
        let enter = doc.binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && $0.args.lowercased() != "reset" }
        guard let enter, let flags = ConfigDocument.flags(doc.resolvedMods(enter.mods)) else {
            return "Press \(doc.config.keyboardHelpKey) in window mode"
        }
        let hold = ConfigDocument.modifierCaps(flags.subtracting(.shift)).joined()
        return hold.isEmpty
            ? "Press \(doc.config.keyboardHelpKey) in window mode"
            : "Hold \(hold) after \(doc.prettyShortcut(enter).joined()), or press \(doc.config.keyboardHelpKey) in window mode"
    }

}

struct AdditionalOptionGroups: View {
    let pane: Pane
    var advanced = false
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    var onCommit: () -> Void = {}

    var body: some View {
        ForEach(OptionRows.additionalSections(pane: pane, advanced: advanced), id: \.self) { section in
            OGroup(section) {
                OptionRows(pane: pane, section: section, advanced: advanced, doc: doc, ui: ui, onCommit: onCommit)
            }
        }
    }
}

struct OptionPlacement {
    let pane: Pane
    let section: String
    let advanced: Bool
}
