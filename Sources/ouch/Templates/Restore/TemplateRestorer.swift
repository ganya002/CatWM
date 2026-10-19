import AppKit

@MainActor
final class TemplateRestorer {
    let template: WorkspaceTemplate
    let manager = WindowManager.shared
    var matched: [UUID: Window] = [:]
    var failures = Set<String>()
    var scheduler = TemplateRestoreScheduler()
    private var matchStability = TemplateMatchStability()
    private var waitingForMetadata = false
    private var initialWindowIDs: Set<CGWindowID>?

    init(template: WorkspaceTemplate) { self.template = template }

    func restore() async throws -> String {
        guard manager.isStarted, !Screen.all().isEmpty else { throw WindowManager.TemplateError.notReady }
        if let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] {
            initialWindowIDs = Set(list.compactMap {
                ($0[kCGWindowNumber as String] as? Int).map { CGWindowID(truncatingIfNeeded: $0) }
            })
        }
        manager.restoringTemplate = true
        defer { manager.finishTemplateRestore() }
        do {
            try await discover()
            try Task.checkCancellation()
            try await apply()
        } catch {
            scheduler.cancel()
            throw error
        }
        let missing = template.windows.filter { matched[$0.id] == nil }
        for name in scheduler.failures where missing.contains(where: { $0.appName == name }) {
            failures.insert(name)
        }
        let problems = Set(missing.map(\.appName)).union(failures).sorted()
        if problems.isEmpty { return "Opened \(template.name)." }
        return "Opened \(matched.count) of \(template.windows.count) windows. "
            + "Check \(problems.joined(separator: ", "))."
    }

    private var targets: [TemplateRestoreTarget] {
        template.windows.map {
            TemplateRestoreTarget(id: $0.id, bundleID: $0.bundleID, appName: $0.appName, document: $0.document)
        }
    }

    private func discover() async throws {
        let deadline = Date().addingTimeInterval(TemplateRestoreScheduler.totalWait)
        while true {
            try Task.checkCancellation()
            if Date() >= deadline { break }
            for bundle in Set(template.windows.map(\.bundleID)) {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundle).forEach { $0.unhide() }
            }
            try await matchWindows(deadline: deadline)
            let now = Date()
            let step = scheduler.step(now: now, deadline: deadline, targets: targets,
                                      matched: Set(matched.keys), apps: appStates())
            for bundle in step.launch {
                try Task.checkCancellation()
                guard Date() < deadline else { break }
                launch(bundle)
            }
            for request in step.requests {
                try Task.checkCancellation()
                guard Date() < deadline else { break }
                await perform(request, deadline: deadline)
            }
            if !step.keepWaiting, !waitingForMetadata { break }
            let remaining = deadline.timeIntervalSince(Date())
            if remaining <= 0 { break }
            let pause = min(TemplateRestoreScheduler.pollInterval, remaining)
            try await Task.sleep(for: .milliseconds(max(1, Int(pause * 1000))))
        }
    }

    private func matchWindows(deadline: Date) async throws {
        let bundles = Set(template.windows.map(\.bundleID)).sorted()
        var found: [TemplateWindowMatch] = []
        for bundle in bundles {
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            found += await scan(bundle: bundle, deadline: deadline)
        }
        let candidates = found.map { candidate in
            TemplateWindowCandidate(windowID: candidate.window.id, bundleID: candidate.bundleID,
                                    title: candidate.title, document: candidate.document,
                                    launchDate: candidate.launchDate,
                                    allowsGenericFallback: candidate.allowsGenericFallback,
                                    newlyOpened: initialWindowIDs.map { !$0.contains(candidate.window.id) } ?? false)
        }
        let chosen = TemplateWindowMatch.assign(template.windows, candidates: candidates)
        let windows = Dictionary(found.map { ($0.window.id, $0.window) }, uniquingKeysWith: { current, _ in current })
        var next: [UUID: Window] = [:]
        var invalidated = Set<CGWindowID>()
        var probes: [TemplateRestoreAX.Probe] = []
        for window in matched.values where windows[window.id] == nil {
            if NSRunningApplication(processIdentifier: window.pid) == nil {
                invalidated.insert(window.id)
            } else {
                probes.append(.init(id: window.id, element: window.element))
            }
        }
        invalidated.formUnion(await TemplateRestoreAX.invalidated(
            probes, deadline: min(deadline, Date().addingTimeInterval(0.6))))
        let retained = TemplateWindowMatch.retainUnscanned(matched.mapValues(\.id), assigned: chosen,
                                                          scanned: Set(windows.keys), invalidated: invalidated)
        for (savedID, windowID) in retained {
            if let window = windows[windowID] {
                next[savedID] = window
            } else if let window = matched[savedID], window.id == windowID {
                next[savedID] = window
            }
        }
        matched = next
        waitingForMetadata = matchStability.waiting(saved: template.windows, candidates: candidates,
                                                    assigned: chosen, now: Date())
    }

    private func scan(bundle: String, deadline: Date) async -> [TemplateWindowMatch] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).map {
            TemplateRestoreAX.App(pid: $0.processIdentifier, bundleID: bundle, launchDate: $0.launchDate)
        }
        let raw = await TemplateRestoreAX.read(apps: apps, deadline: min(deadline, Date().addingTimeInterval(1.5)))
        let spaces = Set(Screen.all().map { Spaces.current(display: $0.uuid) })
        var found: [TemplateWindowMatch] = []
        for candidate in raw {
            let membership = Spaces.of(window: candidate.id)
            let offSpace = !membership.isEmpty && spaces.isDisjoint(with: membership)
            let hidden = manager.workspaceOf[candidate.id].map { !manager.isShown($0) } ?? false
            let window = manager.windows[candidate.id] ?? Window(id: candidate.id, element: candidate.element,
                                                                pid: candidate.pid, bundleID: bundle)
            AXUIElementSetMessagingTimeout(candidate.element, axTimeout)
            let fallback = TemplateWindowMatch.allowsGenericFallback(offSpace: offSpace, hiddenWorkspace: hidden)
            found.append(.init(window: window, bundleID: bundle, title: candidate.title, document: candidate.document,
                               launchDate: candidate.launchDate, allowsGenericFallback: fallback))
        }
        return found
    }

    private func appStates() -> [String: TemplateAppState] {
        var states: [String: TemplateAppState] = [:]
        for bundle in Set(template.windows.map(\.bundleID)) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            states[bundle] = TemplateAppState(
                running: !running.isEmpty,
                finishedLaunching: running.contains(where: \.isFinishedLaunching),
                openable: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil)
        }
        return states
    }

    private func launch(_ bundleID: String) {
        guard !scheduler.cancelled else { return }
        let appName = template.windows.first { $0.bundleID == bundleID }?.appName ?? bundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            scheduler.noteLaunchFailed(bundleID, appName: appName)
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.unhide() }
        guard running.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self else { return }
                self.scheduler.noteLaunchFailed(bundleID, appName: appName)
            }
        }
    }

    private func perform(_ request: TemplateRestoreRequest, deadline: Date) async {
        let now = Date()
        guard !scheduler.cancelled else { return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: request.bundleID).first,
              let appURL = app.bundleURL else {
            scheduler.noteRefused(request.savedID, appName: request.appName, now: now)
            return
        }
        if let document = request.document {
            guard let url = URL(string: document) else {
                scheduler.noteRefused(request.savedID, appName: request.appName, now: now)
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            let savedID = request.savedID
            let token = request.token
            let appName = request.appName
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: configuration) { [weak self] _, error in
                guard error != nil else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.scheduler.noteFailed(savedID, token: token, appName: appName, now: Date())
                }
            }
            return
        }
        let accepted = await TemplateRestoreAX.newWindow(pid: app.processIdentifier, deadline: deadline)
        if !accepted {
            scheduler.noteRefused(request.savedID, appName: request.appName, now: Date())
        }
    }
}
