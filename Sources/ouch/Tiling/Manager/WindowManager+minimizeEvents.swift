import AppKit

extension WindowManager {
    static let restoreHold: TimeInterval = 1.5

    func claimForCurrentWorkspace(_ ids: [CGWindowID]) {
        guard config.virtualWorkspaces, !restoringTemplate, let here = currentWorkspace else { return }
        for id in ids where workspaceOf[id] != here {
            guard let target = nativeCatalog.entry(here), Spaces.of(window: id).contains(target.space) else { continue }
            model.assign(id, to: here)
        }
    }

    func windowMinimizeChanged(_ element: AXUIElement, minimized: Bool) {
        guard let window = windows.values.first(where: { CFEqual($0.element, element) }),
              window.minimized != minimized else {
            return scheduleRefresh(after: 0)
        }
        window.minimized = minimized
        window.observedAt = Date()
        guard !minimized else { return scheduleRefresh(after: 0) }
        claimForCurrentWorkspace([window.id])
        restoreTabGroup(of: window.id)
        restoredEarly[window.id] = Date()
        snapNextPlacement.insert(window.id)
        refresh(instant: true, placing: [window.id])
        scheduleRefresh(after: 0)
    }

    func prewarm() {
        guard !isStarted else { return }
        scanner.observeDesktop(known: []) {}
    }
}
