import AppKit

extension WindowManager {
    func updateNativeCatalog(_ screens: [Screen]) {
        let displays = screens.compactMap { screen in
            Spaces.list(display: screen.uuid).map { info in
                NativeWorkspaceCatalog.Display(id: screen.uuid, spaces: info.desktops.map { info.ids[$0] })
            }
        }
        guard !displays.isEmpty, displays.count == screens.count else { return }
        nativeCatalog.synchronize(displays)
        for entry in nativeCatalog.entries { monitorOf[entry.name] = entry.display }
        if nativeCatalog.saved != lastNativeCatalogSaved {
            lastNativeCatalogSaved = nativeCatalog.saved
            UserDefaults.standard.set(nativeCatalog.saved, forKey: "ws.nativeSpaces")
        }
    }

    func syncNativeWorkspaces(screens: [Screen], present: Set<CGWindowID>) -> WorkspaceReconciliation {
        updateNativeCatalog(screens)
        MainActor.assumeIsolated { DesktopGuardClient.prewarm() }
        let displays = Set(screens.map(\.uuid))
        shown = shown.filter { displays.contains($0.key) }
        for screen in screens {
            let space = Spaces.current(display: screen.uuid)
            let name = nativeCatalog.entry(space: space)?.name
            model.show(name ?? Self.spaceWorkspace(display: screen.uuid, space: space), on: screen.uuid)
            guard let name else { continue }
            if let old = virtualShown[screen.uuid], old != name, !sortSession { previousWorkspace[screen.uuid] = old }
            virtualShown[screen.uuid] = name
        }
        func host(_ id: CGWindowID, on space: UInt64) -> String? {
            guard let screen = screens.first(where: {
                Spaces.list(display: $0.uuid)?.ids.contains(space) == true
            }) else { return nil }
            let key = Self.spaceWorkspace(display: screen.uuid, space: space)
            model.assign(id, to: key)
            monitorOf[key] = screen.uuid
            return key
        }
        for (id, window) in windows
        where !workspaceMoves.contains(id) && nativeMoveTargets[id] == nil && !sortSession
            && !isPending(workspaceOf[id]) {
            let membership = nativeMembership[id].map { Set([$0]) } ?? scanner.desktop.spaces[id] ?? []
            if let override = nativeMembership[id], scanner.desktop.spaces[id] == [override] {
                nativeMembership[id] = nil
            }
            if let entry = nativeCatalog.entries.first(where: { membership.contains($0.space) }) {
                model.assign(id, to: entry.name)
                displayOf[id] = entry.display
            } else if window.fullscreen, let space = membership.first {
                _ = host(id, on: space)
            }
        }
        model.fullscreenHost = [:]
        for (id, space) in fullscreenSpaces() {
            if let key = host(id, on: space) { model.fullscreenHost[key] = id }
        }
        let visible = present.filter { model.isShown(workspaceOf[$0]) }
        return .init(model: model, homeSpace: [:], displayOf: displayOf, visible: visible, park: [])
    }

    func showNativeWorkspace(_ workspace: String, focusing preferred: Window?, focus takesFocus: Bool, quiet: Bool) {
        updateNativeCatalog(Screen.all())
        nativeWorkspaceGeneration += 1
        let generation = nativeWorkspaceGeneration
        guard let entry = nativeCatalog.entry(workspace) else {
            guard let screen = currentScreen() ?? Screen.all().first else { return }
            nativeDesktop.stop()
            Task { @MainActor in
                do {
                    _ = try await self.ensureNativeWorkspace(workspace, on: screen, while: {
                        self.nativeWorkspaceGeneration == generation
                    })
                    if self.nativeWorkspaceGeneration == generation {
                        self.showNativeWorkspace(workspace, focusing: preferred, focus: takesFocus, quiet: quiet)
                    }
                } catch is CancellationError { } catch {
                    Log.info("native workspaces: create \(workspace) failed: \(error.localizedDescription)")
                    HUD.shared.show(error.localizedDescription, on: screen.nsScreen)
                }
            }
            return
        }
        configureNativeController(focusing: preferred, focus: takesFocus, quiet: quiet)
        nativeDesktop.request(.init(workspace: workspace, display: entry.display, space: entry.space))
    }

