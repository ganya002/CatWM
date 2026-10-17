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
        var frameRevision: Int? = nil
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
    private(set) var lastScan: CFTimeInterval = 0
    private var busy: [pid_t: UUID] = [:]
    private var queues: [pid_t: DispatchQueue] = [:]
    private let read: (Job) -> AppScan

    init(read: @escaping (Job) -> AppScan = WindowScanner.read) {
        self.read = read
    }

    func observeDesktop(known: Set<CGWindowID>, done: @escaping () -> Void) {
        guard !observingDesktop else { return }
        observingDesktop = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let observation = WindowServerObservation.read(known: known)
            DispatchQueue.main.async {
                guard let self else { return }
                self.desktop = observation
                self.observingDesktop = false
                done()
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
                let r = read(job)
                let elapsed = CACurrentMediaTime() - start
                DispatchQueue.main.async {
                    guard let self else { return }
                    waiting -= 1
                    if self.busy[job.pid] == token {
                        self.busy[job.pid] = nil
                        self.results[job.pid] = r
                        Log.debug(String(format: "scan: pid %d windows %d %.1fms", job.pid, r.listed.count, elapsed * 1000))
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
        if queues[pid] == nil { queues[pid] = DispatchQueue(label: "ouch.scan.\(pid)", qos: .userInitiated) }
        queues[pid]!.async(execute: work)
    }

    private static func read(_ job: Job) -> AppScan {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var s = AppScan()
        if job.listWindows {
            for el in axApp(job.pid).elements(kAXWindowsAttribute) {
                guard let id = el.windowID else { continue }
                s.listed.append(id)
                AXUIElementSetMessagingTimeout(el, axTimeout)
                if let known = job.known[id] {
                    readKnown(known, into: &s)
                    continue
                }
                if el.bool("AXFullScreen") == true { s.fullscreen.insert(id) }
                if el.bool(kAXMinimizedAttribute) == true { s.minimized.insert(id) }
                guard el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      !s.minimized.contains(id), !s.fullscreen.contains(id) else { continue }
                s.found[id] = Found(element: el, frame: el.frame, title: el.string(kAXTitleAttribute),
                                    resizable: el.isSettable(kAXSizeAttribute))
            }
        }
        let listed = Set(s.listed)
        for (id, w) in job.known where !listed.contains(id) {
            var role: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(w.element, kAXRoleAttribute as CFString, &role)
            if result == .invalidUIElement { s.gone.insert(id) }
            else if result == .success { readKnown(w, into: &s) }
        }
        return s
    }

    private static func readKnown(_ w: Window, into scan: inout AppScan) {
        let revision = w.frameRevision
        if w.isNativeFullscreen { scan.fullscreen.insert(w.id) }
        if w.element.bool(kAXMinimizedAttribute) == true { scan.minimized.insert(w.id) }
        scan.found[w.id] = Found(element: w.element, frame: w.element.frame, title: w.element.string(kAXTitleAttribute),
                                 resizable: w.element.isSettable(kAXSizeAttribute), frameRevision: revision)
    }
}
