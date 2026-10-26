import AppKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case general = "General", scrolling = "Scrolling", windows = "Windows", motion = "Motion", templates = "Templates"
    case shortcuts = "Shortcuts"
    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .scrolling: "rectangle.split.3x1"
        case .windows: "macwindow.on.rectangle"
        case .motion: "wand.and.stars"
        case .templates: "rectangle.3.group"
        case .shortcuts: "keyboard"
        }
    }
    var configKind: ConfigKind? {
        switch self {
        case .motion: .animation
        case .shortcuts: .keyboard
        default: nil
        }
    }
}
