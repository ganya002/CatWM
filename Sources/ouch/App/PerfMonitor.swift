// App: detects slow animations and main-thread hangs, and reports them through the report relay.
import AppKit
import CryptoKit
import QuartzCore

/// Watches Ouch's own frame pacing while it animates (other apps' windows and its own panels), the AX
/// cost per app, and main-thread hangs. Every event goes to the log. With `perf-reports = true` the
/// repeat offenders also go to the relay's `/perf` route, which files or updates one Linear issue per
/// fingerprint. The payload holds numbers and bundle IDs only: no window titles, paths or names.
enum PerfMonitor {
    /// A slow app seen during a window move.
    struct SlowApp {
        let bundle: String
        let stepMs: Double
        let skipped: Double // share of frames dropped because the app was still busy
    }

    fileprivate struct Event {
        var kind: String
        var frames = 0, durationMs = 0.0, p95Ms = 0.0, slowShare = 0.0, hz = 60
        var app: SlowApp?
        var hangMs = 0.0
        var tags: Set<String> = []
    }

    // MARK: Thresholds

    private static let settle = 30.0 // seconds after launch before anything counts
    private static let skipFirstRuns = 2 // cold caches
    private static let hangLine = 0.25, severeHang = 1.0
    private static let slowAppStepMs = 24.0, slowAppSkipped = 0.5
    private static let eventsNeeded = 5, severeEventsNeeded = 2
    private static let cooldown = 7 * 86400.0, perWeek = 5

    private static let launched = CACurrentMediaTime()
    private static var seen: [String: Int] = [:]
    private static var active: [FrameRun] = []
    private static var asleep = false
    private static var busyAt: CFTimeInterval = 0
    private static var uploading = false

    static var enabled: Bool { WindowManager.shared.config.perfReports }

    // MARK: Entry points

    /// Starts the frame clock for one animation. Call `end` when it is over.
    static func begin(_ kind: String) -> FrameRun? {
        guard !asleep, let screen = NSScreen.main else { return nil }
        let run = FrameRun(kind: kind, screen: screen)
        active.append(run)
        return run
    }

    /// Measures a SwiftUI or layer animation that has no completion handler.
    static func track(_ kind: String, for seconds: Double) {
        guard let run = begin(kind) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { run.end() }
    }

