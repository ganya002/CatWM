import AppKit

extension WindowManager {
    func assignManagedWindow(_ id: CGWindowID, to workspace: String?) {
        guard config.virtualWorkspaces, let workspace, desktops.nativeCatalog.entry(workspace) != nil,
              let window = windows[id] else {
            model.assign(id, to: workspace)
            return
        }
        moveNativeWindow(window, to: workspace, follow: true)
    }

    func moveNativeWindow(_ window: Window, to workspace: String, follow: Bool, from origin: String?? = nil) {
        updateNativeCatalog(Screen.all())
        guard !workspaceMoves.contains(window.id) else { return }
        guard !window.fullscreenUnlessStalled else { desktops.nativeMoveTargets[window.id] = nil; return }
        guard !desktops.nativeCreationBusy, let target = desktops.nativeCatalog.entry(workspace) else {
            createWorkspaceThenMove(window, to: workspace, follow: follow)
            return
        }
        let from = origin ?? workspaceOf[window.id]
        let hadFocus = focusedWindow()?.id == window.id
        let known = windows[window.id] != nil
        let frame = window.frameUnlessStalled
        let visibleTarget = Spaces.current(display: target.display) == target.space
        workspaceMoves.insert(window.id)
        if follow, !visibleTarget {
            animator.cancel(window.id)
            desktops.followMoves[window.id] = .init(window: window, workspace: workspace, space: target.space,
                                                    from: from)
            showWorkspace(workspace, focusing: window)
            return
        }
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
        animator.afterPendingWrites(pids: [window.pid]) { [weak self] in
            guard let self else { return }
            let displayBatch = visibleTarget ? WindowServerUpdates.shared.begin() : nil
            let started = Date()
            Spaces.move(window: window.id, to: target.space, waitUntilOnScreen: visibleTarget) { [weak self] moved in
                guard let self else { displayBatch?.finish(); return }
                defer { displayBatch?.finish() }
                workspaceMoves.remove(window.id)
                desktops.nativeMoveTargets[window.id] = nil
                guard moved || Spaces.of(window: window.id) == [target.space], window.isValidUnlessStalled else {
                    rollBackNativeMove(window, from: from, known: known, frame: visibleTarget ? frame : nil)
                    return
                }
                let held = Int(Date().timeIntervalSince(started) * 1000)
                Log.info("native workspaces: moved window \(window.id) to workspace \(workspace) in \(held) ms")
                completeNativeMigration(window.id, workspace: workspace)
                desktops.nativeMembership[window.id] = target.space
                assignWindow(window, toWorkspace: workspace, from: from, follow: follow, handOffFocus: hadFocus)
            }
        }
    }

    @MainActor func completeFollowMove(_ move: NativeDesktopState.FollowMove) async throws {
        let id = move.window.id
        desktops.followMoves[id] = nil
        let moved = await withCheckedContinuation { done in
            Spaces.move(window: id, to: move.space) { done.resume(returning: $0) }
        }
        workspaceMoves.remove(id)
        guard moved || Spaces.of(window: id) == [move.space], move.window.isValidUnlessStalled else {
            throw DesktopTransitionError.check("macOS couldn't move this window")
        }
        Log.info("native workspaces: moved window \(id) to workspace \(move.workspace)")
        completeNativeMigration(id, workspace: move.workspace)
        desktops.nativeMembership[id] = move.space
        assignWindow(move.window, toWorkspace: move.workspace, from: move.from, follow: false, handOffFocus: false)
    }

    func dropFollowMoves() {
        workspaceMoves.subtract(desktops.followMoves.keys)
        desktops.followMoves = [:]
        arrivals = [:]
    }

    private func rollBackNativeMove(_ window: Window, from: String?, known: Bool, frame: CGRect?) {
        HUD.shared.show("macOS couldn't move this window", on: currentScreen()?.nsScreen)
        if let frame {
            if known { model.assign(window.id, to: from) } else { forget(window.id) }
            if !frame.isNull, window.isValidUnlessStalled { window.setFrame(frame) }
        }
        scheduleRefresh(after: 0)
    }

