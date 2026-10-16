import AppKit
import SwiftUI


final class Feedback: ObservableObject {
    static let shared = Feedback()

    @Published var isOpen = false
    @Published var text = ""
    @Published var sending = false
    @Published var failed = false

    var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    func open() {
        failed = false
        isOpen = true
    }

    func close() { isOpen = false }

    func send() {
        guard canSend, let endpoint = Self.endpoint else { return }
        sending = true
        failed = false
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = body.split(separator: "\n").first.map(String.init) ?? ""
        let log = (try? String(contentsOf: Log.url, encoding: .utf8)) ?? ""
        Self.post(title: title, body: body, log: log, crash: nil, to: endpoint) { [weak self] ok in
            guard let self else { return }
            sending = false
            guard ok else { return failed = true }
            text = ""
            isOpen = false
            HUD.shared.show("Feedback sent", on: nil)
        }
    }


    static var endpoint: URL? {
        let v = (Bundle.main.object(forInfoDictionaryKey: "OuchReportURL") as? String)?.trimmingCharacters(in: .whitespaces)
        return v.flatMap(URL.init(string:))
    }

    static func sendCrash(_ crash: URL, done: @escaping (Bool) -> Void) {
        guard let endpoint else { return done(false) }
        let summary = CrashSummary(crash)
        let title = "Crash: " + (summary?.headline ?? crash.lastPathComponent)
        let body = "Ouch crashed\(summary.map { " at \($0.time)" } ?? ""). Sent on its own after the restart."
        post(title: title, body: body, log: Log.beforeLaunch(), crash: crash, to: endpoint, done: done)
    }

