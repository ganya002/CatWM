// Tiling: workspace bookkeeping (which window is where, what each display shows, focus history) as one value.
import CoreGraphics

/// Everything that says which workspace a window is on, what each display shows and which windows had
/// focus. It is a value: a copy (see `snapshot`) is the state as it was, which the Sort panel's Revert
/// and Undo put back. `WindowManager` keeps one and forwards its old property names to it.
struct WorkspaceModel {
    /// Workspace each window belongs to. Change it through `assign`, `swapWorkspaces`, `keepWorkspaces` and `forget`.
    private(set) var workspaceOf: [CGWindowID: String] = [:]
    var order: [CGWindowID] = []            // tiling order; first window on a screen is "main"
    var monitorOf: [String: String] = [:]   // display UUID each workspace lives on
    var shown: [String: String] = [:] {     // display UUID → workspace it shows right now
        didSet { shownSet = Set(shown.values) }
    }
    var virtualShown: [String: String] = [:] // display UUID → Ouch workspace on its home Space
    var states: [String: ScreenState] = [:]  // layout state per workspace
    var lastFocused: [String: CGWindowID] = [:] // workspace → the window last focused on it
    var focusStamps: [CGWindowID: Int] = [:] // focus history: higher was focused more recently
    var focusClock = 0
    var focusOrder: [CGWindowID] = []        // most recently focused first
    /// The workspaces in `shown`, kept with it: `isShown` runs inside loops over every window.
    private(set) var shownSet: Set<String> = []

    func isShown(_ ws: String?) -> Bool { ws.map(shownSet.contains) ?? false }

    // MARK: Windows

    mutating func assign(_ id: CGWindowID, to ws: String?) { workspaceOf[id] = ws }

    mutating func swapWorkspaces(_ a: CGWindowID, _ b: CGWindowID) {
        (workspaceOf[a], workspaceOf[b]) = (workspaceOf[b], workspaceOf[a])
    }

    /// Drops the assignment of every window whose workspace fails `keep`.
    mutating func keepWorkspaces(where keep: (String) -> Bool) { workspaceOf = workspaceOf.filter { keep($0.value) } }

    /// A window closed. macOS reuses window IDs, so nothing of it may stay: a new window with its ID
    /// would get its workspace, its place in the tiling order or its focus history.
    mutating func forget(_ id: CGWindowID) {
        workspaceOf[id] = nil
        order.removeAll { $0 == id }
        focusStamps[id] = nil
        focusOrder.removeAll { $0 == id }
        lastFocused = lastFocused.filter { $0.value != id }
    }

    // MARK: Displays

    mutating func show(_ ws: String?, on display: String) { shown[display] = ws }

    /// Forgets every workspace and what the displays show (the workspace mode changed). Tiling order and
    /// focus history stay: they belong to the windows.
    mutating func resetWorkspaces() {
        workspaceOf = [:]; monitorOf = [:]; shown = [:]; virtualShown = [:]; states = [:]; lastFocused = [:]
    }

    // MARK: Focus

    /// Records `id` as the most recently focused window.
    mutating func noteFocus(_ id: CGWindowID) {
        if focusStamps[id] != focusClock {
            focusClock += 1
            focusStamps[id] = focusClock
        }
        focusOrder.removeAll { $0 == id }
        focusOrder.insert(id, at: 0)
        if focusOrder.count > 80 { focusOrder.removeLast(focusOrder.count - 80) }
    }

    /// The window focused most recently of `ids`, if any of them was ever focused.
    func mostRecent<S: Sequence>(of ids: S) -> CGWindowID? where S.Element == CGWindowID {
        guard let id = ids.max(by: { (focusStamps[$0] ?? 0) < (focusStamps[$1] ?? 0) }), focusStamps[id] != nil else { return nil }
        return id
    }

    // MARK: Snapshot

    /// A copy that later changes don't reach. Layout states are objects, so they are copied too.
    func snapshot() -> WorkspaceModel {
        var copy = self
        copy.states = states.mapValues { $0.copy() }
        return copy
    }
}
