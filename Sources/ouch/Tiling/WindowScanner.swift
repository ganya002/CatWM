// Tiling: reads each app's windows through AX off the main thread, one serial queue per app.
import AppKit
import QuartzCore

/// How long one AX call to another app may take before it fails. The default is six seconds, and an app
/// that is busy (Electron apps, kitty under load) then holds the thread that asked for that long.
let axTimeout: Float = 0.3

/// An app's AX element with a short messaging timeout (see `axTimeout`).
func axApp(_ pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, axTimeout)
    return app
}

/// Discovers windows for `refresh`. Each app gets its own serial queue, so a slow app holds up only
/// its own scan, never the main thread or the other apps. The main thread starts a scan, then lays out
/// with the results when all apps answer or when the deadline comes, whichever is first. An app that
/// is late keeps its last result, and its new result starts one more refresh when it comes.
final class WindowScanner {
    /// What a scan asks of one app.
    struct Job {
        let pid: pid_t
        let listWindows: Bool        // the app has windows on screen: read its window list
        let known: [CGWindowID: Window] // its windows we already manage
    }

    /// A window that was not managed yet when the scan read it.
    struct Found {
        let element: AXUIElement
        let frame: CGRect
        let title: String?
        let resizable: Bool
    }

    /// One app's answer.
    struct AppScan {
        var listed: [CGWindowID] = []          // every window in its AX window list, in that order
        var found: [CGWindowID: Found] = [:]   // standard windows not managed yet (not minimized or fullscreen)
        var fullscreen: Set<CGWindowID> = []   // managed windows in native fullscreen
        var gone: Set<CGWindowID> = []         // managed windows that are not in the list and do not answer AX
    }

    /// When the main thread stops waiting for apps that are late.
    static let deadline = 0.25

    // Main thread only.
    private(set) var results: [pid_t: AppScan] = [:]
    private(set) var lastScan: CFTimeInterval = 0
    private var busy: Set<pid_t> = []
    private var queues: [pid_t: DispatchQueue] = [:]

    /// Reads every app in `jobs`, then calls `done` on the main thread. An app whose previous scan is
    /// still running is not asked again: its last result stays. `late` is called on the main thread
    /// when an app answers after `done` was called.
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

    /// Runs on the app's queue. Reading the frames here also fills each window's cached frame.
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
