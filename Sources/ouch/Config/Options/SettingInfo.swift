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
}
