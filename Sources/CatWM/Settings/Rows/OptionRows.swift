import AppKit
import CatWMKit
import MacKeysCore
import SwiftUI

struct OptionRows: View {
    private enum CustomRow {
        case floatingMode, sortNudge, animationDuration, animationCurve, animationBounce
        case panelAnimation, modeEffect, keyboardFinish, switcherExclude
    }

    private static let customRows: [PartialKeyPath<Config>: CustomRow] = [
        \Config.floatingIsDenylist: .floatingMode,
        \Config.sortNudge: .sortNudge,
        \Config.animationDuration: .animationDuration,
        \Config.animationCurve: .animationCurve,
        \Config.animationBounce: .animationBounce,
        \Config.panelAnimation: .panelAnimation,
        \Config.modeEffect: .modeEffect,
        \Config.keyboardFinish: .keyboardFinish,
        \Config.switcherExclude: .switcherExclude
    ]

    let pane: Pane
    let section: String
    var advanced = false
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    var onCommit: () -> Void = {}

    static func options(pane: Pane, section: String, advanced: Bool) -> [ConfigOption] {
        Options.all.enumerated().filter {
            $0.element.setting.map { $0.pane == pane && $0.section == section && $0.advanced == advanced } ?? false
        }.sorted {
            let lhs = $0.element.settingInfo.order
            let rhs = $1.element.settingInfo.order
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
    }

    static func additionalSections(pane: Pane, advanced: Bool) -> [String] {
        var sections: [String] = []
        for option in Options.all {
            guard let info = option.setting, info.pane == pane, info.advanced == advanced else { continue }
            guard !OptionPlacements.all.contains(where: {
                $0.pane == pane && $0.section == info.section && $0.advanced == advanced
            }) else {
                continue
            }
            if !sections.contains(info.section) { sections.append(info.section) }
        }
        return sections
    }

    var body: some View {
        ForEach(Self.options(pane: pane, section: section, advanced: advanced), id: \.key) { option in
            row(option).disabled(!option.settingInfo.enabled(doc.config))
        }
    }

    @ViewBuilder private func row(_ option: ConfigOption) -> some View {
        if let custom = Self.customRows[option.path] {
            customRow(custom)
        } else {
            genericRow(option)
        }
    }

    @ViewBuilder private func customRow(_ custom: CustomRow) -> some View {
        switch custom {
        case .floatingMode: floatingModeRow
        case .sortNudge: sortNudgeRows
        case .animationDuration: animationDurationRow
        case .animationCurve: animationCurveRows
        case .animationBounce: animationBounceRow
        case .panelAnimation: panelAnimationRow
        case .modeEffect: modeEffectRow
        case .keyboardFinish: keyboardFinishRow
        case .switcherExclude:
            let info = ConfigOption.at(\Config.switcherExclude).settingInfo
            AppList(ids: $doc.config.switcherExclude, title: info.label, empty: "They never show in the switcher")
                .setting(info.id, settingsUI)
        }
    }

    @ViewBuilder private func genericRow(_ option: ConfigOption) -> some View {
        if let path = option.path as? WritableKeyPath<Config, Bool> {
            OptionSwitch(path, doc: doc, settingsUI: settingsUI,
                         description: path == \Config.keyboardHelp ? keyboardHelpHint : nil)
        } else if let path = option.path as? WritableKeyPath<Config, CGFloat> {
            OptionSlider(path, doc: doc, settingsUI: settingsUI, width: option.settingInfo.width,
                         format: { "\(Int($0))" + option.settingInfo.unit })
        } else if !option.choices.isEmpty {
            OptionRow(option.path, settingsUI: settingsUI) { label in
                OMenuPicker(
                    title: label, options: option.choices,
                    selection: Binding(
                        get: { option.text(doc.config) },
                        set: { _ = option.read(&doc.config, $0, option.key) }))
            }
        } else if let setNumber = option.setNumber {
            OptionRow(option.path, settingsUI: settingsUI) { label in
                OSlider(
                    value: Binding(
                        get: { option.number(doc.config) * option.settingInfo.scale },
                        set: { setNumber(&doc.config, $0 / option.settingInfo.scale) }),
                    range: option.sliderRange(holding: option.number(doc.config) * option.settingInfo.scale),
                    step: 1, ticks: [option.resetValue], resetValue: option.resetValue,
                    width: option.settingInfo.width, label: label, format: { "\(Int($0))" + option.settingInfo.unit })
            }
        } else {
            OptionRow(option.path, settingsUI: settingsUI) { label in
                OTextField(
                    placeholder: label,
                    text: Binding(
                        get: { option.text(doc.config) },
                        set: { _ = option.read(&doc.config, $0, option.key) }))
            }
        }
    }

    private var keyboardHelpHint: String {
        let enter = doc.binds.first {
            $0.submap.isEmpty && $0.dispatcher == "submap" && $0.args.lowercased() != "reset"
        }
        guard let enter, let flags = ConfigText.flags(doc.resolvedMods(enter.mods)) else {
            return "Press \(doc.config.keyboardHelpKey) in window mode"
        }
        let hold = ConfigDocument.modifierCaps(flags.subtracting(.shift)).joined()
        return hold.isEmpty
            ? "Press \(doc.config.keyboardHelpKey) in window mode"
            : "Hold \(hold) after \(doc.prettyShortcut(enter).joined()), "
                + "or press \(doc.config.keyboardHelpKey) in window mode"
    }
}

extension OptionRows {
    private var floatingModeRow: some View {
        OptionRow(
            \Config.floatingIsDenylist, settingsUI: settingsUI,
            description: doc.config.floatingIsDenylist ? "Float; everything else tiles" : "Are the only ones that tile"
        ) { label in
            OSegmented(title: label, options: [(true, "Float"), (false, "Tile")],
                       selection: $doc.config.floatingIsDenylist)
        }
    }

