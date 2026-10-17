import AppKit

@MainActor
final class TemplateRestorer {
    let template: WorkspaceTemplate
    let manager = WindowManager.shared
    var matched: [UUID: Window] = [:]
    var requestedDocuments = Set<String>()
    var requestedWindows = Set<UUID>()
    var lastRequest: [String: Date] = [:]
    var failures = Set<String>()

    init(template: WorkspaceTemplate) { self.template = template }

    func restore() async throws -> String {
        guard manager.isStarted, !Screen.all().isEmpty else { throw WindowManager.TemplateError.notReady }
        manager.restoringTemplate = true
        defer {
            manager.restoringTemplate = false
            manager.scheduleRefresh(after: 0)
        }
        for bundle in Set(template.windows.map(\.bundleID)) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundle).forEach { $0.unhide() }
        }
        matchWindows()
        launchMissingApps()
        let deadline = Date().addingTimeInterval(15)
        while matched.count < template.windows.count, Date() < deadline {
            try Task.checkCancellation()
            matchWindows()
            requestMissingWindows()
            if matched.count == template.windows.count { break }
            try await Task.sleep(for: .milliseconds(300))
        }
        try Task.checkCancellation()
        try await apply()
        let missing = template.windows.filter { matched[$0.id] == nil }.map(\.appName)
        let problems = Set(missing).union(failures).sorted()
        if problems.isEmpty { return "Opened \(template.name)." }
        return "Opened \(matched.count) of \(template.windows.count) windows. Check \(problems.joined(separator: ", "))."
    }

    func matchWindows() {
        let bundles = Set(template.windows.map(\.bundleID))
        let candidates = bundles.flatMap { TemplateWindowMatch.read(bundleID: $0, manager: manager) }
        var used = Set(matched.values.map(\.id))
        for score in stride(from: 3, through: 0, by: -1) {
            for saved in template.windows where matched[saved.id] == nil {
                guard let candidate = candidates.first(where: {
                    !used.contains($0.window.id) && $0.window.bundleID == saved.bundleID &&
                        TemplateWindowMatch.score(saved, title: $0.title, document: $0.document,
                                                  windowID: $0.window.id, launchDate: $0.launchDate) == score
                }) else { continue }
                matched[saved.id] = candidate.window
                used.insert(candidate.window.id)
            }
        }
    }

    func launchMissingApps() {
        for bundle in Set(template.windows.filter { matched[$0.id] == nil }.map(\.bundleID)) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
                failures.insert(template.windows.first { $0.bundleID == bundle }?.appName ?? bundle)
                continue
            }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            running.forEach { $0.unhide() }
            guard running.isEmpty else { continue }
            lastRequest[bundle] = Date()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                if error != nil {
                    Task { @MainActor in
                        guard let self else { return }
                        self.failures.insert(self.template.windows.first { $0.bundleID == bundle }?.appName ?? bundle)
                    }
                }
            }
        }
    }

    func requestMissingWindows() {
        for saved in template.windows where matched[saved.id] == nil {
            guard Date().timeIntervalSince(lastRequest[saved.bundleID] ?? .distantPast) > 1.5,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: saved.bundleID).first,
                  let appURL = app.bundleURL else { continue }
            if let document = saved.document, let url = URL(string: document) {
                let key = saved.bundleID + "\n" + document
                guard requestedDocuments.insert(key).inserted else { continue }
                lastRequest[saved.bundleID] = Date()
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
                    if error != nil { Task { @MainActor in self?.failures.insert(saved.appName) } }
                }
            } else if requestedWindows.insert(saved.id).inserted {
                lastRequest[saved.bundleID] = Date()
                if !Self.newWindow(pid: app.processIdentifier) { failures.insert(saved.appName) }
            }
        }
    }

    static func newWindow(pid: pid_t) -> Bool {
        guard let bar = axApp(pid).element(kAXMenuBarAttribute) else { return false }
        let items = bar.elements(kAXChildrenAttribute).flatMap { $0.elements(kAXChildrenAttribute) }
            .flatMap { $0.elements(kAXChildrenAttribute) }
        let enabled = items.filter { $0.bool(kAXEnabledAttribute) != false }
        let item = enabled.first { $0.string(kAXTitleAttribute) == "New Window" }
            ?? enabled.first {
                $0.string(kAXMenuItemCmdCharAttribute)?.lowercased() == "n" &&
                    (($0.value(kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0) == 0
            }
        guard let item else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }
}
