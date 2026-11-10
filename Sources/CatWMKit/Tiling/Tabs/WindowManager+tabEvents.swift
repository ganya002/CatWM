import AppKit

extension WindowManager {
    package static let closedTabHold: TimeInterval = 2

    package func markClosedTab(_ id: CGWindowID) {
        guard tabs.group(of: id) != nil else { return }
        tabUI.closedTabs[id] = Date()
        scheduleRefresh(after: 0.3)
    }

    package func dropHiddenOnClose() {
        tabUI.closedTabs = tabUI.closedTabs.filter { id, since in
            tabs.group(of: id) != nil && -since.timeIntervalSinceNow < Self.closedTabHold
        }
        for id in tabUI.closedTabs.keys where !present.contains(id) && windows[id]?.minimized == false {
            tabUI.closedTabs[id] = nil
            model.leaveTab(id)
            Log.info("tabs: window \(id) hid when it was closed; it left its tabs")
        }
        if !tabUI.closedTabs.isEmpty { scheduleRefresh(after: 0.3) }
    }
}

extension WindowManager {
    package func cancelTabDrop() -> Bool {
        guard surface.showsTabDrop, let id = tabUI.drag.lifted ?? drags.first?.key else { return false }
        if tabUI.drag.lifted == nil, tabUI.drag.allowsJoin {
            tabUI.drag.beginNative(id)
        }
        guard let id = tabUI.drag.cancelDrop(on: surface) else { return false }
        Log.info("tabs: Escape cancelled the drop of \(id)")
        return true
    }
}
