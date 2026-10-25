import AppKit
import SwiftUI

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
