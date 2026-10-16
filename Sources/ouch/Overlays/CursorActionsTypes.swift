// Overlays: shared types for the cursor quick actions (indicator, menu and actions).
import AppKit

/// One entry in the cursor quick-action menu.
struct QuickAction: Identifiable {
    let id: String            // stable name, e.g. "float"
    let title: String
    let symbol: String        // SF Symbol name
    var keys: [String] = []   // window-mode shortcut as keycaps, e.g. ["⇧", "F"]; empty for none
    var keyCode: UInt16?      // that shortcut's key, so a press runs this row while the menu is open
    var keyMods: CGEventFlags = []
    var isOn = false          // the state is on now (e.g. the window floats)
    var destructive = false   // drawn in the warning colour (close)
    let run: () -> Void
}

/// What the menu shows. `CursorActions` fills it; `CursorActionsView` draws it.
final class CursorActionsModel: ObservableObject {
    @Published var title = ""                 // name of the window under the cursor
    @Published var actions: [QuickAction] = []
    @Published var hovered: String?           // id of the action under the pointer
    @Published var modGlyph = "⌥"             // the modifier whose tap opens the menu, drawn in the mark
    @Published var open = false              // false: only the small indicator is drawn
    /// Pointer position in the panel, so the view can lay out around it. Panel space, y down.
    @Published var anchor = CGPoint.zero
    /// Called by the view when the user picks an action. `CursorActions` closes the menu and runs it.
    var onPick: ((QuickAction) -> Void)?
}
