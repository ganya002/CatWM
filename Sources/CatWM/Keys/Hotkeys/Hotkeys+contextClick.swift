import AppKit

extension Hotkeys {
    static let windowMode = "window"

    func handlePointer(_ type: CGEventType, _ event: CGEvent) -> Bool {
        type == .scrollWheel ? handleScroll(event) : handleRightClick(type, event)
    }

    private func handleRightClick(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .rightMouseUp {
            defer { swallowRightUp = false }
            return swallowRightUp
        }
        swallowRightUp = false
        guard submap == Self.windowMode, !paused else { return false }
        let popup = Popup.shared
        if popup.hitsMenu(at: event.location) { return false }
        let menus = popup.windowNumbers
        popup.closeAll()
        guard let hit = CGWindowInfo.normalWindow(at: event.location, ignoring: menus),
              WindowManager.shared.windows[hit.id] != nil else { return false }
        swallowRightUp = true
        DispatchQueue.main.async { WindowContextMenu.open(hit.id) }
        return true
    }
}
