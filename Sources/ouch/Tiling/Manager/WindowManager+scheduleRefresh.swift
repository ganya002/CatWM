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
        guard isStarted else { return }
        let pidsOnScreen = Set(CGWindowInfo.onScreen().map(\.pid))
        var known: [pid_t: [CGWindowID: Window]] = [:]
        for w in windows.values { known[w.pid, default: [:]][w.id] = w }
        var jobs: [WindowScanner.Job] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != getpid() {
            let pid = app.processIdentifier
            let list = app.activationPolicy == .regular && !app.isHidden && pidsOnScreen.contains(pid)
            guard list || known[pid] != nil else { continue }
            jobs.append(.init(pid: pid, listWindows: list, known: known[pid] ?? [:]))
        }
        scanner.scan(jobs, done: { [weak self] in self?.refresh() }, late: { [weak self] in self?.refresh() })
    }

}
