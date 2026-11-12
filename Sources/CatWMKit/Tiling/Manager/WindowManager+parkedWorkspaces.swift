import AppKit

extension WindowManager {
    package var namedWorkspaces: Bool { config.virtualWorkspaces || config.parkedWorkspaces }

    package func syncParkedWorkspaces(screens: [Screen], present: Set<CGWindowID>) -> WorkspaceReconciliation {
        let spaces = Dictionary(screens.map { ($0.uuid, backend.currentSpace(display: $0.uuid)) },
                                uniquingKeysWith: { first, _ in first })
        let held = NSEvent.pressedMouseButtons & 1 != 0
        let observation = WorkspaceObservation(
            displays: screens.map { .init(id: $0.uuid, frame: $0.frame, space: spaces[$0.uuid] ?? 0, spaces: []) },
            frames: windows.mapValues(\.cachedFrame), present: present,
            held: held ? present : present.filter { animator.isBusy($0) },
            fullscreen: fullscreenSpaces())
        let plan = WorkspaceReconciliation.reconcile(observation, model: model, virtual: true,
                                                     homeSpace: spaces, displayOf: displayOf)
        model = plan.model
        displayOf = plan.displayOf
        for id in plan.park { park(id, screens: screens) }
        return plan
    }

    package func showParkedWorkspace(_ workspace: String, focusing preferred: Window?, focus takesFocus: Bool) {
        let screens = backend.screens()
        if let monitor = monitorOf[workspace], virtualShown[monitor] == workspace,
           let screen = screens.first(where: { $0.uuid == monitor }) {
            if takesFocus { focusShownWorkspace(workspace, preferred: preferred, on: screen) }
            return
        }
        guard let screen = currentScreen() ?? screens.first else { return }
        let previous = virtualShown[screen.uuid]
        if let previous, previous != workspace { previousWorkspace[screen.uuid] = previous }
        virtualShown[screen.uuid] = workspace
        model.show(workspace, on: screen.uuid)
        monitorOf[workspace] = screen.uuid
        if let previous, previous != workspace { beginSlide(from: previous, to: workspace, on: screen) }
        refresh()
        if takesFocus { focusShownWorkspace(workspace, preferred: preferred, on: screen) }
    }

    package func moveParkedWindow(_ window: Window, to workspace: String, follow: Bool) {
        if monitorOf[workspace] == nil, let display = displayOf[window.id] ?? currentScreen()?.uuid {
            monitorOf[workspace] = display
        }
        assignWindow(window, toWorkspace: workspace, from: workspaceOf[window.id], follow: follow, handOffFocus: true)
    }

    package static func parkedStep(from current: String, by delta: Int) -> String? {
        guard let number = Int(WorkspaceKey.number(current)) else { return nil }
        return String(max(1, number + delta))
    }
}
