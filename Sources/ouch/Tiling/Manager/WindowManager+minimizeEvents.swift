import AppKit

extension WindowManager {
    static let restoreHold: TimeInterval = 1.5

    func claimForCurrentWorkspace(_ ids: [CGWindowID]) {
        guard config.virtualWorkspaces, !restoringTemplate, let here = currentWorkspace else { return }
        for id in ids where workspaceOf[id] != here { model.assign(id, to: here) }
    }

    func windowMinimizeChanged(_ element: AXUIElement, minimized: Bool) {
        guard let w = windows.values.first(where: { CFEqual($0.element, element) }), w.minimized != minimized else {
            return scheduleRefresh(after: 0)
        }
        w.minimized = minimized
        w.observedAt = Date()
        guard !minimized else { return scheduleRefresh(after: 0) }
        claimForCurrentWorkspace([w.id])
        restoredEarly[w.id] = Date()
        snapNextPlacement.insert(w.id)
        refresh(instant: true, placing: [w.id])
        scheduleRefresh(after: 0)
    }

    func prewarm() {
        guard !isStarted else { return }
        scanner.observeDesktop(known: []) {}
    }
}
