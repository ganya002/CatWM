import AppKit
import CoreGraphics
import Foundation

@MainActor
package final class TemplateRestorer {
    package let template: WorkspaceTemplate
    package let manager = WindowManager.shared
    package var matched: [UUID: Window] = [:]
    package var failures = Set<String>()
    package var scheduler = RestoreScheduler()
    private var matchStability = MatchStability()
    private var waitingForMetadata = false
    private var stalledBundles = Set<String>()
    package var earlyRestored = Set<CGWindowID>()
    package var pulled = Set<CGWindowID>()
    package var pullOrigins: [CGWindowID: UInt64] = [:]
    private var scanLogged = Set<String>()
    private var candidateNotes: [CGWindowID: String] = [:]
    private var scanFound: [String: Int] = [:]
    private var adapterFailed = Set<UUID>()
    package var initialWindowIDs: Set<CGWindowID>?

    package init(template: WorkspaceTemplate) { self.template = template }

    package func restore() async throws -> String {
        guard manager.config.features.contains(.templates) else { throw WindowManager.TemplateError.off }
        guard manager.scope == nil else { throw WindowManager.TemplateError.scoped }
        guard manager.isStarted, !Screen.all().isEmpty else { throw WindowManager.TemplateError.notReady }
        initialWindowIDs = Set(CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements]).map(\.id))
        manager.restoringTemplate = true
        defer { manager.finishTemplateRestore() }
        let started = Date()
        Log.info("template: restoring \(template.name) on Desktop \(currentDesktop() ?? 0)")
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
            Log.info("template: matched \(matched.count) of \(template.windows.count) windows in \(found) ms, "
                + "restored in \(total) ms")
        } catch {
            let missing = template.windows.filter { matched[$0.id] == nil }
                .map { "\($0.appName) '\($0.title)'" }.joined(separator: ", ")
            Log.info("template: unmatched saved windows: \(missing)")
            Log.info("template: restore stopped after \(Int(Date().timeIntervalSince(started) * 1000)) ms, "
                + "matched \(matched.count) of \(template.windows.count): \(error.localizedDescription)")
            scheduler.cancel()
            await returnUnusedPulls(keeping: pullOrigins.keys.filter { manager.workspaceOf[$0] != nil })
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

    private var targets: [RestoreTarget] {
        template.windows.map {
            RestoreTarget(id: $0.id, bundleID: $0.bundleID, appName: $0.appName, document: $0.document)
        }
    }

    private func discover() async throws {
        let deadline = Date().addingTimeInterval(RestoreScheduler.totalWait)
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
            let step = scheduler.step(now: now, deadline: deadline,
                                      targets: targets.filter { !stalledBundles.contains($0.bundleID) },
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
            let stalled = Self.waitsOnStall(targets, matched: Set(matched.keys), stalled: stalledBundles)
            if !step.keepWaiting, !waitingForMetadata, !stalled { break }
            let remaining = deadline.timeIntervalSince(Date())
            if remaining <= 0 { break }
            let interval = step.keepWaiting || stalled ? RestoreScheduler.pollInterval : Self.settlePollInterval
            let pause = min(interval, remaining)
            try await Task.sleep(for: .milliseconds(max(1, Int(pause * 1000))))
        }
    }

    package static let settlePollInterval: TimeInterval = 0.05

    private func matchWindows(deadline: Date) async throws {
        let bundles = Set(template.windows.map(\.bundleID)).sorted()
        var found: [Found] = []
        for bundle in bundles {
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            found += await scan(bundle: bundle, deadline: deadline)
        }
        let candidates = found.map { candidate in
            WindowCandidate(windowID: candidate.window.id, bundleID: candidate.bundleID,
                            title: candidate.title, document: candidate.document,
                            launchDate: candidate.launchDate,
                            allowsGenericFallback: candidate.allowsGenericFallback,
                            newlyOpened: isFillable(candidate), frame: candidate.frame)
        }
        let chosen = WindowMatch.assign(template.windows, candidates: candidates)
        let windows = Dictionary(found.map { ($0.window.id, $0.window) }, uniquingKeysWith: { current, _ in current })
        var next: [UUID: Window] = [:]
        var invalidated = Set<CGWindowID>()
        var probes: [RestoreAX.Probe] = []
        for window in matched.values where windows[window.id] == nil {
            if NSRunningApplication(processIdentifier: window.pid) == nil {
                invalidated.insert(window.id)
            } else {
                probes.append(.init(id: window.id, element: window.element))
            }
        }
        invalidated.formUnion(await RestoreAX.invalidated(
            probes, deadline: min(deadline, Date().addingTimeInterval(0.6))))
        let retained = WindowMatch.retainUnscanned(matched.mapValues(\.id), assigned: chosen,
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

    private func scan(bundle: String, deadline: Date) async -> [Found] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).map {
            RestoreAX.App(pid: $0.processIdentifier, bundleID: bundle, launchDate: $0.launchDate)
        }
        let (raw, complete) = await RestoreAX.read(apps: apps, deadline: min(deadline, Date().addingTimeInterval(1.5)))
        if complete { stalledBundles.remove(bundle) } else { stalledBundles.insert(bundle) }
        let spaces = Set(Screen.all().map { Spaces.current(display: $0.uuid) })
        if scanLogged.insert(bundle).inserted || !raw.isEmpty && scanFound[bundle] != raw.count {
            scanFound[bundle] = raw.count
            Log.info("template: scan \(bundle) apps \(apps.count) windows \(raw.count)")
        }
        var found: [Found] = []
        for candidate in raw {
            let membership = Spaces.of(window: candidate.id)
            let offSpace = !membership.isEmpty && spaces.isDisjoint(with: membership)
            let hidden = !pulled.contains(candidate.id)
                && (manager.workspaceOf[candidate.id].map { !manager.isShown($0) } ?? false)
            let window = manager.windows[candidate.id] ?? Window(id: candidate.id, element: candidate.element,
                                                                pid: candidate.pid, bundleID: bundle)
            AXUIElementSetMessagingTimeout(candidate.element, axTimeout)
            let fallback = WindowMatch.allowsGenericFallback(offSpace: offSpace, hiddenWorkspace: hidden)
            let note = "title '\(candidate.title)' spaces \(membership) offSpace \(offSpace) hidden \(hidden) "
                + "generic \(fallback)"
            if candidateNotes[candidate.id] != note {
                candidateNotes[candidate.id] = note
                Log.info("template: candidate \(candidate.id) of \(bundle) \(note)")
            }
            found.append(.init(window: window, bundleID: bundle, title: candidate.title, document: candidate.document,
                               launchDate: candidate.launchDate, allowsGenericFallback: fallback,
                               frame: candidate.frame))
        }
        return found
    }

    private func appStates() -> [String: AppLaunchState] {
        var states: [String: AppLaunchState] = [:]
        for bundle in Set(template.windows.map(\.bundleID)) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            states[bundle] = AppLaunchState(
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
        let arguments = template.windows.lazy.filter { $0.bundleID == bundleID }
            .compactMap { $0.launch?.arguments }.first ?? []
        Task { @MainActor [weak self] in
            guard await !Launcher.launch(url, arguments: arguments), let self else { return }
            self.scheduler.noteLaunchFailed(bundleID, appName: appName)
        }
    }

    private func perform(_ request: RestoreRequest, deadline: Date) async {
        let now = Date()
        guard !scheduler.cancelled else { return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: request.bundleID).first,
              let appURL = app.bundleURL else {
            scheduler.noteRefused(request.savedID, appName: request.appName, now: now)
            return
        }
        let saved = template.windows.first { $0.id == request.savedID }
        if let command = saved?.launch?.command {
            let started = Launcher.run(command: command)
            Log.info("template: launch command for \(request.appName) \(started ? "started" : "failed")")
            if !started { scheduler.noteRefused(request.savedID, appName: request.appName, now: now) }
            return
        }
        if let state = saved?.state, !adapterFailed.contains(request.savedID),
           await AppAdapters.canRestore(state, bundleID: request.bundleID) {
            Log.info("template: reopening \(state.tabs.count) tabs or folders for \(request.appName)")
            open(request, adapter: true) {
                await AppAdapters.restore(state, bundleID: request.bundleID, appURL: appURL)
            }
            return
        }
        if let raw = saved?.launch?.url ?? request.document {
            guard let url = URL(string: raw) else {
                scheduler.noteRefused(request.savedID, appName: request.appName, now: now)
                return
            }
            open(request, adapter: false) { await Launcher.open(url, withApp: appURL) }
            return
        }
        let accepted = await RestoreAX.newWindow(pid: app.processIdentifier, deadline: deadline)
        Log.info("template: new window for \(request.appName) \(accepted ? "accepted" : "refused")")
        guard !accepted else { return }
        Log.info("template: asking \(request.appName) to reopen a window")
        open(request, adapter: false) { await Launcher.launch(appURL) }
    }

    private func open(_ request: RestoreRequest, adapter: Bool, _ opening: @escaping @MainActor () async -> Bool) {
        let savedID = request.savedID
        let token = request.token
        let appName = request.appName
        Task { @MainActor [weak self] in
            guard await !opening(), let self else { return }
            if adapter { self.adapterFailed.insert(savedID) }
            self.scheduler.noteFailed(savedID, token: token, appName: appName, now: Date())
        }
    }
}

extension TemplateRestorer {
    package static func waitsOnStall(_ targets: [RestoreTarget], matched: Set<UUID>, stalled: Set<String>) -> Bool {
        targets.contains { !matched.contains($0.id) && stalled.contains($0.bundleID) }
    }
}

package enum TemplatePlacementPlan {
    package enum DesktopMove: Equatable {
        case stay
        case move
        case unavailable
    }

    package static func preferredDisplays(_ template: WorkspaceTemplate,
                                          mapping: [String: String]) -> [String: String] {
        var preferred: [String: String] = [:]
        for display in template.displays.filter(\.isMain) + template.displays.filter({ !$0.isMain }) {
            guard let target = mapping[display.id], preferred[target] == nil else { continue }
            preferred[target] = display.id
        }
        return preferred
    }

    package static func desktopMove(membership: [UInt64], destination: UInt64) -> DesktopMove {
        if membership.isEmpty { return .unavailable }
        return membership.contains(destination) ? .stay : .move
    }
}
