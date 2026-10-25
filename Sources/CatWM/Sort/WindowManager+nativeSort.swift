import AppKit

extension WindowManager {
    func toggleSortCommand() {
        if config.virtualWorkspaces {
            SortPanel.shared.toggle()
        } else {
            HUD.shared.show("Overview needs CatWM workspaces", on: currentScreen()?.nsScreen)
        }
    }

    func finishSort(closing ids: [CGWindowID], goTo: String?, focus: Bool, opening fullscreen: CGWindowID? = nil,
                    leavingFullscreen moves: [CGWindowID: String] = [:]) {
        Task { @MainActor in
            await self.commitNativeSort()
            for (id, workspace) in moves { await self.leaveFullscreen(id, to: workspace) }
            self.finishSortAfterNative(closing: ids, goTo: goTo, focus: focus, opening: fullscreen)
        }
    }

    @MainActor private func commitNativeSort() async {
        for name in desktops.nativeSortNames.sorted(by: workspaceSort) {
            guard let display = monitorOf[name], let screen = Screen.all().first(where: { $0.uuid == display }) else {
                continue
            }
            do { _ = try await ensureNativeWorkspace(name, on: screen) } catch {
                HUD.shared.show(error.localizedDescription, on: screen.nsScreen)
            }
        }
        let assignments = workspaceOf
        for (id, name) in assignments {
            guard let target = desktops.nativeCatalog.entry(name), let window = windows[id], !window.fullscreen,
                  Spaces.of(window: id) != [target.space] else { continue }
            workspaceMoves.insert(id)
            animator.cancel(id)
            let moved = await withCheckedContinuation { continuation in
                Spaces.move(window: id, to: target.space) { continuation.resume(returning: $0) }
            }
            workspaceMoves.remove(id)
            if moved { desktops.nativeMembership[id] = target.space } else {
                HUD.shared.show("macOS couldn't move a window to workspace \(name)", on: currentScreen()?.nsScreen)
            }
        }
        desktops.nativeSortNames = []
    }

    @MainActor func leaveFullscreen(_ id: CGWindowID, to workspace: String) async {
        guard let window = windows[id], let screen = Screen.all().first(where: {
            $0.uuid == monitorOf[workspace]
        }), window.unlessStalled(false, { window.element.set("AXFullScreen", kCFBooleanFalse) }) else {
            Log.info("sort: \(id) refused to leave full screen")
            return
        }
        workspaceMoves.insert(id)
        defer { workspaceMoves.remove(id); scheduleRefresh(after: 0) }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func leaving() -> Bool { window.fullscreenUnlessStalled || !DesktopUI.isSettled(screen) }
        guard await poll(5, every: 50_000_000, until: { !leaving() || !window.isValidUnlessStalled }), !leaving() else {
            HUD.shared.show("macOS did not finish leaving full screen", on: screen.nsScreen)
            return
        }
        do {
            let target = try await ensureNativeWorkspace(workspace, on: screen)
            var moved = false
            repeat {
                moved = await withCheckedContinuation { continuation in
                    Spaces.move(window: id, to: target.space) { continuation.resume(returning: $0) }
                }
                if !moved { try await Task.sleep(nanoseconds: 100_000_000) }
            } while !moved && window.isValidUnlessStalled && ProcessInfo.processInfo.systemUptime < deadline
            guard moved else { throw DesktopTransitionError.check("macOS couldn't move this window") }
            desktops.nativeMembership[id] = target.space
            model.assign(id, to: workspace)
            model.fullscreenHost = model.fullscreenHost.filter { $0.value != id }
            leavingFullscreen[id] = Date()
        } catch {
            Log.info("sort: leave full screen failed: \(error.localizedDescription)")
            HUD.shared.show(error.localizedDescription, on: screen.nsScreen)
        }
    }
}
