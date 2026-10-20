import AppKit
import SwiftUI

extension WindowsPane {
    func add() {
        let id = settingsUI.newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !doc.config.floating.contains(id) else { return }
        withAnimation(Motion.easeOut) { doc.config.floating.append(id) }
        settingsUI.newID = ""
    }
}
