import AppKit
import SwiftUI

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
