import AppKit

final class TabStripFollow {
    private struct Anchor {
        let group: Int
        let offset: CGVector
        let cursor: CGPoint
        let lowest: CGFloat
    }

    static let shared = TabStripFollow()
    private var anchor: Anchor?
    private var monitors: [Any] = []

    func follow(_ group: Int, at offset: CGVector, lowest: CGFloat) {
        anchor = Anchor(group: group, offset: offset, cursor: mouseLocation(), lowest: lowest)
        TabStrips.shared.shift(group, by: offset)
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDragged]
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.moved()
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in self?.moved() }
        monitors = [local, global].compactMap(\.self)
    }

    func end() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        anchor = nil
    }

    private func moved() {
        guard let anchor else { return }
        let cursor = mouseLocation()
        let dy = max(anchor.lowest, anchor.offset.dy + cursor.y - anchor.cursor.y)
        TabStrips.shared.shift(anchor.group, by: CGVector(dx: anchor.offset.dx + cursor.x - anchor.cursor.x, dy: dy))
    }
}
