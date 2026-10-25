import AppKit

extension WindowManager {
    func scheduleRefresh(after delay: Double = 0.05) {
        let deadline = DispatchTime.now() + delay
        if refreshWork != nil, refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanAndRefresh() }
        refreshWork = work
        refreshDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work) // style-ok: debounce of refresh requests
    }

    func scanAndRefresh() {
        refreshWork = nil
        guard isStarted, !nativeDesktop.isRunning, !desktops.nativeCreationBusy else { return }
        scanner.observeDesktop(known: Set(windows.keys)) { [weak self] in self?.scanAppsAndRefresh() }
    }

    private func scanAppsAndRefresh() {
        guard isStarted, !nativeDesktop.isRunning, !desktops.nativeCreationBusy else { return }
        let listed = config.virtualWorkspaces ? scanner.desktop.allWindows : scanner.desktop.windows
        let pidsOnScreen = Set(listed.map(\.pid))
        var known: [pid_t: [CGWindowID: Window]] = [:]
        for window in windows.values { known[window.pid, default: [:]][window.id] = window }
        var jobs: [WindowScanner.Job] = []
        let applications = scanner.applications
        observedApps = applications.filter { $0.regular && !$0.hidden }.map { ($0.pid, $0.bundleID) }
        for app in applications {
            let pid = app.pid
            if app.regular { observe(pid: pid) }
            let list = app.regular && !app.hidden && pidsOnScreen.contains(pid)
            guard list || known[pid] != nil else { continue }
            jobs.append(.init(pid: pid, listWindows: list, known: known[pid] ?? [:]))
        }
        let refresh: () -> Void = { [weak self] in self?.refresh() }
        scanner.scan(jobs, done: refresh, updated: refresh)
    }

    func finishTemplateRestore() {
        restoringTemplate = false
        refreshWork?.cancel()
        refreshWork = nil
        refreshDeadline = .distantFuture
        scheduleRefresh(after: 0)
    }
}
