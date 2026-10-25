import AppKit
import SwiftUI

struct SettingAnchor: ViewModifier {
    let id: String
    @ObservedObject var settingsUI: SettingsUI

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.accentSoft)
                    .padding(.horizontal, -12)
                    .opacity(settingsUI.highlight == id ? 1 : 0)
            }
            .id(id)
    }
}
