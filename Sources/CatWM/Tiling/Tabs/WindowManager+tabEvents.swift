import AppKit

extension WindowManager {
    static let closedTabHold: TimeInterval = 2

    func markClosedTab(_ id: CGWindowID) {
        guard tabs.group(of: id) != nil else { return }
        closedTabs[id] = Date()
        scheduleRefresh(after: 0.3)
    }

    func dropHiddenOnClose() {
        closedTabs = closedTabs.filter { id, since in
            tabs.group(of: id) != nil && -since.timeIntervalSinceNow < Self.closedTabHold
        }
        for id in closedTabs.keys where !present.contains(id) && windows[id]?.minimized == false {
            closedTabs[id] = nil
            model.leaveTab(id)
            Log.info("tabs: window \(id) hid when it was closed; it left its tabs")
        }
        if !closedTabs.isEmpty { scheduleRefresh(after: 0.3) }
    }
}

extension WindowManager {
    func cancelTabDrop() -> Bool {
        guard let id = draggedTab ?? drags.first?.key, !tabDropCancelled,
              TabDropHint.shared.showing || TabStrips.shared.isPreviewing else { return false }
        tabDropCancelled = true
        trackTabHover(nil)
        _ = TabStrips.shared.endPreview(of: id)
        TabDropHint.shared.hide()
        Log.info("tabs: Escape cancelled the drop of \(id)")
        return true
    }
}
