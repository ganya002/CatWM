import AppKit
import SwiftUI

extension View {
    func setting(_ id: String, _ ui: SettingsUI) -> some View {
        modifier(SettingAnchor(id: id, ui: ui))
    }
}
