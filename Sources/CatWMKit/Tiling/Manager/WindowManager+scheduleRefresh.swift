import AppKit

extension WindowManager {
    package func scheduleRefresh(after delay: Double = 0.05) {
        let deadline = DispatchTime.now() + delay
        if refreshWork != nil, refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanAndRefresh() }
        refreshWork = work
        refreshDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work) // style-ok: debounce of refresh requests
    }

    package func scanAndRefresh(then done: (() -> Void)? = nil) {
        refreshWork = nil
        guard isStarted, !nativeDesktop.isRunning, !desktops.nativeCreationBusy else { done?(); return }
        scanRequests += 1
        let request = scanRequests
        if let done { scanWaiters.append((request, done)) }
        scanner.observeDesktop(known: Set(windows.keys)) { [weak self] in self?.scanAppsAndRefresh(request) }
    }

    private func scanAppsAndRefresh(_ request: Int) {
        guard isStarted, !nativeDesktop.isRunning, !desktops.nativeCreationBusy else { return finishScan(request) }
        releaseClaimedApps()
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
        let readAll: ((Bool) -> Void)? = scanWaiters.isEmpty ? nil : { [weak self] all in
            guard let self else { return }
            if all { finishScan(request) } else { scanner.whenIdle { [weak self] in self?.scanAndRefresh() } }
        }
        scanner.scan(jobs, done: refresh, updated: refresh, readAll: readAll)
    }

    private func finishScan(_ request: Int) {
        guard !scanWaiters.isEmpty else { return }
        let ready = scanWaiters.filter { $0.request <= request }
        scanWaiters.removeAll { $0.request <= request }
        ready.forEach { $0.done() }
    }

    package func finishTemplateRestore() {
        restoringTemplate = false
        refreshWork?.cancel()
        refreshWork = nil
        refreshDeadline = .distantFuture
        scheduleRefresh(after: 0)
    }
}