    private static func post(title: String, body: String, log: String, crash: URL?, to url: URL, done: @escaping (Bool) -> Void) {
        let title = String(title.prefix(110))
        var files: [(String, String)] = [("environment.md", environment(crash: crash.flatMap(CrashSummary.init)))]
        if !log.isEmpty {
            files.append(("ouch.log", log.split(separator: "\n", omittingEmptySubsequences: false).suffix(1500).joined(separator: "\n")))
        }
        if let conf = try? String(contentsOf: Config.url, encoding: .utf8) { files.append(("ouch.conf", conf)) }
        if let crash, let ips = try? String(contentsOf: crash, encoding: .utf8) { files.append(("crash.ips", ips)) }

        let boundary = "ouch-\(UUID().uuidString)"
        var data = Data()
        func part(_ header: String, _ content: String) {
            data.append(Data("--\(boundary)\r\n\(header)\r\n\r\n".utf8))
            data.append(Data(content.utf8))
            data.append(Data("\r\n".utf8))
        }
        for (name, value) in [("title", title), ("body", body), ("version", version)] {
            part("Content-Disposition: form-data; name=\"\(name)\"", value)
        }
        for (name, content) in files {
            let text = redact(content)
            part("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: text/plain",
                 text.count > 40000 ? "…\n" + text.suffix(40000) : text)
        }
        data.append(Data("--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: req, from: data) { reply, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let id = reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["id"] as? String
            DispatchQueue.main.async {
                if status == 200 {
                    Log.info("feedback: \(crash != nil ? "crash " : "")filed as \(id ?? "?")")
                    done(true)
                } else {
                    Log.info("feedback: not sent (\(status) \(error?.localizedDescription ?? ""))")
                    done(false)
                }
            }
        }.resume()
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    private static func redact(_ s: String) -> String {
        s.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private static func environment(crash: CrashSummary?) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let displays = NSScreen.screens.map { s in
            "\(s.localizedName) \(Int(s.frame.width))×\(Int(s.frame.height)) @\(Int(s.backingScaleFactor))x"
        }
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        var lines = [
            "# Environment",
            "",
            "- Ouch \(version)",
            "- macOS \(os)",
            "- Mac: \(hardwareModel()), \(arch())",
            "- Displays: \(displays.joined(separator: "; "))",
            "- Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")",
            "- Input Monitoring: \(Permissions.inputMonitoringGranted ? "granted" : "not granted")",
            "- Window manager running: \(WindowManager.shared.isStarted ? "yes" : "no")",
            "- Sent: \(date)",
        ]
        if let crash {
            lines.append("- Crash: \(crash.headline) at \(crash.time) (see crash.ips)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private static func arch() -> String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}


struct CrashSummary {
    let exception: String
    let frame: String?
    let date: Date

    var headline: String { [exception, frame].compactMap { $0 }.joined(separator: " in ") }
    var time: String { DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short) }

    init?(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let newline = text.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(with: Data(text[newline...].utf8)) as? [String: Any]
        else { return nil }
        let exc = body["exception"] as? [String: Any]
        let type = exc?["type"] as? String ?? "Crash"
        exception = (exc?["signal"] as? String).map { "\(type) (\($0))" } ?? type
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? 0
        let frames = faulting < threads.count ? threads[faulting]["frames"] as? [[String: Any]] ?? [] : []
        let ours = frames.first { f in
            let i = f["imageIndex"] as? Int ?? -1
            return i >= 0 && i < images.count && images[i]["name"] as? String == "ouch"
        }
        frame = (ours ?? frames.first)?["symbol"] as? String
        date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }
}

enum CrashWatch {
    private static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ouch")
    private static let marker = support.appendingPathComponent("running")
    private static let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    private static let seenKey = "lastCrashReportSeen"
    private static let pendingKey = "pendingCrashReport"

    private static var pending: URL? {
        guard let path = UserDefaults.standard.string(forKey: pendingKey), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        let previous = (try? fm.attributesOfItem(atPath: marker.path))?[.modificationDate] as? Date
        try? fm.removeItem(at: marker)
        fm.createFile(atPath: marker.path, contents: Data("\(getpid())".utf8))
        startWatchdog()

        let defaults = UserDefaults.standard
        if defaults.object(forKey: seenKey) == nil { defaults.set(Date(), forKey: seenKey) }
        if CommandLine.arguments.contains("--crash-report"), let latest = newestReport(after: .distantPast) {
            return found(latest)
        }
        guard let previous else { return pending.map(send) ?? () }
        Log.info("crash watch: the last run didn't exit cleanly")
        let since = max(previous, defaults.object(forKey: seenKey) as? Date ?? previous)
        poll(after: since, attempts: 12)
    }

    static func cleanExit() { try? FileManager.default.removeItem(at: marker) }

    private static func poll(after date: Date, attempts: Int) {
        if let report = newestReport(after: date) { return found(report) }
        guard attempts > 0 else { return Log.info("crash watch: no crash report (force quit or killed?)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { poll(after: date, attempts: attempts - 1) }
    }

    private static func found(_ report: URL) {
        UserDefaults.standard.set(Date(), forKey: seenKey)
        UserDefaults.standard.set(report.path, forKey: pendingKey)
        Log.info("crash watch: found \(report.lastPathComponent)")
        send(report)
    }

    private static func send(_ report: URL) {
        Feedback.sendCrash(report) { ok in
            if ok { UserDefaults.standard.removeObject(forKey: pendingKey) }
        }
    }

    private static func newestReport(after date: Date) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("ouch-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d > date
                else { return nil }
                return (url, d)
            }
            .max { $0.1 < $1.1 }?.0
    }

    private static func startWatchdog() {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return }
        let script = """
        start=$(date +%s)
        while kill -0 "$1" 2>/dev/null; do sleep 2; done
        [ "$(cat "$2" 2>/dev/null)" = "$1" ] || exit 0
        [ $(( $(date +%s) - start )) -lt 20 ] && exit 0
        i=0
        while [ $i -lt 60 ]; do
          i=$((i + 1))
          if [ -n "$(find "$4" -maxdepth 1 -name 'ouch-*.ips' -newer "$2" 2>/dev/null)" ]; then
            open "$3" --args --after-crash
            exit 0
          fi
          sleep 1
        done
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "ouch-watchdog", "\(getpid())", marker.path, app.path, reports.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { Log.info("crash watch: no watchdog: \(error.localizedDescription)") }
    }
}
