import AppKit
import CatWMKit
import CryptoKit
import QuartzCore

final class PerfMonitor {
    static let shared = PerfMonitor()

    private struct Event {
        var kind: String
        var frames = 0, durationMs = 0.0, p95Ms = 0.0, slowShare = 0.0, refreshRate = 60
        var app: SlowApp?
        var hangMs = 0.0
        var tags: Set<String> = []
    }

    private static let settle = 30.0
    private static let skipFirstRuns = 2
    private static let hangLine = 0.25, severeHang = 1.0
    private static let slowAppStepMs = 24.0, slowAppSkipped = 0.5
    private static let eventsNeeded = 5, severeEventsNeeded = 2
    private static let cooldown = 7 * 86400.0, perWeek = 5

    private static let launched = CACurrentMediaTime()
    private var seen: [String: Int] = [:]
    private var active: [FrameRun] = []
    private var asleep = false
    private var busyAt: CFTimeInterval = 0
    private var uploading = false
    private var observers: [NSObjectProtocol] = []

    var enabled: Bool { !Instance.isNamed && WindowManager.shared.config.perfReports }

    func begin(_ kind: String) -> FrameRun? {
        guard !asleep, let screen = NSScreen.main else { return nil }
        let run = FrameRun(kind: kind, screen: screen)
        active.append(run)
        return run
    }