    func configureNativeController(focusing preferred: Window?, focus takesFocus: Bool, quiet: Bool) {
        nativeDesktop.prepare = { [weak self] in try await self?.prepareNativeLayout($0) }
        nativeDesktop.settings = .init(duration: config.animate ? config.animationDuration : 0,
                                       curve: config.animationCurve, bounce: config.animationBounce)
        nativeDesktop.onSettled = { [weak self] request, changed in
            guard let self else { return }
            self.scheduleRefresh(after: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard Spaces.current(display: request.display) == request.space else { return }
                self.refresh()
                if takesFocus {
                    let candidates = [preferred?.id, self.lastFocused[request.workspace]].compactMap(\.self)
                        + self.order
                    if let id = candidates.first(where: {
                        self.workspaceOf[$0] == request.workspace && self.windows[$0]?.minimized == false
                    }), let window = self.windows[id] {
                        self.focus(window, warp: false)
                    } else { self.parkFocus() }
                }
                if changed, !quiet, self.config.enablesLayoutHUD, self.config.enablesLayoutHUDOnSpaceChange,
                   let screen = Screen.all().first(where: { $0.uuid == request.display }) {
                    self.showWorkspaceHUD(request.workspace, on: screen)
                }
            }
        }
        nativeDesktop.onIdle = { [weak self] in self?.scheduleRefresh(after: 0) }
        nativeDesktop.onFailure = { [weak self] message in
            Log.info("native workspaces: \(message)")
            HUD.shared.show(message, on: self?.currentScreen()?.nsScreen)
            self?.scheduleRefresh(after: 0)
        }
    }

    func handleNativeSwipe(_ sample: DesktopGestureTap.Sample) {
        if sample.phase == 1 { nativeGestureSign = nil }
        if nativeGestureSign == nil, abs(sample.progress) > 0.001, !nativeDesktop.isRunning {
            guard let screen = Screen.all().first(where: { $0.frame.contains(mouseLocation()) }) else { return }
            updateNativeCatalog(Screen.all())
            guard let source = nativeCatalog.entry(space: Spaces.current(display: screen.uuid)) else { return }
            let direction = sample.progress > 0 ? 1 : -1
            guard let name = nativeCatalog.step(from: source.name, by: direction),
                  let target = nativeCatalog.entry(name) else { return }
            nativeGestureSign = Double(direction)
            configureNativeController(focusing: nil, focus: true, quiet: false)
            nativeDesktop.beginGesture(.init(workspace: name, display: target.display, space: target.space))
        }
        guard let sign = nativeGestureSign else { return }
        let progress = min(1, max(0, sample.progress * sign))
        nativeDesktop.scrub(progress)
        if sample.phase == 4 || sample.phase == 8 {
            nativeDesktop.endGesture(commit: sample.phase != 8 && (progress >= 0.5 || sample.velocity * sign > 0.5))
            nativeGestureSign = nil
        }
    }

    @MainActor func prepareNativeLayout(_ request: NativeDesktopController.Request) async throws {
        guard tilingEnabled, let screen = Screen.all().first(where: { $0.uuid == request.display }) else { return }
        let ids = order.filter {
            workspaceOf[$0] == request.workspace && windows[$0]?.isFloating == false
                && windows[$0]?.minimized == false && windows[$0]?.fullscreen == false
        }
        guard let slots = layoutTargets(ids, state(workspace: request.workspace), on: screen) else { return }
        let moves = ids.compactMap { id -> Animator.Move? in
            guard let window = windows[id], let frame = slots[id] else { return nil }
            animator.cancel(id)
            targets[id] = frame
            return .init(window: window, to: frame, bounds: screen.visible)
        }
        animator.animate(moves, duration: 0)
        var finished = false
        animator.afterPendingWrites { finished = true }
        guard await poll(1, until: { finished }) else {
            throw DesktopTransitionError.check("Windows are still preparing for the Desktop switch")
        }
    }
}