    private func createWorkspaceThenMove(_ window: Window, to workspace: String, follow: Bool) {
        guard let screen = currentScreen() ?? Screen.all().first else { return }
        desktops.nativeMoveTargets[window.id] = workspace
        Task { @MainActor in
            do {
                _ = try await self.ensureNativeWorkspace(workspace, on: screen, while: {
                    self.desktops.nativeMoveTargets[window.id] == workspace
                })
                guard self.desktops.nativeMoveTargets[window.id] == workspace else { return }
                self.desktops.nativeMoveTargets[window.id] = nil
                guard window.isValidUnlessStalled else { return }
                self.moveNativeWindow(window, to: workspace, follow: follow)
            } catch is CancellationError { } catch {
                Log.info("native workspaces: move \(window.id) to \(workspace) failed: "
                    + error.localizedDescription)
                self.desktops.nativeMoveTargets[window.id] = nil
                HUD.shared.show(error.localizedDescription, on: screen.nsScreen)
                self.scheduleRefresh(after: 0)
            }
        }
    }

    @MainActor func ensureNativeWorkspace(_ name: String, on screen: Screen,
                                          while current: () -> Bool = { true }) async throws
        -> NativeWorkspaceCatalog.Entry {
        let free = await poll(5, every: 30_000_000) {
            !current() || !(desktops.nativeCreationBusy || nativeDesktop.isRunning)
        }
        guard current() else { throw CancellationError() }
        guard free else { throw DesktopTransitionError.check("The previous Desktop action did not finish") }
        guard let snapshot = updateNativeCatalog(Screen.all()) else {
            throw DesktopTransitionError.check("macOS could not read the Desktops")
        }
        if let entry = desktops.nativeCatalog.entry(name) { return entry }
        guard !name.isEmpty, !isPending(name), isVirtual(name) else {
            throw DesktopTransitionError.check("This workspace name is unavailable")
        }
        desktops.nativeCreationBusy = true
        defer { desktops.nativeCreationBusy = false; scheduleRefresh(after: 0) }
        let number = Int(WorkspaceKey.number(name)) ?? 0
        var latest = snapshot
        repeat {
            let successor = desktops.nativeCatalog.successor(of: name, on: screen.uuid)
            let created = try await DesktopLifecycle.create(on: screen, snapshot: latest, before: successor)
            if !config.workspacesPerDisplay { desktops.nativeCatalog.bind(name, to: created.space, on: screen.uuid) }
            latest = created.snapshot
            updateNativeCatalog(Screen.all(), snapshot: latest)
        } while config.workspacesPerDisplay && desktops.nativeCatalog.entry(name) == nil
            && desktops.nativeCatalog.entries(on: screen.uuid).count < number
        guard let entry = desktops.nativeCatalog.entry(name) else {
            throw DesktopTransitionError.check("The Desktop disappeared")
        }
        return entry
    }

    func commitNativeRemovals() {
        let removed = desktops.nativeDroppedWorkspaces
        guard !removed.isEmpty else { return }
        Task { @MainActor in
            guard await poll(5, every: 50_000_000, until: {
                !self.nativeDesktop.isRunning && !self.desktops.nativeCreationBusy && self.workspaceMoves.isEmpty
            }) else { return }
            self.desktops.nativeCreationBusy = true
            defer { self.desktops.nativeCreationBusy = false; self.scheduleRefresh(after: 0) }
            let entries = removed.compactMap { self.desktops.nativeCatalog.entry($0) }
                .sorted { (Int(WorkspaceKey.number($0.name)) ?? 0) > (Int(WorkspaceKey.number($1.name)) ?? 0) }
            for entry in entries {
                guard let screen = Screen.all().first(where: { $0.uuid == entry.display }) else { continue }
                do {
                    try await self.removeDesktop(entry.space, on: screen)
                    if self.config.workspacesPerDisplay { self.closeGap(after: entry) }
                } catch {
                    HUD.shared.show(error.localizedDescription, on: screen.nsScreen)
                }
            }
            self.desktops.nativeDroppedWorkspaces.subtract(removed)
        }
    }
}

extension WindowManager {
    func adoptNativeZoom(_ window: Window) {
        scanner.run(window.pid) { [weak self] in
            let frame = window.element.frame
            DispatchQueue.main.async {
                guard let self, self.windows[window.id] === window, !window.isFloating,
                      !self.animator.isBusy(window.id), !frame.isNull,
                      NSEvent.pressedMouseButtons & 1 == 0,
                      let screen = self.screen(containing: frame),
                      self.shown[screen.uuid] == self.workspaceOf[window.id] else { return }
                let state = self.state(for: screen)
                let usable = self.usableRect(screen)
                let fills = frame.width >= usable.width * 0.95 && frame.height >= usable.height * 0.95
                if fills, state.zoomed != window.id {
                    state.zoomed = window.id
                } else if !fills, state.zoomed == window.id {
                    state.zoomed = nil
                }
                self.scheduleRefresh()
            }
        }
    }
}
