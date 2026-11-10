import AppKit
import QuartzCore

extension WindowManager {
    @discardableResult
    package func updateNativeCatalog(_ screens: [Screen],
                                     snapshot supplied: Spaces.Snapshot? = nil) -> Spaces.Snapshot? {
        guard let snapshot = supplied ?? Spaces.snapshot() else { return nil }
        let displays = screens.compactMap { screen in
            snapshot.list(display: screen.uuid).map { info in
                let uuids = info.desktops.compactMap { index in
                    info.uuids.indices.contains(index) ? info.uuids[index].map { (info.ids[index], $0) } : nil
                }
                return NativeWorkspaceCatalog.Display(
                    id: screen.uuid, spaces: info.desktops.map { info.ids[$0] },
                    current: info.current.map { info.ids[$0] },
                    uuids: Dictionary(uuids, uniquingKeysWith: { first, _ in first }))
            }
        }
        guard !displays.isEmpty, displays.count == screens.count else { return nil }
        desktops.nativeCatalog.perDisplay = config.workspacesPerDisplay
        let shared = SharedSpaces.isOn(displays: screens.count)
        if shared != desktops.nativeCatalog.sharedSpaces {
            desktops.nativeCatalog.sharedSpaces = shared
            if shared { Log.info("native workspaces: displays share one Space; each display tiles its own windows") }
        }
        let removed = desktops.nativeCatalog.synchronize(displays)
        for name in removed { forgetRemovedWorkspace(name) }
        for entry in desktops.nativeCatalog.entries { monitorOf[entry.name] = entry.display }
        if desktops.nativeCatalog.saved != desktops.lastNativeCatalogSaved
            || desktops.nativeCatalog.homes != desktops.lastNativeCatalogHomes
            || desktops.nativeCatalog.uuids != desktops.lastNativeCatalogUUIDs {
            desktops.lastNativeCatalogSaved = desktops.nativeCatalog.saved
            desktops.lastNativeCatalogHomes = desktops.nativeCatalog.homes
            desktops.lastNativeCatalogUUIDs = desktops.nativeCatalog.uuids
            Instance.defaults.set(desktops.nativeCatalog.saved, forKey: DefaultsKey.wsNativeSpaces)
            Instance.defaults.set(desktops.nativeCatalog.homes, forKey: DefaultsKey.wsNativeDisplays)
            Instance.defaults.set(desktops.nativeCatalog.uuids, forKey: DefaultsKey.wsNativeSpaceUUIDs)
        }
        return snapshot
    }

    package func renumberWorkspaces() {
        tilingRecovery.zoomed = [:]
        model.resetWorkspaces()
        desktops.nativeCatalog = NativeWorkspaceCatalog()
        labels = [:]; previousWorkspace = [:]; floats.savedOwnerOf = [:]
        desktops.nativeDroppedWorkspaces = []; desktops.nativeSortNames = []
        closeAndSort.sortSnapshot = nil; closeAndSort.closingNow = []; closeAndSort.closingApps = []
        surface.abandonOverview()
        Log.info("workspaces: \(config.workspacesPerDisplay ? "numbered on each display" : "numbered on all displays")")
    }

    package func syncNativeWorkspaces(screens: [Screen], present: Set<CGWindowID>) -> WorkspaceReconciliation {
        updateNativeCatalog(screens)
        Task { @MainActor [nativeDesktop] in nativeDesktop.prewarmGuard() }
        let displays = Set(screens.map(\.uuid))
        shown = shown.filter { displays.contains($0.key) }
        virtualShown = virtualShown.filter { displays.contains($0.key) }
        showCurrentWorkspaces(screens)
        func host(_ id: CGWindowID, on space: UInt64) -> String? {
            guard let screen = screens.first(where: {
                Spaces.list(display: $0.uuid)?.ids.contains(space) == true
            }) else { return nil }
            let key = Self.spaceWorkspace(display: screen.uuid, space: space)
            model.hostMaximised(id, in: key)
            monitorOf[key] = screen.uuid
            return key
        }
        var assignments: [CGWindowID: String] = [:]
        for (id, window) in windows
        where !nativeMoves.isBusy(id) && !closeAndSort.sortSession
            && !isPending(workspaceOf[id]) {
            let membership = nativeMoves.observedMembership(id, observed: scanner.desktop.spaces[id] ?? [])
            if let entry = desktops.nativeCatalog.entries.first(where: { membership.contains($0.space) }) {
                assignments[id] = entry.name
                displayOf[id] = sharesSpaces ? sharedDisplay(of: window, in: screens) ?? entry.display : entry.display
            } else if window.fullscreen, let space = membership.first {
                _ = host(id, on: space)
            }
        }
        model.assign(assignments)
        model.fullscreenHost = [:]
        for (id, space) in fullscreenSpaces() {
            if let key = host(id, on: space) { model.fullscreenHost[key] = id }
        }
        releaseEmptyWorkspaces()
        let visible = present.filter { model.isShown(workspaceOf[$0]) }
        return .init(model: model, homeSpace: [:], displayOf: displayOf, visible: visible, park: [])
    }

