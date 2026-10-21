import AppKit

extension WindowManager {
    func scheduleRefresh(after delay: Double = 0.05) {
        let deadline = DispatchTime.now() + delay
        if refreshWork != nil, refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanAndRefresh() }
        refreshWork = work
        refreshDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work)
    }

    func scanAndRefresh() {
        refreshWork = nil
        guard isStarted, !nativeDesktop.isRunning, !nativeCreationBusy else { return }
        scanner.observeDesktop(known: Set(windows.keys)) { [weak self] in self?.scanAppsAndRefresh() }
    }

    private func scanAppsAndRefresh() {
        guard isStarted else { return }
        let listed = config.virtualWorkspaces ? scanner.desktop.allWindows : scanner.desktop.windows
        let pidsOnScreen = Set(listed.map(\.pid))
        var known: [pid_t: [CGWindowID: Window]] = [:]
        for window in windows.values { known[window.pid, default: [:]][window.id] = window }
        var jobs: [WindowScanner.Job] = []
        let applications = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != getpid() }
        observedApps = applications.filter { $0.activationPolicy == .regular && !$0.isHidden }
            .map { ($0.processIdentifier, $0.bundleIdentifier) }
        for app in applications {
            observe(app)
            let pid = app.processIdentifier
            let list = app.activationPolicy == .regular && !app.isHidden && pidsOnScreen.contains(pid)
            guard list || known[pid] != nil else { continue }
            jobs.append(.init(pid: pid, listWindows: list, known: known[pid] ?? [:]))
        }
        let refresh: () -> Void = { [weak self] in self?.refresh() }
        scanner.scan(jobs, done: refresh, late: refresh)
    }

    func finishTemplateRestore() {
        restoringTemplate = false
        refreshWork?.cancel()
        refreshWork = nil
        refreshDeadline = .distantFuture
        scheduleRefresh(after: 0)
    }
}
