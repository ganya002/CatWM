import AppKit

struct QuickAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keys: [String] = []
    var keyCode: UInt16?
    var keyMods: CGEventFlags = []
    var isOn = false
    var destructive = false
    var remove: (() -> Void)?
    let run: () -> Void
}