    static func start() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, value) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
                              (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in asleep = value }
        }
        // The run loop is busy from `afterWaiting` to `beforeWaiting`; a long stretch is a hang.
        let activities = CFRunLoopActivity([.afterWaiting, .beforeWaiting]).rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { busyAt = now; return }
            guard busyAt > 0 else { return }
            let busy = now - busyAt
            busyAt = 0
            if busy > hangLine { hung(busy) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    // MARK: Verdicts

    fileprivate static func finish(_ run: FrameRun, apps: [SlowApp]) {
        active.removeAll { $0 === run }
        seen[run.kind, default: 0] += 1
        guard seen[run.kind]! > skipFirstRuns, !run.tags.contains("gap") else { return }
        let slowApp = apps.filter { $0.stepMs > slowAppStepMs || $0.skipped > slowAppSkipped }
            .max { $0.stepMs < $1.stepMs }
        let stats = run.stats
        let framesSlow = stats.map { $0.frames >= 12 && $0.duration >= 0.15 && ($0.p95 > $0.period * 2 || $0.slowShare > 0.10) } ?? false
        guard framesSlow || slowApp != nil else { return }

        var tags = run.tags
        let load = { () -> Double in var l = [0.0]; getloadavg(&l, 1); return l[0] }()
        if load > Double(ProcessInfo.processInfo.activeProcessorCount) { tags.insert("load") }
        var event = Event(kind: run.kind, hz: run.hz, app: slowApp, tags: tags)
        if let stats {
            event.frames = stats.frames
            event.durationMs = stats.duration * 1000
            event.p95Ms = stats.p95 * 1000
            event.slowShare = stats.slowShare
        }
        record(event)
    }

    private static func hung(_ seconds: Double) {
        guard !asleep else { return }
        var event = Event(kind: "hang", hangMs: seconds * 1000)
        event.kind = "hang:" + (active.map(\.kind).sorted().first ?? "idle")
        record(event)
    }

    private static func record(_ event: Event) {
        let text = String(format: "perf: %@ frames %d p95 %.1fms slow %.0f%% hang %.0fms app %@ tags %@", event.kind, event.frames,
                          event.p95Ms, event.slowShare * 100, event.hangMs, event.app?.bundle ?? "-", event.tags.sorted().joined(separator: ","))
        Log.info(text)
        // A hot or loaded machine is slow for reasons that are not Ouch's. Keep the log line, skip the report.
        guard enabled, event.tags.isDisjoint(with: ["thermal", "lowpower", "load"]),
              CACurrentMediaTime() - launched > settle, let endpoint = endpoint else { return }
        let fp = fingerprint(event)
        let defaults = UserDefaults.standard
        var counts = defaults.dictionary(forKey: "perf.counts") as? [String: Int] ?? [:]
        counts[fp, default: 0] += 1
        defaults.set(counts, forKey: "perf.counts")

        let severe = event.hangMs > severeHang * 1000
        guard counts[fp]! >= (severe ? severeEventsNeeded : eventsNeeded), !uploading else { return }
        let now = Date().timeIntervalSince1970
        let sentAt = defaults.dictionary(forKey: "perf.sentAt") as? [String: Double] ?? [:]
        var log = (defaults.array(forKey: "perf.sentLog") as? [Double] ?? []).filter { now - $0 < 7 * 86400 }
        guard now - (sentAt[fp] ?? 0) > cooldown, log.count < perWeek,
              now - (log.last ?? 0) > 86400, now > defaults.double(forKey: "perf.backoffUntil") else { return }

        uploading = true
        upload(event, fingerprint: fp, count: counts[fp]!, to: endpoint) { ok in
            uploading = false
            if ok {
                log.append(now)
                var sent = sentAt
                sent[fp] = now
                counts[fp] = 0
                defaults.set(sent, forKey: "perf.sentAt")
                defaults.set(log, forKey: "perf.sentLog")
                defaults.set(counts, forKey: "perf.counts")
            } else {
                defaults.set(now + 3600, forKey: "perf.backoffUntil")
            }
        }
    }

    // MARK: Upload

    /// The relay's `/perf` route, next to `/report`.
    private static var endpoint: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "OuchReportURL") as? String, s.hasSuffix("/report") else { return nil }
        return URL(string: String(s.dropLast("report".count)) + "perf")
    }

    private static func fingerprint(_ e: Event) -> String {
        let v = version.split(separator: ".").prefix(2).joined(separator: ".")
        let magnitude = e.hangMs > 0 ? e.hangMs / 250 : e.p95Ms / 8
        let bucket = Int(log2(max(1, magnitude)))
        let raw = [e.kind, v, "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)", hardware,
                   e.app?.bundle ?? "-", "\(bucket)"].joined(separator: "|")
        return SHA256.hash(data: Data(raw.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private static func upload(_ e: Event, fingerprint fp: String, count: Int, to url: URL, done: @escaping (Bool) -> Void) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let config = WindowManager.shared.config
        var body: [String: Any] = [
            "fingerprint": fp, "kind": e.kind, "version": version, "os": "\(os.majorVersion).\(os.minorVersion)",
            "hardware": hardware, "hz": e.hz, "displays": NSScreen.screens.count, "curve": config.animationCurve.name,
            "durationMs": Int(config.animationDuration * 1000), "count": count,
            "frames": e.frames, "p95Ms": (e.p95Ms * 10).rounded() / 10, "slowShare": (e.slowShare * 100).rounded() / 100,
            "hangMs": Int(e.hangMs), "tags": e.tags.sorted(),
        ]
        if let a = e.app { body["app"] = ["bundle": a.bundle, "stepMs": (a.stepMs * 10).rounded() / 10, "skipped": (a.skipped * 100).rounded() / 100] }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return done(false) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: req, from: data) { reply, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let id = reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["id"] as? String
            DispatchQueue.main.async {
                Log.info("perf: \(fp) \(status == 200 ? "filed as \(id ?? "?")" : "not sent (\(status))")")
                done(status == 200)
            }
        }.resume()
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private static let hardware: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }()
}

// MARK: - Frame run

/// The frame clock for one animation. A display link on the screen counts how late each frame comes;
/// a frame that takes more than 1.5 display periods is slow.
final class FrameRun: NSObject {
    struct Stats { let frames: Int; let duration, period, p95, slowShare: Double }

    let kind: String
    fileprivate(set) var tags: Set<String> = []
    let hz: Int
    private var link: CADisplayLink?
    private let started = CACurrentMediaTime()
    private var last = 0.0, period = 1.0 / 60
    private var gaps: [Double] = []
    private var ended = false

    fileprivate init(kind: String, screen: NSScreen) {
        self.kind = kind
        hz = screen.maximumFramesPerSecond
        super.init()
        let info = ProcessInfo.processInfo
        if info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { tags.insert("thermal") }
        if info.isLowPowerModeEnabled { tags.insert("lowpower") }
        link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func frame(_ l: CADisplayLink) {
        period = max(0.001, l.targetTimestamp - l.timestamp)
        defer { last = l.timestamp }
        guard last > 0 else { return }
        let dt = l.timestamp - last
        if dt > 0.5 { tags.insert("gap") } else { gaps.append(dt) } // a sleep or a hang, judged on its own
    }

    var stats: Stats? {
        guard !gaps.isEmpty else { return nil }
        let s = gaps.sorted()
        return Stats(frames: gaps.count, duration: CACurrentMediaTime() - started, period: period,
                     p95: s[min(s.count - 1, Int(Double(s.count) * 0.95))],
                     slowShare: Double(gaps.filter { $0 > period * 1.5 }.count) / Double(gaps.count))
    }

    /// Stops the clock and judges the run. `apps` is the AX cost per app, for window moves.
    func end(apps: [PerfMonitor.SlowApp] = []) {
        guard !ended else { return }
        ended = true
        link?.invalidate()
        link = nil
        PerfMonitor.finish(self, apps: apps)
    }
}
