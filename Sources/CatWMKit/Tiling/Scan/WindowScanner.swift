import AppKit
import QuartzCore

package final class WindowScanner {
    package struct Job {
        package let pid: pid_t
        package let listWindows: Bool
        package let known: [CGWindowID: Window]
        package let fullscreen: Set<CGWindowID>
        package let minimized: Set<CGWindowID>

        package init(pid: pid_t, listWindows: Bool, known: [CGWindowID: Window]) {
            self.pid = pid; self.listWindows = listWindows; self.known = known
            fullscreen = Set(known.values.filter(\.fullscreen).map(\.id))
            minimized = Set(known.values.filter(\.minimized).map(\.id))
        }
    }

    package struct Found {
        package let element: AXUIElement
        package let frame: CGRect
        package let title: String?
        package let resizable: Bool
        package var frameRevision: Int?
    }

    package struct AppScan {
        package var readAt = Date()
        package var listed: [CGWindowID] = []
        package var found: [CGWindowID: Found] = [:]
        package var fullscreen: Set<CGWindowID> = []
        package var minimized: Set<CGWindowID> = []
        package var gone: Set<CGWindowID> = []

        package func hasNewWindows(comparedTo known: [CGWindowID: Window]) -> Bool {
            found.contains { known[$0.key] == nil && !$0.value.frame.isNull }
        }
    }

    package static let deadline = 0.25

    package private(set) var results: [pid_t: AppScan] = [:]
    package private(set) var desktop = WindowServerObservation()
    package private(set) var applications: [RunningApplicationSnapshot] = []
    package private(set) var claimed: Set<pid_t> = []
    private var observingDesktop = false
    private var pendingDesktop: (known: Set<CGWindowID>, done: () -> Void)?
    private let readDesktop: (Set<CGWindowID>) -> WindowServerObservation
    private let readApplications: () -> [RunningApplicationSnapshot]
    private let scope: WindowScope?
    private let claims: ScopeClaims?
    package private(set) var lastScan: CFTimeInterval = 0
    private var busy: [pid_t: UUID] = [:]
    private var idleWaiters: [() -> Void] = []
    private var queues: [pid_t: DispatchQueue] = [:]
    private let read: (Job, (AppScan) -> Void) -> AppScan
    private let scanDeadline: TimeInterval

    package init(read: @escaping (Job, (AppScan) -> Void) -> AppScan = { AXBackend.shared.scan($0, discovered: $1) },
                 readDesktop: @escaping (Set<CGWindowID>) -> WindowServerObservation = {
                     AXBackend.shared.desktop(known: $0)
                 },
                 readApplications: @escaping () -> [RunningApplicationSnapshot] = { AXBackend.shared.applications() },
                 deadline: TimeInterval = WindowScanner.deadline,
                 scope: WindowScope? = nil, claims: ScopeClaims? = nil) {
        self.read = read
        self.readDesktop = readDesktop
        self.readApplications = readApplications
        scanDeadline = deadline
        self.scope = scope
        self.claims = claims
    }

    package func observeDesktop(known: Set<CGWindowID>, done: @escaping () -> Void) {
        guard !observingDesktop else {
            pendingDesktop = ((pendingDesktop?.known ?? []).union(known), done)
            return
        }
        observingDesktop = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, readDesktop, readApplications, scope, claims] in
            let claimed = claims?.claimedPids() ?? []
            let keep = { (pid: pid_t) in scope?.pids.contains(pid) ?? !claimed.contains(pid) }
            let observation = readDesktop(known).keeping(keep)
            let applications = readApplications().filter { keep($0.pid) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.desktop = observation
                self.applications = applications
                self.claimed = claimed
                self.observingDesktop = false
                let pending = self.pendingDesktop
                self.pendingDesktop = nil
                done()
                if let pending { self.observeDesktop(known: pending.known, done: pending.done) }
            }
        }
    }

    package func watchClaims(_ changed: @escaping () -> Void) { claims?.watch(changed) }
    package func stopWatchingClaims() { claims?.stop() }

    package func keeps(_ pid: pid_t) -> Bool { scope?.pids.contains(pid) ?? !claimed.contains(pid) }

    package func scan(_ jobs: [Job], done: @escaping () -> Void, updated: @escaping () -> Void,
                      readAll: ((_ all: Bool) -> Void)? = nil) {
        lastScan = CACurrentMediaTime()
        let running = Set(jobs.map(\.pid))
        for pid in results.keys where !running.contains(pid) { forget(pid) }
        let asked = jobs.filter { busy[$0.pid] == nil }
        var waiting = asked.count
        var finished = false
        var updateQueued = false
        func publish() {
            guard !updateQueued else { return }
            updateQueued = true
            DispatchQueue.main.async {
                updateQueued = false
                if !finished { updated() }
            }
        }
        func finish() {
            guard !finished else { return }
            finished = true
            done()
        }
        guard waiting > 0 else { finish(); readAll?(asked.count == jobs.count); return }
        for job in asked {
            let token = UUID()
            busy[job.pid] = token
            run(job.pid) { [weak self, read] in
                let start = CACurrentMediaTime()
                let scan = read(job) { discovery in
                    self?.acceptDiscovery(discovery, pid: job.pid, token: token) {
                        if finished { updated() } else { publish() }
                    }
                }
                let elapsed = CACurrentMediaTime() - start
                DispatchQueue.main.async {
                    guard let self else { return }
                    waiting -= 1
                    if self.busy[job.pid] == token {
                        self.busy[job.pid] = nil
                        self.results[job.pid] = scan
                        Log.debug(String(format: "scan: pid %d windows %d %.1fms",
                                         job.pid, scan.listed.count, elapsed * 1000))
                        if finished {
                            updated()
                        } else if waiting > 0, scan.hasNewWindows(comparedTo: job.known) { publish() }
                    }
                    if waiting == 0 { finish(); readAll?(asked.count == jobs.count) }
                    self.notifyIdle()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + scanDeadline) { finish() } // style-ok: limit for a hung app
    }

    private func acceptDiscovery(_ scan: AppScan, pid: pid_t, token: UUID, notify: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.busy[pid] == token else { return }
            self.results[pid] = scan
            notify()
        }
    }

    package func whenIdle(_ action: @escaping () -> Void) {
        guard !busy.isEmpty else { return action() }
        idleWaiters.append(action)
    }

    private func notifyIdle() {
        guard busy.isEmpty, !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0() }
    }

    package func forget(_ pid: pid_t) {
        results[pid] = nil
        busy[pid] = nil
        notifyIdle()
    }

    package func terminated(_ pid: pid_t) {
        forget(pid)
        queues[pid] = nil
    }

    package var queueCount: Int { queues.count }

    package func run(_ pid: pid_t, _ work: @escaping () -> Void) {
        let queue = queues[pid] ?? DispatchQueue(label: "catwm.scan.\(pid)", qos: .userInitiated)
        queues[pid] = queue
        queue.async(execute: work)
    }
}

package struct RunningApplicationSnapshot {
    package let pid: pid_t
    package let bundleID: String?
    package let regular: Bool
    package let hidden: Bool

    package static func read() -> [Self] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid != getpid() else { return nil }
            let regular = app.activationPolicy == .regular
            return Self(pid: pid, bundleID: regular ? app.bundleIdentifier : nil,
                        regular: regular, hidden: regular && app.isHidden)
        }
    }
}