    package var sharesSpaces: Bool { config.virtualWorkspaces && desktops.nativeCatalog.sharedSpaces }

    private func showCurrentWorkspaces(_ screens: [Screen]) {
        let spaces = screens.map { backend.currentSpace(display: $0.uuid) }
        let current = zip(screens, spaces).map { screen, space in
            (display: screen.uuid, space: desktops.nativeCatalog.sharedSpaces ? spaces[0] : space)
        }
        let names = desktops.nativeCatalog.shown(current)
        for (display, space) in current {
            let name = names[display]
            model.show(name ?? Self.spaceWorkspace(display: display, space: space), on: display)
            guard let name else { continue }
            if let old = virtualShown[display], old != name,
               !closeAndSort.sortSession { previousWorkspace[display] = old }
            virtualShown[display] = name
        }
    }

    package func sharedDisplay(of window: Window, in screens: [Screen]) -> String? {
        let id = window.id
        return SharedSpaces.display(
            of: window.cachedFrame, kept: displayOf[id], target: targets[id],
            settling: drags[id] != nil || corrections[id] != nil || animator.isBusy(id),
            in: screens.map { (id: $0.uuid, frame: $0.frame) })
    }

    package func showNativeWorkspace(_ workspace: String, focusing preferred: Window?, focus takesFocus: Bool,
                                     quiet: Bool) {
        let requestedAt = CACurrentMediaTime()
        updateNativeCatalog(backend.screens())
        desktops.nativeWorkspaceGeneration += 1
        let generation = desktops.nativeWorkspaceGeneration
        let screen = currentScreen() ?? backend.screens().first
        guard !desktops.nativeCreationBusy, let entry = desktops.nativeCatalog.entry(workspace) else {
            guard let screen else { return }
            nativeDesktop.stop()
            Task { @MainActor in
                do {
                    let entry = try await self.ensureNativeWorkspace(workspace, on: screen, while: {
                        self.desktops.nativeWorkspaceGeneration == generation
                    })
                    if self.desktops.nativeWorkspaceGeneration == generation {
                        self.configureNativeController(focusing: preferred, focus: takesFocus, quiet: quiet)
                        self.nativeDesktop.request(.init(workspace: workspace, display: entry.display,
                                                         space: entry.space), since: requestedAt)
                    }
                } catch is CancellationError { } catch {
                    Log.info("native workspaces: create \(workspace) failed: \(error.localizedDescription)")
                    surface.showHUD(error.localizedDescription, on: screen.nsScreen)
                }
            }
            return
        }
        configureNativeController(focusing: preferred, focus: takesFocus, quiet: quiet)
        nativeDesktop.request(.init(workspace: workspace, display: entry.display, space: entry.space),
                              since: requestedAt)
    }

    private func releaseEmptyWorkspaces() {
        guard config.removesEmptyWorkspaces, !closeAndSort.sortSession, !restoringTemplate, !nativeDesktop.isRunning,
              nativeDesktop.requested == nil, !desktops.nativeCreationBusy, nativeMoves.isEmpty,
              !scanner.desktop.allWindows.isEmpty else { return }
        let held = Set(workspaceOf.filter { windows[$0.key] != nil }.values).union(virtualShown.values)
            .union(model.shownSet)
        let occupied = Set(scanner.desktop.allWindows.compactMap { window in
            scanner.desktop.spaces[window.id].flatMap { $0.count == 1 ? $0.first : nil }
        })
        let empty = desktops.nativeCatalog.entries.filter {
            !held.contains($0.name) && !occupied.contains($0.space)
                && backend.currentSpace(display: $0.display) != $0.space
        }
        if config.workspacesPerDisplay {
            func number(_ entry: NativeWorkspaceCatalog.Entry) -> Int { Int(WorkspaceKey.number(entry.name)) ?? 0 }
            let kept = desktops.nativeCatalog.entries.filter { entry in !empty.contains(entry) }
            return removeDesktops(empty.filter { entry in
                !kept.contains { $0.display == entry.display && number($0) > number(entry) }
            })
        }
        removeDesktops(empty)
    }

