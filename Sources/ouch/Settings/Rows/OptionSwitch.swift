import AppKit
import SwiftUI

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
