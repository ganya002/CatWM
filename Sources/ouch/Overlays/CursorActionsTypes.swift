import AppKit

struct QuickAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var key: String = ""
    var isOn = false
    var destructive = false
    let run: () -> Void
}

final class CursorActionsModel: ObservableObject {
    @Published var title = ""
    @Published var actions: [QuickAction] = []
    @Published var hovered: String?
    @Published var modGlyph = "⌥"
    @Published var open = false
    @Published var anchor = CGPoint.zero
    var onPick: ((QuickAction) -> Void)?
}