    private func removeDesktops(_ empty: [NativeWorkspaceCatalog.Entry]) {
        let now = Date()
        let targets = empty.filter {
            desktops.desktopRemovalFailures[$0.space].map { now.timeIntervalSince($0) > 30 } ?? true
        }
            .sorted { (Int(WorkspaceKey.number($0.name)) ?? 0) > (Int(WorkspaceKey.number($1.name)) ?? 0) }
        guard !targets.isEmpty, !desktops.desktopRemovalScheduled else { return }
        desktops.desktopRemovalScheduled = true
        Task { @MainActor in
            defer { self.desktops.desktopRemovalScheduled = false }
            guard await poll(5, every: 50_000_000, until: {
                !self.nativeDesktop.isRunning && self.nativeDesktop.requested == nil && self.nativeMoves.isEmpty
                    && !self.desktops.nativeCreationBusy
            }) else { return }
            desktops.nativeCreationBusy = true
            defer { self.desktops.nativeCreationBusy = false; self.scheduleRefresh(after: 0) }
            for entry in targets {
                guard let screen = backend.screens().first(where: { $0.uuid == entry.display }),
                      backend.currentSpace(display: entry.display) != entry.space else { continue }
                do {
                    try await self.removeDesktop(entry.space, on: screen)
                    if self.config.workspacesPerDisplay {
                        self.closeGap(after: entry)
                    } else {
                        self.forgetRemovedWorkspace(entry.name)
                    }
                    self.desktops.desktopRemovalFailures[entry.space] = nil
                    Log.info("native workspaces: removed empty workspace \(entry.name)")
                } catch {
                    self.desktops.desktopRemovalFailures[entry.space] = Date()
                    Log.info("native workspaces: could not remove \(entry.name): \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor package func removeDesktop(
        _ space: UInt64, on screen: Screen,
        remove: (UInt64, Screen) async throws -> Void = DesktopLifecycle.remove
    ) async throws {
        for attempt in 1... {
            _ = await poll(1, every: 10_000_000) { DesktopUI.isSettled(screen) }
            do { return try await remove(space, screen) } catch DesktopTransitionError.occupied {
                throw DesktopTransitionError.occupied
            } catch where attempt < 5 {
                try await Task.sleep(nanoseconds: 200_000_000) // style-ok: a failed remove has no retry event
            }
        }
    }

    package func forgetRemovedWorkspace(_ name: String) {
        states[name] = nil
        lastFocused[name] = nil
        labels[name] = nil
    }

    package func closeGap(after removed: NativeWorkspaceCatalog.Entry) {
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
        tilingRecovery.zoomed = moved(tilingRecovery.zoomed)
        labels = moved(labels)
        lastFocused = moved(lastFocused)
        previousWorkspace = moved(previousWorkspace).mapValues(shifted)
    }

    package func showMaximised(_ window: Window) -> Bool {
        guard config.virtualWorkspaces, window.fullscreen, let space = Spaces.of(window: window.id).first,
              let screen = backend.screens().first(where: {
                  Spaces.list(display: $0.uuid)?.ids.contains(space) == true
              }),
              backend.currentSpace(display: screen.uuid) != space else { return false }
        desktops.nativeWorkspaceGeneration += 1
        configureNativeController(focusing: window, focus: true, quiet: true)
        nativeDesktop.request(.init(workspace: Self.spaceWorkspace(display: screen.uuid, space: space),
                                    display: screen.uuid, space: space))
        return true
    }

    package func configureNativeController(focusing preferred: Window?, focus takesFocus: Bool, quiet: Bool) {
        nativeDesktop.prepare = { [weak self] in try await self?.prepareNativeLayout($0) }
        nativeDesktop.settings = MotionSpec(config)
        nativeDesktop.onSettled = { [weak self] request, changed in
            guard let self else { return }
            if self.isVirtual(request.workspace) {
                if changed, let old = self.virtualShown[request.display], old != request.workspace,
                   !self.closeAndSort.sortSession {
                    self.previousWorkspace[request.display] = old
                }
                self.virtualShown[request.display] = request.workspace
            }
            self.placeArrivals(on: request.display)
            self.scheduleRefresh(after: 0)
            DispatchQueue.main.async {
                guard self.nativeDesktop.requested == nil,
                      self.backend.currentSpace(display: request.display) == request.space else { return }
                self.refresh(placing: [])
                guard let screen = self.backend.screens().first(where: { $0.uuid == request.display }) else { return }
                if takesFocus { self.focusShownWorkspace(request.workspace, preferred: preferred, on: screen) }
                if changed, !quiet, self.config.enablesLayoutHUD, self.config.enablesLayoutHUDOnSpaceChange {
                    self.showWorkspaceHUD(request.workspace, on: screen)
                }
            }
        }
        nativeDesktop.onMotion = { [weak self] request in self?.placeArrivals(on: request.display) }
        nativeDesktop.isForward = { [weak self] source, target, desktopOrder in
            guard let self, let from = self.desktops.nativeCatalog.entry(space: source)?.name,
                  let into = self.desktops.nativeCatalog.entry(space: target)?.name else { return desktopOrder }
            return self.workspaceSort(from, into)
        }
        nativeDesktop.onIdle = { [weak self] in
            self?.nativeMoves.desktopBecameIdle()
            self?.scheduleRefresh(after: 0)
        }
        nativeDesktop.onFailure = { [weak self] message in
            Log.info("native workspaces: \(message)")
            self?.surface.showHUD(message, on: self?.currentScreen()?.nsScreen)
            self?.scheduleRefresh(after: 0)
        }
    }

    @MainActor package func prepareNativeLayout(
        _ request: NativeDesktopController.Request,
        readFrames: (Set<CGWindowID>) -> [CGWindowID: CGRect]? = { WindowServerQuery.frames(for: $0) }
    ) async throws {
        let arriving = nativeMoves.following(to: request.workspace)
        let shownApps = Set(observedApps.map(\.pid))
        let eligible = order.filter {
            (workspaceOf[$0] == request.workspace || arriving[$0] != nil)
                && windows[$0].map { shownApps.contains($0.pid) && !$0.isFloating } == true
                && windows[$0]?.minimized == false && windows[$0]?.fullscreen == false
        }
        let eligibleIDs = Set(eligible)
        let ids = eligible.filter { id in
            guard let group = tabs.group(of: id) else { return true }
            let active = eligibleIDs.contains(group.active) ? group.active
                : group.members.first(where: eligibleIDs.contains)
            return active == id
        }
        var slots: [CGWindowID: CGRect] = [:]
        for (screen, group) in layoutGroups(ids, on: request.display) where tilingEnabled {
            guard let placed = layoutTargets(group, state(workspace: request.workspace), on: screen) else { continue }
            let expanded = group.flatMap { id -> [(CGWindowID, CGRect)] in
                guard let slot = placed[id] else { return [] }
                let frame = belowTabStrip(slot, for: id)
                let peers = tabs.group(of: id)?.members.filter { $0 != id && eligibleIDs.contains($0) } ?? []
                return ([id] + peers).map { ($0, frame) }
            }
            let frames = Dictionary(uniqueKeysWithValues: expanded)
            slots.merge(frames) { first, _ in first }
            try await place(expanded.map(\.0).filter { arriving[$0] == nil }, in: frames, on: screen,
                            readFrames: readFrames)
        }
        for move in arriving.values {
            try await completeFollowMove(move)
            if let slot = slots[move.window.id] { nativeMoves.arrived(move.window.id, frame: slot) }
        }
    }

    package func layoutGroups(_ ids: [CGWindowID], on display: String) -> [(screen: Screen, ids: [CGWindowID])] {
        let screens = backend.screens()
        guard sharesSpaces else { return screens.filter { $0.uuid == display }.map { ($0, ids) } }
        return screens.map { screen in (screen, ids.filter { (displayOf[$0] ?? display) == screen.uuid }) }
    }

    package func placeArrivals(on display: String) {
        let screen = backend.screens().first { $0.uuid == display }
        let moves = nativeMoves.takeArrivals().compactMap { id, frame -> Animator.Move? in
            guard let window = windows[id], let screen else { return nil }
            targets[id] = frame
            return .init(window: window, to: frame, bounds: screen.visible)
        }
        animator.animate(moves, duration: config.animate ? config.animationDuration : 0,
                         curve: config.animationCurve, bounce: config.animationBounce)
    }

    @MainActor private func place(_ ids: [CGWindowID], in slots: [CGWindowID: CGRect], on screen: Screen,
                                  readFrames: (Set<CGWindowID>) -> [CGWindowID: CGRect]?) async throws {
        guard !ids.isEmpty else { return }
        let moves = ids.compactMap { id -> Animator.Move? in
            guard let window = windows[id], let frame = slots[id] else { return nil }
            animator.cancel(id)
            targets[id] = frame
            return .init(window: window, to: frame, bounds: screen.visible)
        }
        let pids = Set(moves.map(\.window.pid))
        guard await animator.waitForPendingWrites(pids: pids) else {
            throw DesktopTransitionError.check("Windows are still preparing for the Desktop switch")
        }
        let actual = readFrames(Set(moves.map(\.window.id))) ?? [:]
        let changed = moves.filter {
            !$0.window.cachedFrame.approxEqual($0.target, tolerance: 1)
                || actual[$0.window.id]?.approxEqual($0.target, tolerance: 1) != true
        }
        guard !changed.isEmpty else { return }
        animator.animate(changed, duration: 0)
        guard await animator.waitForPendingWrites(pids: Set(changed.map(\.window.pid))) else {
            throw DesktopTransitionError.check("Windows are still preparing for the Desktop switch")
        }
    }
}
