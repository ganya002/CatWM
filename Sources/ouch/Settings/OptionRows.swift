import AppKit
import SwiftUI

extension ConfigOption {
    var ui: SettingInfo {
        guard let setting else { fatalError("config option \(key) has no Settings row") }
        return setting
    }

    var resetValue: Double { number(Config()) * ui.scale }

    func sliderRange(holding value: Double) -> ClosedRange<Double> {
        let r = ui.range ?? 0...1
        return min(r.lowerBound, value)...max(r.upperBound, value)
    }
}

struct OptionSwitch: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let path: WritableKeyPath<Config, Bool>
    var description: String? = nil

    init(_ path: WritableKeyPath<Config, Bool>, doc: ConfigDocument, ui: SettingsUI, description: String? = nil) {
        self.path = path
        self.doc = doc
        self.ui = ui
        self.description = description
    }

    var body: some View {
        let s = ConfigOption.at(path).ui
        OSwitchRow(s.label, description: description ?? s.help, isOn: $doc.config[dynamicMember: path])
            .setting(s.id, ui)
    }
}

struct OptionRow<Control: View>: View {
    @ObservedObject var ui: SettingsUI
    let info: SettingInfo
    var description: String? = nil
    let control: (String) -> Control

    init(_ path: PartialKeyPath<Config>, ui: SettingsUI, description: String? = nil, @ViewBuilder control: @escaping (String) -> Control) {
        self.ui = ui
        self.info = ConfigOption.at(path).ui
        self.description = description
        self.control = control
    }

    var body: some View {
        ORow(info.label, description: description ?? info.help) { control(info.label) }
            .setting(info.id, ui)
    }
}

struct OptionSlider: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let path: WritableKeyPath<Config, CGFloat>
    var width: CGFloat = 160
    let format: (Double) -> String

    init(_ path: WritableKeyPath<Config, CGFloat>, doc: ConfigDocument, ui: SettingsUI, width: CGFloat = 160, format: @escaping (Double) -> String) {
        self.path = path
        self.doc = doc
        self.ui = ui
        self.width = width
        self.format = format
    }

    var body: some View {
        let option = ConfigOption.at(path), s = option.ui
        let value = Double(doc.config[keyPath: path]) * s.scale
        ORow(s.label, description: s.help) {
            OSlider(value: Binding(get: { Double(doc.config[keyPath: path]) * s.scale },
                                   set: { doc.config[keyPath: path] = CGFloat($0.rounded() / s.scale) }),
                    range: option.sliderRange(holding: value), step: 1, ticks: [option.resetValue], resetValue: option.resetValue,
                    width: width, label: s.label, format: format)
        }
        .setting(s.id, ui)
    }
}
