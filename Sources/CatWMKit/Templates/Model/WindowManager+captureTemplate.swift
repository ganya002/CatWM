import AppKit

extension WindowManager {
    package enum TemplateError: LocalizedError, Equatable {
        case notReady, empty, incomplete, busy, scoped, off
        package var errorDescription: String? {
            switch self {
            case .notReady: "Grant Accessibility access before you save or open a template."
            case .empty: "Open a window in this workspace before you save a template."
            case .incomplete: "CatWM could not read every window in time, so this template was not saved."
            case .busy: "CatWM is still reading another workspace, so this template was not saved."
            case .scoped: "This CatWM manages only some apps (CATWM_SCOPE), so it cannot open a template."
            case .off: "Templates are off in the config (`features.services.templates`)."
            }
        }
    }

    @MainActor
    package func captureTemplate() async throws -> WorkspaceTemplate {
        try Task.checkCancellation()
        guard config.features.contains(.templates) else { throw TemplateError.off }
        let request = try makeRequest()
        let stop = StopFlag()
        let outcome = await withTaskCancellationHandler {
            await TemplateWindowCapture.slot.run(within: TemplateWindowCapture.backstop) {
                let apps = request.apps
                let pid = request.frontmostPID
                let budget = TemplateWindowCapture.budget
                return await Task.detached(priority: .userInitiated) {
                    WindowCapture.collect(apps: apps, frontmostPID: pid, budget: budget, stop: { stop.isStopped })
                }.value
            }
        } onCancel: {
            stop.stop()
        }
        try Task.checkCancellation()
        switch outcome {
        case .cancelled:
            throw CancellationError()
        case .timedOut:
            throw TemplateError.incomplete
        case .busy:
            throw TemplateError.busy
        case .finished(let batch):
            guard batch.complete else { throw TemplateError.incomplete }
            let template = try finish(batch, facts: request.facts)
            guard config.templateAppScripting else { return template }
            return try await withAppStates(template)
        }
    }

    @MainActor
    private func withAppStates(_ template: WorkspaceTemplate) async throws -> WorkspaceTemplate {
        let windows = template.windows.filter { !$0.minimized && !$0.fullscreen }.map {
            AppStateCapture.Window(id: $0.windowID, bundleID: $0.bundleID, title: $0.title, frame: $0.frame,
                                   document: $0.document)
        }
        let onScreen = Set(CGWindowInfo.onScreen().map(\.id))
        let tabs = WindowTabs.background(windows.filter { AppAdapters.adapter(for: $0.bundleID) != nil },
                                         onScreen: onScreen)
        let started = Date()
        let states = await AppStateCapture.capture(windows.filter { tabs[$0.id] == nil }, consentWait: 30,
                                                   scriptTimeout: 3)
        try Task.checkCancellation()
        var copy = template
        copy.windows.removeAll { window in tabs[window.windowID].map { states[$0] != nil } ?? false }
        for index in copy.windows.indices {
            copy.windows[index].state = states[copy.windows[index].windowID]
        }
        Log.info("template: app state for \(states.count) of \(windows.count) windows "
            + "in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        return copy
    }

    private func makeRequest() throws -> TemplateCaptureRequest {
        guard isStarted else { throw TemplateError.notReady }
        let screens = backend.screens()
        guard !screens.isEmpty else { throw TemplateError.notReady }
        let mainID = NSScreen.screens.first?.displayID
        var displays: [WorkspaceTemplate.Display] = []
        var zoomed: [String: CGWindowID] = [:]
        for screen in screens {
            let state = state(for: screen)
            displays.append(.init(id: screen.uuid, name: screen.name, frame: screen.frame,
                                  visible: screen.visible, isMain: screen.id == mainID, layout: state.layout.rawValue,
                                  ratio: state.ratio, mainCount: state.mainCount))
            if let id = state.zoomed { zoomed[screen.uuid] = id }
        }
        var knownFloating: [CGWindowID: Bool] = [:]
        var naturalFrames: [CGWindowID: CGRect] = [:]
        for (id, window) in windows {
            knownFloating[id] = window.isFloating
            if !window.naturalFrame.isNull { naturalFrames[id] = window.naturalFrame }
        }
        let displayIDs = Set(displays.map(\.id))
        var hidden: Set<CGWindowID> = []
        var monitors: [CGWindowID: String] = [:]
        for (id, workspace) in workspaceOf {
            if !isShown(workspace) { hidden.insert(id) }
            if let monitor = monitorOf[workspace], displayIDs.contains(monitor) { monitors[id] = monitor }
        }
        let facts = TemplateCaptureFacts(tilingEnabled: tilingEnabled, displays: displays, zoomed: zoomed, order: order,
                                         currentSpaces: Set(screens.map { backend.currentSpace(display: $0.uuid) }),
                                         hiddenWorkspaceWindows: hidden, monitorForTiled: monitors,
                                         virtualWorkspaces: config.virtualWorkspaces, knownFloating: knownFloating,
                                         naturalFrames: naturalFrames, fallbackFocus: model.mostRecent(of: visible))
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AppSnapshot? in
            guard app.activationPolicy == .regular, app.processIdentifier != getpid(),
                  scope?.pids.contains(app.processIdentifier) ?? true,
                  let bundleID = app.bundleIdentifier else { return nil }
            return AppSnapshot(pid: app.processIdentifier, bundleID: bundleID,
                                       name: app.localizedName ?? bundleID, launchDate: app.launchDate)
        }
        return TemplateCaptureRequest(facts: facts, apps: apps,
                                      frontmostPID: frontmostPID())
    }

    private func finish(_ batch: WindowBatch, facts: TemplateCaptureFacts) throws -> WorkspaceTemplate {
        var batch = batch
        for index in batch.windows.indices {
            let id = batch.windows[index].windowID
            batch.windows[index].spaces = Spaces.of(window: id)
            if facts.knownFloating[id] == nil {
                batch.windows[index].floatingOverride = floatingDecision(batch.windows[index])
            }
        }
        return try TemplateCaptureAssembler.make(facts: facts, batch: batch)
    }

    private func floatingDecision(_ window: ObservedWindow) -> Bool {
        let title: String? = window.title
        let created = Window(id: window.windowID, element: axApp(window.pid), pid: window.pid,
                             bundleID: window.bundleID)
        created.naturalFrame = window.frame
        return shouldFloat(created, title: title, resizable: window.resizable)
    }
}
