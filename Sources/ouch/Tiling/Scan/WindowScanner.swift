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
    }

    struct AppScan {
        var listed: [CGWindowID] = []
        var found: [CGWindowID: Found] = [:]
        var fullscreen: Set<CGWindowID> = []
        var gone: Set<CGWindowID> = []
    }

    static let deadline = 0.25

    private(set) var results: [pid_t: AppScan] = [:]
    private(set) var lastScan: CFTimeInterval = 0
    private var busy: Set<pid_t> = []
    private var queues: [pid_t: DispatchQueue] = [:]

    func scan(_ jobs: [Job], done: @escaping () -> Void, late: @escaping () -> Void) {
        lastScan = CACurrentMediaTime()
        let running = Set(jobs.map(\.pid))
        results = results.filter { running.contains($0.key) }
        let asked = jobs.filter { !busy.contains($0.pid) }
        var waiting = asked.count
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            done()
        }
        guard waiting > 0 else { finish(); return }
        for job in asked {
            busy.insert(job.pid)
            queue(job.pid).async { [weak self] in
                let r = Self.read(job)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busy.remove(job.pid)
                    self.results[job.pid] = r
                    waiting -= 1
                    if finished { late() } else if waiting == 0 { finish() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline) { finish() }
    }

    func forget(_ pid: pid_t) { results[pid] = nil }

    private func queue(_ pid: pid_t) -> DispatchQueue {
        if let q = queues[pid] { return q }
        let q = DispatchQueue(label: "ouch.scan.\(pid)", qos: .userInitiated)
        queues[pid] = q
        return q
    }

    private static func read(_ job: Job) -> AppScan {
        var s = AppScan()
        if job.listWindows {
            for el in axApp(job.pid).elements(kAXWindowsAttribute) {
                guard let id = el.windowID else { continue }
                s.listed.append(id)
                if let w = job.known[id] {
                    if w.isNativeFullscreen { s.fullscreen.insert(id) }
                    _ = w.frame
                    continue
                }
                AXUIElementSetMessagingTimeout(el, axTimeout)
                guard el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      el.bool(kAXMinimizedAttribute) != true, el.bool("AXFullScreen") != true else { continue }
                s.found[id] = Found(element: el, frame: el.frame, title: el.string(kAXTitleAttribute),
                                    resizable: el.isSettable(kAXSizeAttribute))
            }
        }
        let listed = Set(s.listed)
        for (id, w) in job.known where !listed.contains(id) && !w.isValid { s.gone.insert(id) }
        return s
    }
}
