import AppKit
import SwiftUI

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
