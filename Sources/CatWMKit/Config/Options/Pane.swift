import Foundation

package enum Pane: String, CaseIterable, Identifiable {
    case general = "General", layout = "Layout", windows = "Windows", motion = "Motion", templates = "Templates"
    case shortcuts = "Shortcuts"
    package var id: Self { self }

    package var icon: String {
        switch self {
        case .general: "gearshape"
        case .layout: "square.grid.2x2"
        case .windows: "macwindow.on.rectangle"
        case .motion: "wand.and.stars"
        case .templates: "rectangle.3.group"
        case .shortcuts: "keyboard"
        }
    }
}
