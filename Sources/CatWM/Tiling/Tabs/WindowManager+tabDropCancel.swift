import AppKit

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