    @ViewBuilder private var sortNudgeRows: some View {
        let nudge = ConfigOption.at(\Config.sortNudge)
        OSwitchRow(
            nudge.settingInfo.label, description: nudge.settingInfo.help,
            isOn: Binding(
                get: { doc.config.sortNudge > 0 },
                set: { doc.config.sortNudge = $0 ? Int(nudge.resetValue) : 0 })
        )
        .disabled(!doc.config.virtualWorkspaces)
        .setting(nudge.settingInfo.id, settingsUI)
        ORow("Crowded from", description: "Windows on one workspace") {
            OSlider(
                value: Binding(
                    get: { Double(doc.config.sortNudge) },
                    set: { doc.config.sortNudge = Int($0.rounded()) }),
                range: nudge.sliderRange(holding: Double(doc.config.sortNudge)), step: 1, ticks: [nudge.resetValue],
                resetValue: nudge.resetValue, width: 160, label: "Crowded from", format: { "\(Int($0)) windows" })
        }
        .disabled(!doc.config.virtualWorkspaces || doc.config.sortNudge == 0)
        .setting(WindowsPane.searchSortCrowded.id, settingsUI)
    }

    private var animationDurationRow: some View {
        let config = doc.config
        let duration = ConfigOption.at(\Config.animationDuration).settingInfo
        return OBarSlider(
            value: Binding(
                get: { config.animationDuration },
                set: { doc.config.animationDuration = ($0 * 100).rounded() / 100 }),
            range: duration.range ?? 0...1, step: 0.01, label: duration.label, symbol: "timer",
            format: { "\(Int(($0 * 1000).rounded())) ms" }, onCommit: onCommit
        )
        .padding(.vertical, 12)
        .disabled(!config.animate)
        .setting(duration.id, settingsUI)
    }

    @ViewBuilder private var animationCurveRows: some View {
        let config = doc.config
        OptionRow(\Config.animationCurve, settingsUI: settingsUI) { label in
            OMenuPicker(
                title: label,
                options: AnimationCurve.named.map { ($0.name, $0.title) }
                    + [("bezier", AnimationCurve.bezier(0, 0, 0, 0).title)],
                selection: Binding(
                    get: { config.animationCurve.isBezier ? "bezier" : config.animationCurve.name },
                    set: { name in
                        if name == "bezier" {
                            if !config.animationCurve.isBezier {
                                doc.config.animationCurve = .bezier(0.34, 1.56, 0.64, 1)
                            }
                        } else if let curve = AnimationCurve(name) {
                            doc.config.animationCurve = curve
                        }
                        onCommit()
                    }))
        }
        .disabled(!config.animate)
        if case .bezier(let startX, let startY, let endX, let endY) = config.animationCurve {
            bezierRow(config, points: Self.points(startX, startY, endX, endY))
        }
    }

