import AppKit
import QuartzCore

@MainActor package final class WindowScanner {
    package struct Job: Sendable {
        package let pid: pid_t
        package let listWindows: Bool
        package let known: [CGWindowID: Window]
        package let fullscreen: Set<CGWindowID>
        package let minimized: Set<CGWindowID>

        @MainActor package init(pid: pid_t, listWindows: Bool, known: [CGWindowID: Window]) {
            self.pid = pid; self.listWindows = listWindows; self.known = known
            fullscreen = Set(known.values.filter(\.fullscreen).map(\.id))
            minimized = Set(known.values.filter(\.minimized).map(\.id))
        }
    }

    package struct Found: Sendable {
        private let reference: AXReference<AXUIElement>
        package var element: AXUIElement { reference.object }
        package let frame: CGRect
        package let title: String?
        package let resizable: Bool
        package var frameRevision: Int?

        package init(element: AXUIElement, frame: CGRect, title: String?, resizable: Bool, frameRevision: Int? = nil) {
            (reference, self.frame, self.title) = (AXReference(element), frame, title)
            (self.resizable, self.frameRevision) = (resizable, frameRevision)
        }
    }

    package struct AppScan: Sendable {
        package var readAt = Date()
        package var listed: [CGWindowID] = []
        package var found: [CGWindowID: Found] = [:]
        package var fullscreen: Set<CGWindowID> = []
        package var minimized: Set<CGWindowID> = []
        package var gone: Set<CGWindowID> = []

        package init() {}

        package func hasNewWindows(comparedTo known: [CGWindowID: Window]) -> Bool {
            found.contains { known[$0.key] == nil && !$0.value.frame.isNull }
        }
    }

    package nonisolated static let deadline = 0.25

    package private(set) var results: [pid_t: AppScan] = [:]
    package private(set) var desktop = WindowServerObservation()
    package private(set) var applications: [RunningApplicationSnapshot] = []
    package private(set) var claimed: Set<pid_t> = []
    private var observingDesktop = false
    private var pendingDesktop: (known: Set<CGWindowID>, done: @MainActor () -> Void)?
    private let readDesktop: @MainActor (Set<CGWindowID>) -> WindowServerObservation
    private let readApplications: @Sendable () -> [RunningApplicationSnapshot]
    private let scope: WindowScope?
    private let claims: ScopeClaims?
    package private(set) var lastScan: CFTimeInterval = 0
    private var busy: [pid_t: UUID] = [:]
    private var idleWaiters: [@MainActor () -> Void] = []
    private var queues: [pid_t: DispatchQueue] = [:]
    private let read: @Sendable (Job, @Sendable (AppScan) -> Void) -> AppScan
    private let scanDeadline: TimeInterval

    package init(read: @escaping @Sendable (Job, @Sendable (AppScan) -> Void) -> AppScan = {
                     AXBackend.shared.scan($0, discovered: $1)
    },
                 readDesktop: @escaping @MainActor (Set<CGWindowID>) -> WindowServerObservation = {
                     AXBackend.shared.desktop(known: $0)
                 },
                 readApplications: @escaping @Sendable () -> [RunningApplicationSnapshot] = {
                     AXBackend.shared.applications()
                 },
                 deadline: TimeInterval = WindowScanner.deadline,
                 scope: WindowScope? = nil, claims: ScopeClaims? = nil) {
        self.read = read
        self.readDesktop = readDesktop
        self.readApplications = readApplications
        scanDeadline = deadline
        self.scope = scope
        self.claims = claims
    }

    package func observeDesktop(known: Set<CGWindowID>, done: @escaping @MainActor () -> Void) {
        guard !observingDesktop else {
            pendingDesktop = ((pendingDesktop?.known ?? []).union(known), done)
            return
        }
        observingDesktop = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, readDesktop, readApplications, scope, claims] in
            let claimed = claims?.claimedPids() ?? []
            let keep = { @Sendable (pid: pid_t) in scope?.pids.contains(pid) ?? !claimed.contains(pid) }
            let applications = readApplications().filter { keep($0.pid) }
            DispatchQueue.main.async {
                guard let self else { return }
                let started = CACurrentMediaTime()
                self.desktop = readDesktop(known).keeping(keep)
                Log.debug(String(format: "scan: desktop windows %d %.1fms", self.desktop.allWindows.count,
                                 (CACurrentMediaTime() - started) * 1000))
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

    package func watchClaims(_ changed: @escaping @Sendable () -> Void) { claims?.watch(changed) }
    package func stopWatchingClaims() { claims?.stop() }

    package func keeps(_ pid: pid_t) -> Bool { scope?.pids.contains(pid) ?? !claimed.contains(pid) }

    package func scan(_ jobs: [Job], done: @escaping @MainActor () -> Void, updated: @escaping @MainActor () -> Void,
                      readAll: (@MainActor (_ all: Bool) -> Void)? = nil) {
        lastScan = CACurrentMediaTime()
        let running = Set(jobs.map(\.pid))
        for pid in results.keys where !running.contains(pid) { forget(pid) }
        let asked = jobs.filter { busy[$0.pid] == nil }
        let progress = ScanProgress(waiting: asked.count, done: done, updated: updated)
        guard progress.waiting > 0 else { progress.finish(); readAll?(asked.count == jobs.count); return }
        for job in asked {
            let token = UUID()
            busy[job.pid] = token
            run(job.pid) { [weak self, read] in
                let start = CACurrentMediaTime()
                let scan = read(job) { [weak self] discovery in
                    self?.acceptDiscovery(discovery, pid: job.pid, token: token) { progress.discovered() }
                }
                let elapsed = CACurrentMediaTime() - start
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    progress.waiting -= 1
                    if self.busy[job.pid] == token {
                        self.busy[job.pid] = nil
                        self.results[job.pid] = scan
                        Log.debug(String(format: "scan: pid %d windows %d %.1fms",
                                         job.pid, scan.listed.count, elapsed * 1000))
                        if progress.finished {
                            updated()
                        } else if progress.waiting > 0, scan.hasNewWindows(comparedTo: job.known) { progress.publish() }
                    }
                    if progress.waiting == 0 { progress.finish(); readAll?(asked.count == jobs.count) }
                    self.notifyIdle()
                }
            }
        }
        progress.expire(after: scanDeadline)
    }

    private nonisolated func acceptDiscovery(_ scan: AppScan, pid: pid_t, token: UUID,
                                             notify: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.busy[pid] == token else { return }
            self.results[pid] = scan
            notify()
        }
    }

    package func whenIdle(_ action: @escaping @MainActor () -> Void) {
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

    package func run(_ pid: pid_t, _ work: @escaping @Sendable () -> Void) {
        let queue = queues[pid] ?? DispatchQueue(label: "catwm.scan.\(pid)", qos: .userInitiated)
        queues[pid] = queue
        queue.async(execute: work)
    }
}

