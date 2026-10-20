import AppKit

extension WindowManager {
    func assignManagedWindow(_ id: CGWindowID, to workspace: String?) {
        guard config.virtualWorkspaces, let workspace, nativeCatalog.entry(workspace) != nil,
              let window = windows[id] else {
            model.assign(id, to: workspace)
            return
        }
        moveNativeWindow(window, to: workspace, follow: true)
    }

    func moveNativeWindow(_ window: Window, to workspace: String, follow: Bool) {
        updateNativeCatalog(Screen.all())
        guard !window.isNativeFullscreen, !workspaceMoves.contains(window.id) else { return }
        guard let target = nativeCatalog.entry(workspace) else {
            guard let screen = currentScreen() ?? Screen.all().first else { return }
            nativeMoveTargets[window.id] = workspace
            Task { @MainActor in
                do {
                    _ = try await self.ensureNativeWorkspace(workspace, on: screen, while: {
                        self.nativeMoveTargets[window.id] == workspace
                    })
                    guard self.nativeMoveTargets[window.id] == workspace, window.isValid else { return }
                    self.nativeMoveTargets[window.id] = nil
                    self.moveNativeWindow(window, to: workspace, follow: follow)
                } catch is CancellationError { } catch {
                    Log.info("native workspaces: move \(window.id) to \(workspace) failed: "
                        + error.localizedDescription)
                    self.nativeMoveTargets[window.id] = nil
                    HUD.shared.show(error.localizedDescription, on: screen.nsScreen)
                    self.scheduleRefresh(after: 0)
                }
            }
            return
        }
        let from = workspaceOf[window.id]
        workspaceMoves.insert(window.id)
        animator.cancel(window.id)
        Spaces.move(window: window.id, to: target.space) { [weak self] moved in
            guard let self else { return }
            self.workspaceMoves.remove(window.id)
            self.nativeMoveTargets[window.id] = nil
            guard moved, window.isValid else {
                HUD.shared.show("macOS couldn't move this window", on: self.currentScreen()?.nsScreen)
                self.scheduleRefresh(after: 0)
                return
            }
            Log.info("native workspaces: moved window \(window.id) to workspace \(workspace)")
            self.completeNativeMigration(window.id, workspace: workspace)
            self.nativeMembership[window.id] = target.space
            self.assignWindow(window, toWorkspace: workspace, from: from, display: target.display, follow: follow)
            self.scheduleRefresh(after: 0)
        }
    }
    @MainActor func ensureNativeWorkspace(_ name: String, on screen: Screen,
                                          while current: () -> Bool = { true }) async throws
        -> NativeWorkspaceCatalog.Entry {
        let free = await poll(5, every: 30_000_000) { !current() || !(nativeCreationBusy || nativeDesktop.isRunning) }
        guard current() else { throw CancellationError() }
        guard free else { throw DesktopTransitionError.check("The previous Desktop action did not finish") }
        updateNativeCatalog(Screen.all())
        if let entry = nativeCatalog.entry(name) { return entry }
        guard !name.isEmpty, !isPending(name), isVirtual(name) else {
            throw DesktopTransitionError.check("This workspace name is unavailable")
        }
        nativeCreationBusy = true
        defer { nativeCreationBusy = false; scheduleRefresh(after: 0) }
        let space = try await DesktopLifecycle.create(on: screen)
        nativeCatalog.bind(name, to: space, on: screen.uuid)
        updateNativeCatalog(Screen.all())
        guard let entry = nativeCatalog.entry(name) else {
            throw DesktopTransitionError.check("The Desktop disappeared")
        }
        return entry
    }

    func commitNativeRemovals() {
        let removed = nativeDroppedWorkspaces
        guard !removed.isEmpty else { return }
        Task { @MainActor in
            guard await poll(5, every: 50_000_000, until: {
                !self.nativeDesktop.isRunning && !self.nativeCreationBusy && self.workspaceMoves.isEmpty
            }) else { return }
            for name in removed {
                guard let entry = self.nativeCatalog.entry(name),
                      let screen = Screen.all().first(where: { $0.uuid == entry.display }) else { continue }
                do { try await DesktopLifecycle.remove(entry.space, on: screen) } catch {
                    HUD.shared.show(error.localizedDescription, on: screen.nsScreen)
                }
            }
            self.nativeDroppedWorkspaces.subtract(removed)
            self.scheduleRefresh(after: 0)
        }
    }
}
