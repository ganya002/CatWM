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
    private var earlyRestored = Set<CGWindowID>()
    private var pulled = Set<CGWindowID>()
    private var pullOrigins: [CGWindowID: UInt64] = [:]
    private var scanLogged = Set<String>()
    private var lastWindowSummary = ""
    private var candidateNotes: [CGWindowID: String] = [:]
    private var scanFound: [String: Int] = [:]
    var initialWindowIDs: Set<CGWindowID>?

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
        let started = Date()
        Log.info("template: restoring \(template.name) on Desktop \(manager.currentScreen().map { Spaces.current(display: $0.uuid) } ?? 0)")
        do {
            try await discover()
            let found = Int(Date().timeIntervalSince(started) * 1000)
            try Task.checkCancellation()
            try await apply()
            await returnUnusedPulls(keeping: Set(matched.values.map(\.id)))
            let total = Int(Date().timeIntervalSince(started) * 1000)
            if matched.count < template.windows.count {
                let missing = template.windows.filter { matched[$0.id] == nil }
                    .map { "\($0.appName) '\($0.title)'" }.joined(separator: ", ")
                Log.info("template: unmatched saved windows: \(missing)")
            }
            Log.info("template: matched \(matched.count) of \(template.windows.count) windows in \(found) ms, restored in \(total) ms")
        } catch {
            let missing = template.windows.filter { matched[$0.id] == nil }
                .map { "\($0.appName) '\($0.title)'" }.joined(separator: ", ")
            Log.info("template: unmatched saved windows: \(missing)")
            Log.info("template: restore stopped after \(Int(Date().timeIntervalSince(started) * 1000)) ms, "
                + "matched \(matched.count) of \(template.windows.count): \(error.localizedDescription)")
            scheduler.cancel()
            await returnUnusedPulls(keeping: Set(pullOrigins.keys.filter { manager.workspaceOf[$0] != nil }))
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
        await pullOffDesktopWindows()
        while true {
            try Task.checkCancellation()
            if Date() >= deadline { break }
            for bundle in Set(template.windows.map(\.bundleID)) {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundle).forEach { $0.unhide() }
            }
            pullNewWindowsHere()
            try await matchWindows(deadline: deadline)
            prepareMatchedEarly()
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
            let interval = step.keepWaiting ? TemplateRestoreScheduler.pollInterval : Self.settlePollInterval
            let pause = min(interval, remaining)
            try await Task.sleep(for: .milliseconds(max(1, Int(pause * 1000))))
        }
    }

    private static let settlePollInterval: TimeInterval = 0.05

    private func pullOffDesktopWindows() async {
        guard let screen = manager.currentScreen() ?? Screen.all().first else { return }
        let here = Spaces.current(display: screen.uuid)
        let desktops = Set(Screen.all().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for bundle in Set(template.windows.map(\.bundleID)).sorted() {
            let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
                .map { Int($0.processIdentifier) })
            var present = 0
            var elsewhere: [(id: CGWindowID, space: UInt64)] = []
            for info in list where (info[kCGWindowLayer as String] as? Int) == 0
                && pids.contains(info[kCGWindowOwnerPID as String] as? Int ?? -1) {
                guard let number = info[kCGWindowNumber as String] as? Int,
                      let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                        .flatMap({ CGRect(dictionaryRepresentation: $0) }),
                      bounds.width >= 100, bounds.height >= 100 else { continue }
                let membership = Spaces.of(window: CGWindowID(number))
                if membership.contains(here) {
                    present += 1
                } else if membership.count == 1, let space = membership.first, desktops.contains(space) {
                    elsewhere.append((CGWindowID(number), space))
                }
            }
            let wanted = template.windows.filter { $0.bundleID == bundle }.count
            for (id, origin) in elsewhere.prefix(max(0, wanted - present)) {
                guard !Task.isCancelled else { return }
                pulled.insert(id)
                pullOrigins[id] = origin
                Log.info("template: pulling window \(id) of \(bundle) from Desktop \(Spaces.of(window: id)) to \(here)")
                _ = await withCheckedContinuation { continuation in
                    Spaces.move(window: id, to: here) { continuation.resume(returning: $0) }
                }
            }
        }
    }

    private func returnUnusedPulls(keeping used: Set<CGWindowID>) async {
        for (id, origin) in pullOrigins where !used.contains(id) {
            guard Spaces.of(window: id) != [origin] else { continue }
            Log.info("template: returning unused window \(id) to Desktop \(origin)")
            _ = await withCheckedContinuation { continuation in
                Spaces.move(window: id, to: origin) { continuation.resume(returning: $0) }
            }
        }
        pullOrigins = [:]
    }

    private func pullNewWindowsHere() {
        guard let initial = initialWindowIDs, let screen = manager.currentScreen() ?? Screen.all().first else { return }
        let here = Spaces.current(display: screen.uuid)
        let desktops = Set(Screen.all().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        let pids = Set(template.windows.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).map { Int($0.processIdentifier) }
        })
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let mine = list.filter { (info: [String: Any]) -> Bool in
            (info[kCGWindowLayer as String] as? Int) == 0 && pids.contains(info[kCGWindowOwnerPID as String] as? Int ?? -1)
        }
        let summary = mine.map { info -> String in
            let number = info[kCGWindowNumber as String] as? Int ?? 0
            let size = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) }.map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
            let isNew = !initial.contains(CGWindowID(number))
            return "\(number)\(isNew ? "*" : "") \(size) spaces \(Spaces.of(window: CGWindowID(number)))"
        }.sorted().joined(separator: "; ")
        if summary != lastWindowSummary {
            lastWindowSummary = summary
            Log.info("template: windows of template apps (here \(here)): \(summary)")
        }
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let number = info[kCGWindowNumber as String] as? Int, let pid = info[kCGWindowOwnerPID as String] as? Int,
                  pids.contains(pid), !initial.contains(CGWindowID(number)), !pulled.contains(CGWindowID(number)),
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  bounds.width >= 100, bounds.height >= 100 else { continue }
            let membership = Spaces.of(window: CGWindowID(number))
            if let space = membership.first {
                guard membership.count == 1, space != here, desktops.contains(space) else { continue }
            }
            pulled.insert(CGWindowID(number))
            Log.info("template: pulling new window \(number) of pid \(pid) from Desktop \(membership) to \(here)")
            Spaces.move(window: CGWindowID(number), to: here) { _ in }
        }
    }

    private func prepareMatchedEarly() {
        let screens = Screen.all()
        let mainID = NSScreen.screens.first?.displayID
        let mapping = template.displayMap(available: screens.map { ($0.uuid, $0.id == mainID) })
        for saved in template.windows where !saved.minimized && !saved.fullscreen {
            guard let window = matched[saved.id], earlyRestored.insert(window.id).inserted else { continue }
            AXUIElementSetMessagingTimeout(window.element, axTimeout)
            if window.element.flag(kAXMinimizedAttribute) {
                _ = window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
            }
            guard initialWindowIDs?.contains(window.id) == false, !window.isNativeFullscreen,
                  let target = mapping[saved.display], let screen = screens.first(where: { $0.uuid == target }),
                  let original = template.displays.first(where: { $0.id == saved.display }) else { continue }
            window.setFrame(WorkspaceTemplate.restoredFrame(saved.frame, from: original.visible, to: screen.visible))
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
                                    newlyOpened: pulled.contains(candidate.window.id)
                                        || (candidate.allowsGenericFallback && manager.workspaceOf[candidate.window.id] == nil)
                                        || (initialWindowIDs.map { !$0.contains(candidate.window.id) } ?? false))
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
        if scanLogged.insert(bundle).inserted || !raw.isEmpty && scanFound[bundle] != raw.count {
            scanFound[bundle] = raw.count
            Log.info("template: scan \(bundle) apps \(apps.count) windows \(raw.count)")
        }
        var found: [TemplateWindowMatch] = []
        for candidate in raw {
            let membership = Spaces.of(window: candidate.id)
            let offSpace = !membership.isEmpty && spaces.isDisjoint(with: membership)
            let hidden = !pulled.contains(candidate.id)
                && (manager.workspaceOf[candidate.id].map { !manager.isShown($0) } ?? false)
            let window = manager.windows[candidate.id] ?? Window(id: candidate.id, element: candidate.element,
                                                                pid: candidate.pid, bundleID: bundle)
            AXUIElementSetMessagingTimeout(candidate.element, axTimeout)
            let fallback = TemplateWindowMatch.allowsGenericFallback(offSpace: offSpace, hiddenWorkspace: hidden)
            let note = "title '\(candidate.title)' spaces \(membership) offSpace \(offSpace) hidden \(hidden) "
                + "generic \(fallback)"
            if candidateNotes[candidate.id] != note {
                candidateNotes[candidate.id] = note
                Log.info("template: candidate \(candidate.id) of \(bundle) \(note)")
            }
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
        Log.info("template: new window for \(request.appName) \(accepted ? "accepted" : "refused")")
        if !accepted {
            scheduler.noteRefused(request.savedID, appName: request.appName, now: Date())
        }
    }
}
