import AppKit
import SwiftUI

struct SettingAnchor: ViewModifier {
    let id: String
    @ObservedObject var ui: SettingsUI

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.accentSoft)
                    .padding(.horizontal, -12)
                    .opacity(ui.highlight == id ? 1 : 0)
            }
            .id(id)
    }
}
