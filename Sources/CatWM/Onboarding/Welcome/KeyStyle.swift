import AppKit
import SwiftUI

enum KeyStyle: String, CaseIterable {
    case vim, wasd

    var configID: String { ConfigLibrary.builtInPrefix + (self == .vim ? "keyboard.default" : "keyboard.wasd") }
    var title: String { self == .vim ? "Vim" : "WASD" }
    var caption: String { self == .vim ? "Right hand on the home row" : "Left hand, like a game" }

    static var current: KeyStyle? {
        let id = SettingsWindow.shared.library.current(.keyboard).id
        return allCases.first { $0.configID == id }
    }
}
