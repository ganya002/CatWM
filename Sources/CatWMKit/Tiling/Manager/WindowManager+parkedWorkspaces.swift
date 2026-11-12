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
        for id in floats.pinned where windows[id]?.isFloating == true && workspaceOf[id] == previous {
            model.assign(id, to: workspace)
        }
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

extension WindowManager {
    package static func specialWorkspace(_ raw: String) -> String {
        let name = raw.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        return "special:" + (name.isEmpty ? "special" : name)
    }

    package func toggleSpecialWorkspace(_ raw: String) {
        guard config.parkedWorkspaces else { return Log.info("special workspace: needs parked workspaces") }
        let workspace = Self.specialWorkspace(raw.isEmpty ? "special" : "special:" + raw)
        let open = floats.special?.workspace
        closeSpecialWorkspace()
        guard open != workspace, let current = currentWorkspace else { return refresh() }
        let members = order.filter { workspaceOf[$0] == workspace }.compactMap { windows[$0] }
        floats.special = (workspace, Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.isFloating) }))
        for window in members {
            model.assign(window.id, to: current)
            window.userFloating = .chosen(true)
        }
        refresh()
        members.forEach(centerWindow)
        if let first = members.last { focus(first) }
    }

    private func closeSpecialWorkspace() {
        guard let (workspace, floating) = floats.special else { return }
        floats.special = nil
        for (id, wasFloating) in floating {
            guard let window = windows[id] else { continue }
            window.userFloating = .chosen(wasFloating)
            model.assign(id, to: workspace)
        }
    }
}
