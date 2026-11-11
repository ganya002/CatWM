import AppKit
import CatWMKit
import SwiftUI

@MainActor enum CrashWatch {
    private static let marker = Instance.supportFolder.appendingPathComponent("running")
    private static let reports = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports")
    private static let seenKey = "lastCrashReportSeen"
    private static let pendingKey = "pendingCrashReport"

    private static var pending: URL? {
        guard let path = Instance.defaults.string(forKey: pendingKey),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func start() {
        guard Instance.paths.mayRelaunchItself else { return }
        let files = FileManager.default
        Log.attempt("create crash marker folder") {
            try files.createDirectory(at: Instance.supportFolder, withIntermediateDirectories: true)
        }
        let previous = (try? files.attributesOfItem(atPath: marker.path))?[.modificationDate] as? Date
        try? files.removeItem(at: marker)
        files.createFile(atPath: marker.path, contents: Data("\(getpid())".utf8))
        startWatchdog()

        let defaults = Instance.defaults
        if defaults.object(forKey: seenKey) == nil { defaults.set(Date(), forKey: seenKey) }
        if LaunchFlag.crashReport.isSet, let latest = newestReport(after: .distantPast) {
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
        Instance.defaults.set(Date(), forKey: seenKey)
        Instance.defaults.set(report.path, forKey: pendingKey)
        Log.info("crash watch: found \(report.lastPathComponent)")
        send(report)
    }

    private static func send(_ report: URL) {
        Feedback.sendCrash(report) { success in
            if success { Instance.defaults.removeObject(forKey: pendingKey) }
        }
    }

    private static func newestReport(after date: Date) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("CatWM-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modified = values?.contentModificationDate, modified > date else { return nil }
                return (url, modified)
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
          if [ -n "$(find "$4" -maxdepth 1 -name 'CatWM-*.ips' -newer "$2" 2>/dev/null)" ]; then
            open "$3" --args \(LaunchFlag.afterCrash.rawValue)
            exit 0
          fi
          sleep 1
        done
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "catwm-watchdog", "\(getpid())", marker.path, app.path, reports.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { Log.info("crash watch: no watchdog: \(error.localizedDescription)") }
    }
}

struct CrashSummary {
    let exception: String
    let frame: String?
    let date: Date

    var headline: String { [exception, frame].compactMap(\.self).joined(separator: " in ") }
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
        let ours = frames.first { frame in
            let i = frame["imageIndex"] as? Int ?? -1
            return i >= 0 && i < images.count && images[i]["name"] as? String == "CatWM"
        }
        frame = (ours ?? frames.first)?["symbol"] as? String
        date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }
}
