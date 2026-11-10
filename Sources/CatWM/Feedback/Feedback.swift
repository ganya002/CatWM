import AppKit
import CatWMKit
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
        let report = Report(title: title, body: body, log: log, crash: nil)
        Self.post(report, to: endpoint) { [weak self] success in
            guard let self else { return }
            finishSend(body: body, success: success)
        }
    }

    func finishSend(body: String, success: Bool) {
        sending = false
        guard success else { return failed = true }
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == body {
            text = ""
            isOpen = false
        }
        HUD.shared.show("Feedback sent", on: nil)
    }

    static var endpoint: URL? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "CatWMReportURL") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return value.flatMap(URL.init(string:))
    }

    static func sendCrash(_ crash: URL, done: @escaping (Bool) -> Void) {
        guard let endpoint else { return done(false) }
        let summary = CrashSummary(crash)
        let title = "Crash: " + (summary?.headline ?? crash.lastPathComponent)
        let body = "CatWM crashed\(summary.map { " at \($0.time)" } ?? ""). Sent on its own after the restart."
        post(Report(title: title, body: body, log: Log.beforeLaunch(), crash: crash), to: endpoint, done: done)
    }

    private struct Report {
        let title: String
        let body: String
        let log: String
        let crash: URL?
    }

    private static func post(_ report: Report, to url: URL, done: @escaping (Bool) -> Void) {
        let title = String(report.title.prefix(110))
        let body = report.body
        let log = report.log
        let crash = report.crash
        var files: [(String, String)] = [("environment.md", environment(crash: crash.flatMap(CrashSummary.init)))]
        if !log.isEmpty {
            let tail = log.split(separator: "\n", omittingEmptySubsequences: false).suffix(1500)
            files.append(("CatWM.log", tail.joined(separator: "\n")))
        }
        let store = ConfigStore.shared
        let configs = store.isScript ? [store.scriptURL, store.overridesURL] : [Config.url]
        for url in configs {
            if let text = try? String(contentsOf: url, encoding: .utf8) { files.append((url.lastPathComponent, text)) }
        }
        if let crash, let ips = try? String(contentsOf: crash, encoding: .utf8) { files.append(("crash.ips", ips)) }

        let boundary = "catwm-\(UUID().uuidString)"
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

    private static func redact(_ text: String) -> String {
        text.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private static func environment(crash: CrashSummary?) -> String {
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let displays = NSScreen.screens.map { screen in
            "\(screen.localizedName) \(Int(screen.frame.width))×\(Int(screen.frame.height)) "
                + "@\(Int(screen.backingScaleFactor))x"
        }
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        var lines = [
            "# Environment",
            "",
            "- CatWM \(version)",
            "- macOS \(system)",
            "- Mac: \(hardwareModel()), \(arch())",
            "- Displays: \(displays.joined(separator: "; "))",
            "- Accessibility: \(Permission.accessibility.isGranted ? "granted" : "not granted")",
            "- Input Monitoring: \(Permission.inputMonitoring.isGranted ? "granted" : "not granted")",
            "- Screen Recording: \(Permission.screenRecording.isGranted ? "granted" : "not granted")",
            "- Window manager running: \(WindowManager.shared.isStarted ? "yes" : "no")",
            "- Sent: \(date)"
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
