import AppKit
import QuartzCore

final class WindowScanner {
    struct Job {
        let pid: pid_t
        let listWindows: Bool
        let known: [CGWindowID: Window]
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
    }

    static let deadline = 0.25

    private(set) var results: [pid_t: AppScan] = [:]
    private(set) var desktop = WindowServerObservation()
    private var observingDesktop = false
    private var pendingDesktop: (known: Set<CGWindowID>, done: () -> Void)?
    private let readDesktop: (Set<CGWindowID>) -> WindowServerObservation
    private(set) var lastScan: CFTimeInterval = 0
    private var busy: [pid_t: UUID] = [:]
    private var queues: [pid_t: DispatchQueue] = [:]
    private let read: (Job) -> AppScan

    init(read: @escaping (Job) -> AppScan = WindowScanner.read,
         readDesktop: @escaping (Set<CGWindowID>) -> WindowServerObservation = WindowServerObservation.read) {
        self.read = read
        self.readDesktop = readDesktop
    }

    func observeDesktop(known: Set<CGWindowID>, done: @escaping () -> Void) {
        guard !observingDesktop else {
            pendingDesktop = ((pendingDesktop?.known ?? []).union(known), done)
            return
        }
        observingDesktop = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, readDesktop] in
            let observation = readDesktop(known)
            DispatchQueue.main.async {
                guard let self else { return }
                self.desktop = observation
                self.observingDesktop = false
                let pending = self.pendingDesktop
                self.pendingDesktop = nil
                done()
                if let pending { self.observeDesktop(known: pending.known, done: pending.done) }
            }
        }
    }

    func scan(_ jobs: [Job], done: @escaping () -> Void, late: @escaping () -> Void) {
        lastScan = CACurrentMediaTime()
        let running = Set(jobs.map(\.pid))
        for pid in results.keys where !running.contains(pid) { forget(pid) }
        let asked = jobs.filter { busy[$0.pid] == nil }
        var waiting = asked.count
        var finished = false
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
                let scan = read(job)
                let elapsed = CACurrentMediaTime() - start
                DispatchQueue.main.async {
                    guard let self else { return }
                    waiting -= 1
                    if self.busy[job.pid] == token {
                        self.busy[job.pid] = nil
                        self.results[job.pid] = scan
                        Log.debug(String(format: "scan: pid %d windows %d %.1fms",
                                         job.pid, scan.listed.count, elapsed * 1000))
                        if finished { late() }
                    }
                    if waiting == 0 { finish() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline) { finish() }
    }

    func forget(_ pid: pid_t) {
        results[pid] = nil
        busy[pid] = nil
    }

    func run(_ pid: pid_t, _ work: @escaping () -> Void) {
        let queue = queues[pid] ?? DispatchQueue(label: "ouch.scan.\(pid)", qos: .userInitiated)
        queues[pid] = queue
        queue.async(execute: work)
    }

    private static func read(_ job: Job) -> AppScan {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var scan = AppScan()
        if job.listWindows {
            var seen = Set<CGWindowID>()
            for element in listedElements(axApp(job.pid)) {
                guard let id = element.windowID, seen.insert(id).inserted else { continue }
                scan.listed.append(id)
                AXUIElementSetMessagingTimeout(element, axTimeout)
                if let known = job.known[id] {
                    readKnown(known, into: &scan)
                    continue
                }
                if element.flag("AXFullScreen") { scan.fullscreen.insert(id) }
                if element.flag(kAXMinimizedAttribute) { scan.minimized.insert(id) }
                guard element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      !scan.minimized.contains(id) else { continue }
                scan.found[id] = Found(element: element, frame: element.frame,
                                       title: element.string(kAXTitleAttribute),
                                       resizable: element.isSettable(kAXSizeAttribute))
            }
        }
        let listed = Set(scan.listed)
        for (id, window) in job.known where !listed.contains(id) {
            var role: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(window.element, kAXRoleAttribute as CFString, &role)
            if result == .invalidUIElement {
                scan.gone.insert(id)
            } else if result == .success {
                readKnown(window, into: &scan)
            }
        }
        return scan
    }

    private static func listedElements(_ app: AXUIElement) -> [AXUIElement] {
        let listed = app.elements(kAXWindowsAttribute)
        if !listed.isEmpty { return listed }
        return app.elements(kAXChildrenAttribute)
            + [app.element(kAXMainWindowAttribute), app.element(kAXFocusedWindowAttribute)].compactMap(\.self)
    }

    private static func readKnown(_ window: Window, into scan: inout AppScan) {
        let revision = window.frameRevision
        if window.isNativeFullscreen { scan.fullscreen.insert(window.id) }
        if window.element.flag(kAXMinimizedAttribute) { scan.minimized.insert(window.id) }
        scan.found[window.id] = Found(element: window.element, frame: window.element.frame,
                                      title: window.element.string(kAXTitleAttribute),
                                      resizable: window.element.isSettable(kAXSizeAttribute), frameRevision: revision)
    }
}