    private func bezierRow(_ config: Config, points: String) -> some View {
        ORow("Control points", description: "x1, y1, x2, y2 as in CSS; y past 1 overshoots") {
            OTextField(placeholder: "0.34, 1.56, 0.64, 1", text: $settingsUI.bezierText, mono: true, onSubmit: onCommit)
                .frame(width: 170)
                .onAppear { settingsUI.bezierText = points }
                .onChange(of: config.animationCurve) { _, new in
                    if case .bezier(let startX, let startY, let endX, let endY) = new,
                       AnimationCurve(settingsUI.bezierText) != new {
                        settingsUI.bezierText = Self.points(startX, startY, endX, endY)
                    }
                }
                .onChange(of: settingsUI.bezierText) { _, text in
                    if let curve = AnimationCurve(text), curve.isBezier { doc.config.animationCurve = curve }
                }
        }
        .disabled(!config.animate)
        .setting(MotionPane.searchBezier.id, settingsUI)
    }

    private var animationBounceRow: some View {
        let config = doc.config
        let bounce = ConfigOption.at(\Config.animationBounce).settingInfo
        return OBarSlider(
            value: Binding(
                get: { config.animationBounce },
                set: { doc.config.animationBounce = ($0 * 100).rounded() / 100 }),
            range: bounce.range ?? 0...1, step: 0.01, label: bounce.label, symbol: "sparkles",
            format: { "\(Int(($0 * 100).rounded()))%" }, onCommit: onCommit
        )
        .padding(.vertical, 12)
        .disabled(!config.animate || !config.animationCurve.usesBounce)
        .setting(bounce.id, settingsUI)
    }

    private var panelAnimationRow: some View {
        let config = doc.config
        return OptionRow(\Config.panelAnimation, settingsUI: settingsUI) { label in
            HStack(spacing: 8) {
                OMenuPicker(
                    title: label, options: PanelMotion.allCases.map { ($0.rawValue, $0.title) },
                    selection: Binding(
                        get: { config.panelAnimation.rawValue },
                        set: { raw in
                            guard let motion = PanelMotion(rawValue: raw) else { return }
                            doc.config.panelAnimation = motion
                            PanelMotionDemo.shared.play([motion], keyboardOnly: true)
                        }))
                OButton("Play", icon: "play.fill", size: .small) {
                    PanelMotionDemo.shared.play([config.panelAnimation], keyboardOnly: true)
                }
            }
        }
    }

    private var modeEffectRow: some View {
        let config = doc.config
        return OptionRow(\Config.modeEffect, settingsUI: settingsUI) { label in
            HStack(spacing: 8) {
                OMenuPicker(
                    title: label, options: ModeEffect.allCases.map { ($0.rawValue, $0.title) },
                    selection: Binding(
                        get: { config.modeEffect.rawValue },
                        set: { raw in
                            guard let style = ModeEffect(rawValue: raw) else { return }
                            doc.config.modeEffect = style
                            ModeFX.shared.command([style.rawValue])
                        }))
                OButton("Play", icon: "play.fill", size: .small) { ModeFX.shared.command([config.modeEffect.rawValue]) }
                    .disabled(config.modeEffect == .none)
            }
        }
    }

    private var keyboardFinishRow: some View {
        OptionRow(\Config.keyboardFinish, settingsUI: settingsUI) { label in
            OMenuPicker(title: label, options: keyboardFinishOptions, selection: $doc.config.keyboardFinish)
        }
    }

    private static func points(_ values: Double...) -> String {
        values.map { String(format: "%g", $0) }.joined(separator: ", ")
    }

    private var keyboardFinishOptions: [(value: String, label: String)] {
        var options =
            [
                (value: "auto", label: "Auto (this Mac)"),
                (value: "macbook-pro", label: "MacBook Pro (family)"),
                (value: "macbook-air", label: "MacBook Air (family)"),
                (value: "macbook-neo", label: "MacBook Neo (family)"),
                (value: "magic-keyboard", label: "Magic Keyboard (family)")
            ] + FinishID.allCases.map { (value: MacKeyboard.slug($0.name), label: $0.name) }
        if !options.contains(where: { $0.value == doc.config.keyboardFinish }) {
            options.append((value: doc.config.keyboardFinish, label: doc.config.keyboardFinish))
        }
        return options
    }
}

struct AdditionalOptionGroups: View {
    let pane: Pane
    var advanced = false
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    var onCommit: () -> Void = {}

    var body: some View {
        ForEach(OptionRows.additionalSections(pane: pane, advanced: advanced), id: \.self) { section in
            OGroup(section) {
                OptionRows(pane: pane, section: section, advanced: advanced, doc: doc, settingsUI: settingsUI,
                           onCommit: onCommit)
            }
        }
    }
}

struct OptionPlacement {
    let pane: Pane
    let section: String
    let advanced: Bool
}