    func track(_ kind: String, for seconds: Double) {
        guard let run = begin(kind) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { run.end() }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let changes = [(NSWorkspace.screensDidSleepNotification, true),
                       (NSWorkspace.screensDidWakeNotification, false),
                       (NSWorkspace.sessionDidResignActiveNotification, true),
                       (NSWorkspace.sessionDidBecomeActiveNotification, false)]
        for (name, value) in changes {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [unowned self] _ in
                asleep = value
            })
        }
        let activities = CFRunLoopActivity([.afterWaiting, .beforeWaiting]).rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [unowned self] _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { busyAt = now; return }
            guard busyAt > 0 else { return }
            let busy = now - busyAt
            busyAt = 0
            if busy > Self.hangLine { hung(busy) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func finish(_ run: FrameRun, apps: [SlowApp]) {
        active.removeAll { $0 === run }
        let runs = seen[run.kind, default: 0] + 1
        seen[run.kind] = runs
        guard runs > Self.skipFirstRuns, !run.tags.contains("gap") else { return }
        let slowApp = apps.filter { $0.stepMs > Self.slowAppStepMs || $0.skipped > Self.slowAppSkipped }
            .max { $0.stepMs < $1.stepMs }
        let stats = run.stats
        let framesSlow = stats.map {
            $0.frames >= 12 && $0.duration >= 0.15 && ($0.p95 > $0.period * 2 || $0.slowShare > 0.10)
        } ?? false
        guard framesSlow || slowApp != nil else { return }

        var tags = run.tags
        let load = { () -> Double in var averages = [0.0]; getloadavg(&averages, 1); return averages[0] }()
        if load > Double(ProcessInfo.processInfo.activeProcessorCount) { tags.insert("load") }
        var event = Event(kind: run.kind, refreshRate: run.refreshRate, app: slowApp, tags: tags)
        if let stats {
            event.frames = stats.frames
            event.durationMs = stats.duration * 1000
            event.p95Ms = stats.p95 * 1000
            event.slowShare = stats.slowShare
        }
        record(event)
    }

    private func hung(_ seconds: Double) {
        guard !asleep else { return }
        var event = Event(kind: "hang", hangMs: seconds * 1000)
        event.kind = "hang:" + (active.map(\.kind).min() ?? "idle")
        record(event)
    }

    private func record(_ event: Event) {
        let text = String(format: "perf: %@ frames %d p95 %.1fms slow %.0f%% hang %.0fms app %@ tags %@",
                          event.kind, event.frames, event.p95Ms, event.slowShare * 100, event.hangMs,
                          event.app?.bundle ?? "-", event.tags.sorted().joined(separator: ","))
        Log.info(text)
        guard enabled, event.tags.isDisjoint(with: ["thermal", "lowpower", "load"]),
              CACurrentMediaTime() - Self.launched > Self.settle, let endpoint = Self.endpoint else { return }
        let digest = Self.fingerprint(event)
        let defaults = Instance.defaults
        var counts = defaults.dictionary(forKey: DefaultsKey.perfCounts) as? [String: Int] ?? [:]
        let count = counts[digest, default: 0] + 1
        counts[digest] = count
        defaults.set(counts, forKey: DefaultsKey.perfCounts)

        let severe = event.hangMs > Self.severeHang * 1000
        guard count >= (severe ? Self.severeEventsNeeded : Self.eventsNeeded), !uploading else { return }
        let now = Date().timeIntervalSince1970
        let sentAt = defaults.dictionary(forKey: DefaultsKey.perfSentAt) as? [String: Double] ?? [:]
        var log = (defaults.array(forKey: DefaultsKey.perfSentLog) as? [Double] ?? []).filter { now - $0 < 7 * 86400 }
        guard now - (sentAt[digest] ?? 0) > Self.cooldown, log.count < Self.perWeek,
              now - (log.last ?? 0) > 86400, now > defaults.double(forKey: DefaultsKey.perfBackoffUntil) else { return }

        uploading = true
        Self.upload(event, fingerprint: digest, count: count, to: endpoint) { succeeded in
            self.uploading = false
            if succeeded {
                log.append(now)
                var sent = sentAt
                sent[digest] = now
                counts[digest] = 0
                defaults.set(sent, forKey: DefaultsKey.perfSentAt)
                defaults.set(log, forKey: DefaultsKey.perfSentLog)
                defaults.set(counts, forKey: DefaultsKey.perfCounts)
            } else {
                defaults.set(now + 3600, forKey: DefaultsKey.perfBackoffUntil)
            }
        }
    }

    private static var endpoint: URL? {
        guard let reportURL = Bundle.main.object(forInfoDictionaryKey: "CatWMReportURL") as? String,
              reportURL.hasSuffix("/report") else { return nil }
        return URL(string: String(reportURL.dropLast("report".count)) + "perf")
    }

    private static func fingerprint(_ event: Event) -> String {
        let minorVersion = version.split(separator: ".").prefix(2).joined(separator: ".")
        let magnitude = event.hangMs > 0 ? event.hangMs / 250 : event.p95Ms / 8
        let bucket = Int(log2(max(1, magnitude)))
        let raw = [event.kind, minorVersion, "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)", hardware,
                   event.app?.bundle ?? "-", "\(bucket)"].joined(separator: "|")
        return SHA256.hash(data: Data(raw.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private static func upload(_ event: Event, fingerprint digest: String, count: Int, to url: URL,
                               done: @escaping (Bool) -> Void) {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let config = WindowManager.shared.config
        var body: [String: Any] = [
            "fingerprint": digest, "kind": event.kind, "version": version,
            "os": "\(system.majorVersion).\(system.minorVersion)",
            "hardware": hardware, "hz": event.refreshRate, "displays": NSScreen.screens.count,
            "curve": config.animationCurve.name,
            "durationMs": Int(config.animationDuration * 1000), "count": count,
            "frames": event.frames, "p95Ms": (event.p95Ms * 10).rounded() / 10,
            "slowShare": (event.slowShare * 100).rounded() / 100,
            "hangMs": Int(event.hangMs), "tags": event.tags.sorted()
        ]
        if let app = event.app {
            body["app"] = ["bundle": app.bundle, "stepMs": (app.stepMs * 10).rounded() / 10,
                           "skipped": (app.skipped * 100).rounded() / 100]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return done(false) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: req, from: data) { reply, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let id = reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["id"] as? String
            DispatchQueue.main.async {
                Log.info("perf: \(digest) \(status == 200 ? "filed as \(id ?? "?")" : "not sent (\(status))")")
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
