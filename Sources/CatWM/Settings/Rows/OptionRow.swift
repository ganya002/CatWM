import AppKit
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
