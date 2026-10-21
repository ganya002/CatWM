import AppKit

extension WindowManager {
    @discardableResult
    func updateNativeCatalog(_ screens: [Screen], snapshot supplied: Spaces.Snapshot? = nil) -> Spaces.Snapshot? {
        guard let snapshot = supplied ?? Spaces.snapshot() else { return nil }
        let displays = screens.compactMap { screen in
            snapshot.list(display: screen.uuid).map { info in
                NativeWorkspaceCatalog.Display(id: screen.uuid, spaces: info.desktops.map { info.ids[$0] },
                                               current: info.current.map { info.ids[$0] })
            }
        }
        guard !displays.isEmpty, displays.count == screens.count else { return nil }
        nativeCatalog.perDisplay = config.workspacesPerDisplay
        nativeCatalog.synchronize(displays)
        for entry in nativeCatalog.entries { monitorOf[entry.name] = entry.display }
        if nativeCatalog.saved != lastNativeCatalogSaved || nativeCatalog.homes != lastNativeCatalogHomes {
            lastNativeCatalogSaved = nativeCatalog.saved
            lastNativeCatalogHomes = nativeCatalog.homes
            UserDefaults.standard.set(nativeCatalog.saved, forKey: "ws.nativeSpaces")
            UserDefaults.standard.set(nativeCatalog.homes, forKey: "ws.nativeDisplays")
        }
        return snapshot
    }

    func renumberWorkspaces() {
        model.resetWorkspaces()
        nativeCatalog = NativeWorkspaceCatalog()
        labels = [:]; previousWorkspace = [:]; savedWorkspaceOf = [:]; savedOwnerOf = [:]
        nativeDroppedWorkspaces = []; nativeSortNames = []
        sortSnapshot = nil; closingNow = []; closingApps = []
        SortPanel.shared.abandon()
        Log.info("workspaces: \(config.workspacesPerDisplay ? "numbered on each display" : "numbered on all displays")")
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
        releaseEmptyWorkspaces()
        let visible = present.filter { model.isShown(workspaceOf[$0]) }
        return .init(model: model, homeSpace: [:], displayOf: displayOf, visible: visible, park: [])
    }

