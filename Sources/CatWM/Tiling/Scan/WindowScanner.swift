import AppKit
import QuartzCore

final class WindowScanner {
    struct Job {
        let pid: pid_t
        let listWindows: Bool
        let known: [CGWindowID: Window]
        let fullscreen: Set<CGWindowID>
        let minimized: Set<CGWindowID>

        init(pid: pid_t, listWindows: Bool, known: [CGWindowID: Window]) {
            self.pid = pid; self.listWindows = listWindows; self.known = known
            fullscreen = Set(known.values.filter(\.fullscreen).map(\.id))
            minimized = Set(known.values.filter(\.minimized).map(\.id))
        }
    }

    struct Found {
        let element: AXUIElement
        let frame: CGRect
        let title: String?
        let resizable: Bool
        var frameRevision: Int?
    }

    struct AppScan {
        var readAt = Date()
        var listed: [CGWindowID] = []
        var found: [CGWindowID: Found] = [:]
        var fullscreen: Set<CGWindowID> = []
        var minimized: Set<CGWindowID> = []
        var gone: Set<CGWindowID> = []

        func hasNewWindows(comparedTo known: [CGWindowID: Window]) -> Bool {
            found.contains { known[$0.key] == nil && !$0.value.frame.isNull }
        }
    }

    static let deadline = 0.25

    private(set) var results: [pid_t: AppScan] = [:]
    private(set) var desktop = WindowServerObservation()
    private(set) var applications: [RunningApplicationSnapshot] = []
    private var observingDesktop = false
    private var pendingDesktop: (known: Set<CGWindowID>, done: () -> Void)?
    private let readDesktop: (Set<CGWindowID>) -> WindowServerObservation
    private let readApplications: () -> [RunningApplicationSnapshot]
    private(set) var lastScan: CFTimeInterval = 0
    private var busy: [pid_t: UUID] = [:]
    private var queues: [pid_t: DispatchQueue] = [:]
    private let read: (Job, (AppScan) -> Void) -> AppScan
    private let scanDeadline: TimeInterval

    init(read: @escaping (Job, (AppScan) -> Void) -> AppScan = WindowScanner.read,
         readDesktop: @escaping (Set<CGWindowID>) -> WindowServerObservation = WindowServerObservation.read,
         readApplications: @escaping () -> [RunningApplicationSnapshot] = RunningApplicationSnapshot.read,
         deadline: TimeInterval = WindowScanner.deadline) {
        self.read = read
        self.readDesktop = readDesktop
        self.readApplications = readApplications
        scanDeadline = deadline
    }

    func observeDesktop(known: Set<CGWindowID>, done: @escaping () -> Void) {
        guard !observingDesktop else {
            pendingDesktop = ((pendingDesktop?.known ?? []).union(known), done)
            return
        }
        observingDesktop = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, readDesktop, readApplications] in
            let observation = readDesktop(known)
            let applications = readApplications()
            DispatchQueue.main.async {
                guard let self else { return }
                self.desktop = observation
                self.applications = applications
                self.observingDesktop = false
                let pending = self.pendingDesktop
                self.pendingDesktop = nil
                done()
                if let pending { self.observeDesktop(known: pending.known, done: pending.done) }
            }
        }
    }

    func scan(_ jobs: [Job], done: @escaping () -> Void, updated: @escaping () -> Void) {
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
        guard waiting > 0 else { finish(); return }
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
                    if waiting == 0 { finish() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + scanDeadline) { finish() } // style-ok: timeout for a hung app
    }

    private func acceptDiscovery(_ scan: AppScan, pid: pid_t, token: UUID, notify: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.busy[pid] == token else { return }
            self.results[pid] = scan
            notify()
        }
    }

    func forget(_ pid: pid_t) {
        results[pid] = nil
        busy[pid] = nil
    }

    func terminated(_ pid: pid_t) {
        forget(pid)
        queues[pid] = nil
    }

    var queueCount: Int { queues.count }

    func run(_ pid: pid_t, _ work: @escaping () -> Void) {
        let queue = queues[pid] ?? DispatchQueue(label: "catwm.scan.\(pid)", qos: .userInitiated)
        queues[pid] = queue
        queue.async(execute: work)
    }
}

struct RunningApplicationSnapshot {
    let pid: pid_t
    let bundleID: String?
    let regular: Bool
    let hidden: Bool

    static func read() -> [Self] {
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
