import AppKit

final class CursorActionsModel: ObservableObject {
    @Published var title = ""
    @Published var actions: [QuickAction] = []
    @Published var hovered: String?
    @Published var modGlyph = "⌥"
    @Published var open = false
    @Published var anchor = CGPoint.zero
    var onPick: ((QuickAction) -> Void)?
}