    func showNativeWorkspace(_ workspace: String, focusing preferred: Window?, focus takesFocus: Bool, quiet: Bool) {
        updateNativeCatalog(Screen.all())
        nativeWorkspaceGeneration += 1
        let generation = nativeWorkspaceGeneration
        let screen = currentScreen() ?? Screen.all().first
        guard !nativeCreationBusy, let entry = nativeCatalog.entry(workspace) else {
            guard let screen else { return }
            nativeDesktop.stop()
            Task { @MainActor in
                do {
                    let entry = try await self.ensureNativeWorkspace(workspace, on: screen, while: {
                        self.nativeWorkspaceGeneration == generation
                    })
                    if self.nativeWorkspaceGeneration == generation {
                        self.configureNativeController(focusing: preferred, focus: takesFocus, quiet: quiet)
                        self.nativeDesktop.request(.init(workspace: workspace, display: entry.display,
                                                         space: entry.space))
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

    private func releaseEmptyWorkspaces() {
        guard config.removesEmptyWorkspaces, !sortSession, !restoringTemplate, !nativeDesktop.isRunning,
              nativeDesktop.requested == nil, !nativeCreationBusy, workspaceMoves.isEmpty, nativeMoveTargets.isEmpty,
              !scanner.desktop.allWindows.isEmpty else { return }
        let held = Set(workspaceOf.filter { windows[$0.key] != nil }.values).union(virtualShown.values)
            .union(model.shownSet)
        let occupied = Set(scanner.desktop.allWindows.compactMap { window in
            scanner.desktop.spaces[window.id].flatMap { $0.count == 1 ? $0.first : nil }
        })
        let empty = nativeCatalog.entries.filter {
            !held.contains($0.name) && !occupied.contains($0.space) && Spaces.current(display: $0.display) != $0.space
        }
        if config.workspacesPerDisplay {
            func number(_ entry: NativeWorkspaceCatalog.Entry) -> Int { Int(WorkspaceKey.number(entry.name)) ?? 0 }
            let kept = nativeCatalog.entries.filter { entry in !empty.contains(entry) }
            return removeDesktops(empty.filter { entry in
                !kept.contains { $0.display == entry.display && number($0) > number(entry) }
            })
        }
        removeDesktops(empty)
    }

    private func removeDesktops(_ empty: [NativeWorkspaceCatalog.Entry]) {
        let now = Date()
        let targets = empty.filter { desktopRemovalFailures[$0.space].map { now.timeIntervalSince($0) > 30 } ?? true }
            .sorted { (Int(WorkspaceKey.number($0.name)) ?? 0) > (Int(WorkspaceKey.number($1.name)) ?? 0) }
        guard !targets.isEmpty, !desktopRemovalScheduled else { return }
        desktopRemovalScheduled = true
        Task { @MainActor in
            defer { self.desktopRemovalScheduled = false }
            guard await poll(5, every: 50_000_000, until: {
                !self.nativeDesktop.isRunning && self.nativeDesktop.requested == nil && self.workspaceMoves.isEmpty
                    && self.nativeMoveTargets.isEmpty && !self.nativeCreationBusy
            }) else { return }
            nativeCreationBusy = true
            defer { self.nativeCreationBusy = false; self.scheduleRefresh(after: 0) }
            for entry in targets {
                guard let screen = Screen.all().first(where: { $0.uuid == entry.display }),
                      Spaces.current(display: entry.display) != entry.space else { continue }
                do {
                    try await self.removeDesktop(entry.space, on: screen)
                    if self.config.workspacesPerDisplay {
                        self.closeGap(after: entry)
                    } else {
                        self.states[entry.name] = nil
                        self.lastFocused[entry.name] = nil
                    }
                    self.desktopRemovalFailures[entry.space] = nil
                    Log.info("native workspaces: removed empty workspace \(entry.name)")
                } catch {
                    self.desktopRemovalFailures[entry.space] = Date()
                    Log.info("native workspaces: could not remove \(entry.name): \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor func removeDesktop(_ space: UInt64, on screen: Screen) async throws {
        for attempt in 1... {
            _ = await poll(1, every: 10_000_000) { DesktopUI.isSettled(screen) }
            do { return try await DesktopLifecycle.remove(space, on: screen) } catch where attempt < 5 {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func closeGap(after removed: NativeWorkspaceCatalog.Entry) {
        guard let gone = Int(WorkspaceKey.number(removed.name)) else { return }
        func shifted(_ key: String) -> String {
            guard WorkspaceKey.display(key) == removed.display, let number = Int(WorkspaceKey.number(key)),
                  number > gone else { return key }
            return WorkspaceKey.make(String(number - 1), on: removed.display, perDisplay: true)
        }
        func moved<Value>(_ dictionary: [String: Value]) -> [String: Value] {
            Dictionary(dictionary.filter { $0.key != removed.name }.map { (shifted($0.key), $0.value) },
                       uniquingKeysWith: { first, _ in first })
        }
        states = moved(states)
        labels = moved(labels)
        lastFocused = moved(lastFocused)
        previousWorkspace = moved(previousWorkspace).mapValues(shifted)
    }

    func showMaximised(_ window: Window) -> Bool {
        guard config.virtualWorkspaces, window.fullscreen, let space = Spaces.of(window: window.id).first,
              let screen = Screen.all().first(where: { Spaces.list(display: $0.uuid)?.ids.contains(space) == true }),
              Spaces.current(display: screen.uuid) != space else { return false }
        nativeWorkspaceGeneration += 1
        configureNativeController(focusing: window, focus: true, quiet: true)
        nativeDesktop.request(.init(workspace: Self.spaceWorkspace(display: screen.uuid, space: space),
                                    display: screen.uuid, space: space))
        return true
    }

    func configureNativeController(focusing preferred: Window?, focus takesFocus: Bool, quiet: Bool) {
        nativeDesktop.prepare = { [weak self] in try await self?.prepareNativeLayout($0) }
        nativeDesktop.settings = .init(duration: config.animate ? config.animationDuration : 0,
                                       curve: config.animationCurve, bounce: config.animationBounce)
        nativeDesktop.onSettled = { [weak self] request, changed in
            guard let self else { return }
            if self.isVirtual(request.workspace) {
                if changed, let old = self.virtualShown[request.display], old != request.workspace,
                   !self.sortSession {
                    self.previousWorkspace[request.display] = old
                }
                self.virtualShown[request.display] = request.workspace
            }
            self.placeArrivals(on: request.display)
            self.scheduleRefresh(after: 0)
            DispatchQueue.main.async {
                guard self.nativeDesktop.requested == nil,
                      Spaces.current(display: request.display) == request.space else { return }
                self.refresh(placing: [])
                guard let screen = Screen.all().first(where: { $0.uuid == request.display }) else { return }
                if takesFocus { self.focusShownWorkspace(request.workspace, preferred: preferred, on: screen) }
                if changed, !quiet, self.config.enablesLayoutHUD, self.config.enablesLayoutHUDOnSpaceChange {
                    self.showWorkspaceHUD(request.workspace, on: screen)
                }
            }
        }
        nativeDesktop.onMotion = { [weak self] request in self?.placeArrivals(on: request.display) }
        nativeDesktop.isForward = { [weak self] source, target, desktopOrder in
            guard let self, let from = self.nativeCatalog.entry(space: source)?.name,
                  let into = self.nativeCatalog.entry(space: target)?.name else { return desktopOrder }
            return self.workspaceSort(from, into)
        }
        nativeDesktop.onIdle = { [weak self] in
            self?.dropFollowMoves()
            self?.scheduleRefresh(after: 0)
        }
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
        let arriving = followMoves.filter { $0.value.workspace == request.workspace }
        let screen = Screen.all().first(where: { $0.uuid == request.display })
        let ids = order.filter {
            (workspaceOf[$0] == request.workspace || arriving[$0] != nil) && windows[$0]?.isFloating == false
                && windows[$0]?.minimized == false && windows[$0]?.fullscreen == false
        }
        let slots = tilingEnabled ? screen.flatMap { layoutTargets(ids, state(workspace: request.workspace), on: $0) }
            : nil
        if let screen, let slots { try await place(ids.filter { arriving[$0] == nil }, in: slots, on: screen) }
        for move in arriving.values {
            try await completeFollowMove(move)
            if let slot = slots?[move.window.id] { arrivals[move.window.id] = slot }
        }
    }

    func placeArrivals(on display: String) {
        let screen = Screen.all().first { $0.uuid == display }
        let moves = arrivals.compactMap { id, frame -> Animator.Move? in
            guard let window = windows[id], let screen else { return nil }
            targets[id] = frame
            return .init(window: window, to: frame, bounds: screen.visible)
        }
        arrivals = [:]
        animator.animate(moves, duration: config.animate ? config.animationDuration : 0,
                         curve: config.animationCurve, bounce: config.animationBounce)
    }

    @MainActor private func place(_ ids: [CGWindowID], in slots: [CGWindowID: CGRect], on screen: Screen) async throws {
        guard !ids.isEmpty else { return }
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
