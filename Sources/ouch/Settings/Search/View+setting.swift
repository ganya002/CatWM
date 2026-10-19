import AppKit
import SwiftUI

extension View {
    func setting(_ id: String, _ settingsUI: SettingsUI) -> some View {
        modifier(SettingAnchor(id: id, settingsUI: settingsUI))
    }
}
