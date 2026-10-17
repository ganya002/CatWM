import AppKit

struct SettingInfo {
    let pane: Pane
    let id: String
    let label: String
    var help: String? = nil
    var keywords = ""
    var advanced = false
    var range: ClosedRange<Double>? = nil
    var scale: Double = 1
    var section = ""
    var order = 0
    var enabled: (Config) -> Bool = { _ in true }
    var unit = " pt"
    var width: CGFloat = 160
}

extension Pane {
    var defaultSection: String {
        switch self {
        case .general: "General"
        case .layout: "Gaps"
        case .windows: "Focus"
        case .motion: "Feel"
        case .templates: "Saved templates"
        case .shortcuts: "Keyboard"
        }
    }
}
