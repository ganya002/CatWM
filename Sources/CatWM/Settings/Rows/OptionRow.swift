import AppKit
import CatWMKit
import SwiftUI

struct OptionRow<Control: View>: View {
    @ObservedObject var settingsUI: SettingsUI
    let info: SettingInfo
    var description: String?
    let control: (String) -> Control

    init(_ path: PartialKeyPath<Config>, settingsUI: SettingsUI, description: String? = nil,
         @ViewBuilder control: @escaping (String) -> Control) {
        self.settingsUI = settingsUI
        self.info = ConfigOption.at(path).settingInfo
        self.description = description
        self.control = control
    }

    var body: some View {
        ORow(info.label, description: description ?? info.help) { control(info.label) }
            .setting(info.id, settingsUI)
    }
}

struct OptionSwitch: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    let path: WritableKeyPath<Config, Bool>
    var description: String?

    init(_ path: WritableKeyPath<Config, Bool>, doc: ConfigDocument, settingsUI: SettingsUI,
         description: String? = nil) {
        self.path = path
        self.doc = doc
        self.settingsUI = settingsUI
        self.description = description
    }

    var body: some View {
        let info = ConfigOption.at(path).settingInfo
        OSwitchRow(info.label, description: description ?? info.help, isOn: $doc.config[dynamicMember: path])
            .setting(info.id, settingsUI)
    }
}

struct OptionSlider: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    let path: WritableKeyPath<Config, CGFloat>
    var width: CGFloat = 160
    let format: (Double) -> String

    init(_ path: WritableKeyPath<Config, CGFloat>, doc: ConfigDocument, settingsUI: SettingsUI, width: CGFloat = 160,
         format: @escaping (Double) -> String) {
        self.path = path
        self.doc = doc
        self.settingsUI = settingsUI
        self.width = width
        self.format = format
    }

    var body: some View {
        let option = ConfigOption.at(path), info = option.settingInfo
        let value = Double(doc.config[keyPath: path]) * info.scale
        ORow(info.label, description: info.help) {
            OSlider(value: Binding(get: { Double(doc.config[keyPath: path]) * info.scale },
                                   set: { doc.config[keyPath: path] = CGFloat($0.rounded() / info.scale) }),
                    range: option.sliderRange(holding: value), step: 1, ticks: [option.resetValue],
                    resetValue: option.resetValue, width: width, label: info.label, format: format)
        }
        .setting(info.id, settingsUI)
    }
}

extension ConfigOption {
    var settingInfo: SettingInfo {
        guard let setting else { fatalError("config option \(key) has no Settings row") }
        return setting
    }

    var resetValue: Double { number(Config()) * settingInfo.scale }

    func sliderRange(holding value: Double) -> ClosedRange<Double> {
        let range = settingInfo.range ?? 0...1
        return min(range.lowerBound, value)...max(range.upperBound, value)
    }
}
