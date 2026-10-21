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
            createWorkspaceThenMove(window, to: workspace, follow: follow)
            return
        }
        let from = workspaceOf[window.id]
        let hadFocus = focusedWindow()?.id == window.id
        let known = windows[window.id] != nil
        let frame = window.frame
        let visibleTarget = Spaces.current(display: target.display) == target.space
        workspaceMoves.insert(window.id)
        if visibleTarget {
            autoSwitchAfter = Date().addingTimeInterval(0.7)
            if !known { windows[window.id] = window; order.append(window.id); watch(window) }
            model.assign(window.id, to: workspace)
            monitorOf[workspace] = target.display
            snapNextPlacement.insert(window.id)
            refresh(instant: true, placing: [window.id])
        } else {
            animator.cancel(window.id)
        }
        animator.afterPendingWrites { [weak self] in
            guard let self else { return }
            let displayBatch = visibleTarget ? WindowServerUpdates.shared.begin() : nil
            let started = Date()
            Spaces.move(window: window.id, to: target.space, waitUntilOnScreen: visibleTarget) { [weak self] moved in
                guard let self else { displayBatch?.finish(); return }
                defer { displayBatch?.finish() }
                workspaceMoves.remove(window.id)
                nativeMoveTargets[window.id] = nil
                guard moved || Spaces.of(window: window.id) == [target.space], window.isValid else {
                    rollBackNativeMove(window, from: from, known: known, frame: visibleTarget ? frame : nil)
                    return
                }
                let held = Int(Date().timeIntervalSince(started) * 1000)
                Log.info("native workspaces: moved window \(window.id) to workspace \(workspace) in \(held) ms")
                completeNativeMigration(window.id, workspace: workspace)
                nativeMembership[window.id] = target.space
                assignWindow(window, toWorkspace: workspace, from: from, follow: follow, handOffFocus: hadFocus)
            }
        }
    }

    private func rollBackNativeMove(_ window: Window, from: String?, known: Bool, frame: CGRect?) {
        HUD.shared.show("macOS couldn't move this window", on: currentScreen()?.nsScreen)
        if let frame {
            if known { model.assign(window.id, to: from) } else { forget(window.id) }
            if window.isValid, !frame.isNull { window.setFrame(frame) }
        }
        scheduleRefresh(after: 0)
    }

    private func createWorkspaceThenMove(_ window: Window, to workspace: String, follow: Bool) {
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
