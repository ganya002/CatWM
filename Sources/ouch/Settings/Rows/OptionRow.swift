import AppKit
import SwiftUI

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
