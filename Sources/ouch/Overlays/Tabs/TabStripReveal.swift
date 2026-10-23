import AppKit

final class TabStripReveal {
    static let shared = TabStripReveal()
    private static let reach: CGFloat = 60
    private static let lead: CGFloat = 10
    private static let linger: TimeInterval = 0.3

    private(set) var isRevealed = false
    private var slot: CGRect?
    private var monitors: [Any] = []
    private var hideWork: DispatchWorkItem?

    func watch(_ slot: CGRect?) {
        self.slot = slot
        guard slot != nil else { return stop() }
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.moved()
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in self?.moved() }
        monitors = [local, global].compactMap(\.self)
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hideWork?.cancel()
        hideWork = nil
        isRevealed = false
    }

    private func moved() {
        guard let slot else { return }
        let point = NSEvent.mouseLocation
        let y = (NSScreen.screens.first?.frame.height ?? 0) - point.y
        let bottom = slot.minY + (isRevealed ? TabStrip.height : Self.lead)
        let inside = point.x >= slot.minX && point.x <= slot.maxX && y >= slot.minY - Self.reach && y <= bottom
        if inside {
            hideWork?.cancel()
            hideWork = nil
            reveal(true)
        } else if isRevealed, hideWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.hideWork = nil
                self?.reveal(false)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: work)
        }
    }

    private func reveal(_ revealed: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        WindowManager.shared.refresh()
    }
}