@MainActor private final class ScanProgress {
    var waiting: Int
    private(set) var finished = false
    private var updateQueued = false
    private var limit: DispatchSourceTimer?
    private let done: @MainActor () -> Void
    private let updated: @MainActor () -> Void

    init(waiting: Int, done: @escaping @MainActor () -> Void, updated: @escaping @MainActor () -> Void) {
        self.waiting = waiting
        self.done = done
        self.updated = updated
    }

    func publish() {
        guard !updateQueued else { return }
        updateQueued = true
        DispatchQueue.main.async {
            self.updateQueued = false
            if !self.finished { self.updated() }
        }
    }

    func expire(after seconds: TimeInterval) {
        let limit = DispatchSource.makeTimerSource(queue: .main)
        limit.schedule(deadline: .now() + seconds)
        limit.setEventHandler { [weak self] in self?.finish() }
        limit.resume()
        self.limit = limit
    }

    func finish() {
        guard !finished else { return }
        finished = true
        limit?.cancel()
        limit = nil
        done()
    }

    func discovered() {
        if finished { updated() } else { publish() }
    }
}

package struct RunningApplicationSnapshot: Sendable {
    package let pid: pid_t
    package let bundleID: String?
    package let regular: Bool
    package let hidden: Bool

    package init(pid: pid_t, bundleID: String?, regular: Bool, hidden: Bool) {
        (self.pid, self.bundleID, self.regular, self.hidden) = (pid, bundleID, regular, hidden)
    }

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
