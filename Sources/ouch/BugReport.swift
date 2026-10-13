import AppKit

// Bug reports. Each one is a folder of plain files (environment, log, config, crash report and the
// instructions for an agent), so an agent reads them by path instead of being handed a wall of
// pasted context. The finished report.md goes out by email to the Linear intake address.

struct BugReport {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ouch/Reports")
    /// Older reports are pruned when a new one is made.
    private static let keep = 20

    let dir: URL
    var id: String { dir.lastPathComponent }
    var prompt: URL { dir.appendingPathComponent("prompt.md") }
    var report: URL { dir.appendingPathComponent("report.md") }
    var crash: URL? { file("crash.ips") }

    /// What gets sent: everything but the agent's instructions and launch script.
    var attachments: [URL] {
        ["report.md", "environment.md", "ouch.log", "ouch.conf", "crash.ips"].compactMap(file)
    }

    private func file(_ name: String) -> URL? {
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A fresh report folder with everything an agent needs to read. `crash` is a macOS crash report.
    static func create(crash: URL? = nil) -> BugReport? {
        let fm = FileManager.default
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        let dir = root.appendingPathComponent(stamp.string(from: Date()))
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let r = BugReport(dir: dir)
            let summary = crash.flatMap(CrashSummary.init)
            try environment(crash: summary).write(to: dir.appendingPathComponent("environment.md"), atomically: true, encoding: .utf8)
            if let log = try? String(contentsOf: Log.url, encoding: .utf8) {
                let tail = log.split(separator: "\n", omittingEmptySubsequences: false).suffix(1500).joined(separator: "\n")
                try redact(tail).write(to: dir.appendingPathComponent("ouch.log"), atomically: true, encoding: .utf8)
            }
            if let conf = try? String(contentsOf: Config.url, encoding: .utf8) {
                try redact(conf).write(to: dir.appendingPathComponent("ouch.conf"), atomically: true, encoding: .utf8)
            }
            if let crash { try fm.copyItem(at: crash, to: dir.appendingPathComponent("crash.ips")) }
            try AgentPrompt.full(for: r).write(to: r.prompt, atomically: true, encoding: .utf8)
            prune()
            return r
        } catch {
            Log.info("bug report: couldn't create \(dir.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// The report an `ouch://report?id=…` link names. Only folders inside `root` count, so a link
    /// from anywhere else can't point Ouch at other files.
    static func existing(id: String) -> BugReport? {
        guard !id.isEmpty, !id.contains("/"), !id.hasPrefix(".") else { return nil }
        let dir = root.appendingPathComponent(id)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return BugReport(dir: dir)
    }

    func delete() { try? FileManager.default.removeItem(at: dir) }

    private static func prune() {
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for old in all.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(keep) {
            try? fm.removeItem(at: old)
        }
    }

    /// The home folder's path names the user; `~` says the same thing.
    private static func redact(_ s: String) -> String {
        s.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private static func environment(crash: CrashSummary?) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let displays = NSScreen.screens.map { s in
            "\(s.localizedName) \(Int(s.frame.width))×\(Int(s.frame.height)) @\(Int(s.backingScaleFactor))x"
        }
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        var lines = [
            "# Environment",
            "",
            "- Ouch \(version) (build \(build))",
            "- macOS \(os)",
            "- Mac: \(hardwareModel()), \(arch())",
            "- Displays: \(displays.joined(separator: "; "))",
            "- Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")",
            "- Input Monitoring: \(Permissions.inputMonitoringGranted ? "granted" : "not granted")",
            "- Window manager running: \(WindowManager.shared.isStarted ? "yes" : "no")",
            "- Report created: \(date)",
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

// MARK: - Crash reports

/// The gist of a macOS crash report (.ips): the exception and the first frame in Ouch's own code.
struct CrashSummary {
    let exception: String
    let frame: String?
    let date: Date

    var headline: String { [exception, frame].compactMap { $0 }.joined(separator: " in ") }
    var time: String { DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short) }

    /// An .ips file is a one-line JSON header followed by the JSON report.
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

extension Notification.Name {
    /// A crash report is waiting, or was just opened: the menu bar icon and menu redraw their dot.
    static let crashPendingChanged = Notification.Name("ouch.crashPendingChanged")
}

/// Notices when Ouch crashed. A marker file lives while Ouch runs and is removed on every clean exit;
/// a small watchdog process brings Ouch back after a crash. Nothing pops up: the menu bar icon and
/// Report a Bug… get a dot until the user opens the crash report.
enum CrashWatch {
    private static let support = BugReport.root.deletingLastPathComponent()
    private static let marker = support.appendingPathComponent("running")
    private static let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    private static let seenKey = "lastCrashReportSeen"
    private static let pendingKey = "pendingCrashReport"

    /// The crash report waiting to be looked at; kept across launches until it's opened.
    static var pending: URL? {
        guard let path = UserDefaults.standard.string(forKey: pendingKey), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Report a Bug…: the waiting crash if there is one, a plain report otherwise.
    static func openReport() {
        let crash = pending
        UserDefaults.standard.removeObject(forKey: pendingKey)
        if crash != nil { NotificationCenter.default.post(name: .crashPendingChanged, object: nil) }
        BugReportPanel.shared.show(crash: crash)
    }

    static func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        // Still there from the last run: it didn't exit cleanly. Its date is when that run started.
        let previous = (try? fm.attributesOfItem(atPath: marker.path))?[.modificationDate] as? Date
        try? fm.removeItem(at: marker)
        fm.createFile(atPath: marker.path, contents: Data("\(getpid())".utf8))
        startWatchdog()

        let defaults = UserDefaults.standard
        if defaults.object(forKey: seenKey) == nil { defaults.set(Date(), forKey: seenKey) } // don't offer old crashes
        if CommandLine.arguments.contains("--crash-report"), let latest = newestReport(after: .distantPast) {
            return offer(latest) // for working on the crash dot and card
        }
        guard let previous else { return }
        Log.info("crash watch: the last run didn't exit cleanly")
        let since = max(previous, defaults.object(forKey: seenKey) as? Date ?? previous)
        // macOS writes the report a few seconds after the crash, and the watchdog can relaunch us sooner.
        poll(after: since, attempts: 12)
    }

    /// Call on every clean exit, or the watchdog takes it for a crash.
    static func cleanExit() { try? FileManager.default.removeItem(at: marker) }

    private static func poll(after date: Date, attempts: Int) {
        if let report = newestReport(after: date) { return offer(report) }
        guard attempts > 0 else { return Log.info("crash watch: no crash report (force quit or killed?)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { poll(after: date, attempts: attempts - 1) }
    }

    private static func offer(_ report: URL) {
        UserDefaults.standard.set(Date(), forKey: seenKey)
        UserDefaults.standard.set(report.path, forKey: pendingKey)
        Log.info("crash watch: found \(report.lastPathComponent)")
        NotificationCenter.default.post(name: .crashPendingChanged, object: nil)
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

    /// A shell loop that waits for Ouch to exit. If the marker still names this run and macOS wrote a
    /// crash report (that can take half a minute), it opens Ouch again. A force quit leaves no report, so Ouch stays closed then, and a
    /// crash in the first 20 seconds isn't retried, so a crash on launch can't loop.
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

// MARK: - Agents

/// An AI app or command-line agent that can help write the report.
struct Agent: Identifiable {
    enum Style {
        /// The prompt goes in through the app's own deep link.
        case claude, codex, cursor
        /// Opens the report folder as a project; the prompt goes on the clipboard.
        case workspace
        /// A chat app without file access: the full prompt goes on the clipboard and Finder shows the files.
        case chat
        /// A command-line agent, run in Terminal. `args` go before the prompt.
        case cli(path: String, args: [String])
    }

    let id: String
    let name: String
    /// Agents from one maker share a single icon in the card; clicking it asks which one.
    let vendor: String
    let app: URL?
    let style: Style
    let icon: NSImage

    var isCLI: Bool { if case .cli = style { true } else { false } }

    func launch(_ report: BugReport) {
        let short = AgentPrompt.short(for: report)
        let ws = NSWorkspace.shared
        switch style {
        case .claude:
            open("claude://code/new", ["q": short, "folder": report.dir.path])
        case .codex:
            open("codex://new", ["prompt": short, "path": report.dir.path])
        case .cursor:
            open("cursor://anysphere.cursor-deeplink/prompt", ["text": short])
        case .workspace:
            copy(short)
            if let app { ws.open([report.dir], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) }
            HUD.shared.show("Prompt copied", on: nil)
        case .chat:
            copy(AgentPrompt.chat(for: report))
            if let app { ws.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) }
            ws.activateFileViewerSelecting(report.attachments.filter { $0 != report.report })
            HUD.shared.show("Paste, then drop the files in", on: nil)
        case .cli(let path, let args):
            runInTerminal(path: path, args: args + [short], in: report.dir)
        }
        Log.info("bug report: asked \(name)")
    }

    private func open(_ base: String, _ query: [String: String]) {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let q = query.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        guard let url = URL(string: "\(base)?\(q)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// A .command file opens in the user's terminal without asking for Automation permission, as an
    /// AppleScript `do script` would.
    private func runInTerminal(path: String, args: [String], in dir: URL) {
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let bin = (path as NSString).deletingLastPathComponent
        let script = """
        #!/bin/zsh -l
        cd \(q(dir.path))
        export PATH=\(q(bin)):"$PATH"
        clear
        \(([path] + args).map(q).joined(separator: " "))
        """
        let file = dir.appendingPathComponent("ask-\(id).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            Log.info("bug report: couldn't start \(name): \(error.localizedDescription)")
        }
    }
}

/// One icon in the card: a maker's agents, apps first.
struct AgentGroup: Identifiable {
    let agents: [Agent]
    var id: String { agents[0].vendor }
    var icon: NSImage { agents[0].icon }
    var name: String { agents.count == 1 ? agents[0].name : agents.map(\.name).joined(separator: " or ") }

    static func make(_ agents: [Agent]) -> [AgentGroup] {
        var order: [String] = [], byVendor: [String: [Agent]] = [:]
        for a in agents {
            if byVendor[a.vendor] == nil { order.append(a.vendor) }
            byVendor[a.vendor, default: []].append(a)
        }
        return order.map { AgentGroup(agents: byVendor[$0]!) }
    }
}

/// Finds the agents this Mac has. Apps by bundle ID; command-line tools through a login shell, since
/// an app opened from Finder doesn't get the user's PATH.
enum Agents {
    private struct AppEntry { let id: String; let vendor: String; let bundles: [String]; let style: Agent.Style }
    private struct CLIEntry { let command: String; let vendor: String; let name: String; let args: [String]; let iconBundle: String? }

    private static let apps = [
        AppEntry(id: "claude", vendor: "claude", bundles: ["com.anthropic.claudefordesktop"], style: .claude),
        AppEntry(id: "codex", vendor: "openai", bundles: ["com.openai.codex"], style: .codex),
        AppEntry(id: "chatgpt", vendor: "openai", bundles: ["com.openai.chat"], style: .chat),
        AppEntry(id: "cursor", vendor: "cursor", bundles: ["com.todesktop.230313mzl4w4u92"], style: .cursor),
        AppEntry(id: "vscode", vendor: "vscode", bundles: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], style: .workspace),
        AppEntry(id: "zed", vendor: "zed", bundles: ["dev.zed.Zed", "dev.zed.Zed-Preview"], style: .workspace),
        AppEntry(id: "windsurf", vendor: "windsurf", bundles: ["com.exafunction.windsurf"], style: .workspace),
        AppEntry(id: "opencode-app", vendor: "opencode", bundles: ["ai.opencode.desktop"], style: .workspace),
        AppEntry(id: "perplexity", vendor: "perplexity", bundles: ["ai.perplexity.mac"], style: .chat),
    ]
    private static let clis = [
        CLIEntry(command: "claude", vendor: "claude", name: "Claude Code", args: [], iconBundle: "com.anthropic.claudefordesktop"),
        CLIEntry(command: "codex", vendor: "openai", name: "Codex CLI", args: [], iconBundle: "com.openai.codex"),
        CLIEntry(command: "opencode", vendor: "opencode", name: "OpenCode", args: ["--prompt"], iconBundle: "ai.opencode.desktop"),
        CLIEntry(command: "gemini", vendor: "gemini", name: "Gemini CLI", args: ["-i"], iconBundle: nil),
    ]
    private static var cachedCLIs: [String: String]?

    /// Apps right away; command-line tools once the shell answers (cached after the first time).
    static func detect(_ done: @escaping ([Agent]) -> Void) {
        let found = installedApps()
        if let cachedCLIs { return done(found + cliAgents(cachedCLIs)) }
        done(found)
        DispatchQueue.global(qos: .userInitiated).async {
            let paths = findCLIs()
            DispatchQueue.main.async {
                cachedCLIs = paths
                done(found + cliAgents(paths))
            }
        }
    }

    private static func installedApps() -> [Agent] {
        let ws = NSWorkspace.shared
        return apps.compactMap { e in
            guard let url = e.bundles.lazy.compactMap({ ws.urlForApplication(withBundleIdentifier: $0) }).first else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return Agent(id: e.id, name: name, vendor: e.vendor, app: url, style: e.style, icon: ws.icon(forFile: url.path))
        }
    }

    private static func cliAgents(_ paths: [String: String]) -> [Agent] {
        let ws = NSWorkspace.shared
        let terminal = ws.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        return clis.compactMap { e in
            guard let path = paths[e.command] else { return nil }
            let iconApp = e.iconBundle.flatMap { ws.urlForApplication(withBundleIdentifier: $0) } ?? terminal
            let icon = iconApp.map { ws.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!
            return Agent(id: "cli-\(e.command)", name: "\(e.name) in Terminal", vendor: e.vendor, app: nil,
                         style: .cli(path: path, args: e.args), icon: icon)
        }
    }

    /// Asks an interactive login shell (that's where most PATH setup lives), then checks the usual
    /// install folders in case the shell config prints junk or hangs.
    private static func findCLIs() -> [String: String] {
        let names = clis.map(\.command)
        var found: [String: String] = [:]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "whence -p \(names.joined(separator: " ")) 2>/dev/null; true"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        if (try? p.run()) != nil {
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { if p.isRunning { p.terminate() } }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let path = line.trimmingCharacters(in: .whitespaces)
                let name = (path as NSString).lastPathComponent
                if path.hasPrefix("/"), names.contains(name), found[name] == nil { found[name] = path }
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local",
                    "\(home)/.opencode/bin", "\(home)/.bun/bin", "\(home)/.npm-global/bin"]
        for name in names where found[name] == nil {
            found[name] = dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        return found
    }
}

// MARK: - Prompts

enum AgentPrompt {
    /// What a deep link or command line carries: just a pointer to the instructions file.
    static func short(for r: BugReport) -> String {
        "Read \(r.prompt.path) and follow the instructions in it."
    }

    /// The instructions for an agent that can read files and run commands.
    static func full(for r: BugReport) -> String {
        let crashed = r.crash != nil
        let docs = (Bundle.main.resourceURL?.appendingPathComponent("AgentDocs/README.md").path)
            .flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        let guide = docs.map { """


        Ouch's own docs for agents are at `\($0)`. Read it, then the pages it points to that matter here \
        (troubleshooting.md first). Use them to tell a real bug from expected behaviour or a config mistake, \
        and to suggest workarounds. Don't change the user's config unless they ask.
        """ } ?? ""
        let files = """
        All files are in `\(r.dir.path)`:

        - `environment.md`: Ouch version, macOS, displays and permissions
        - `ouch.log`: Ouch's recent log, newest at the bottom
        - `ouch.conf`: the user's config\(crashed ? "\n- `crash.ips`: the macOS crash report (JSON after the first line)" : "")
        """
        let steps = crashed ? """
        1. Read `crash.ips` first. Find the exception, the crashed thread and the top frames in the `ouch` image. Then check `ouch.log` for what happened just before the crash time.
        2. Tell the user, in plain words and a few sentences, why Ouch most likely crashed. Say whether their config or setup seems to trigger it, and suggest a workaround if there is one. Say so when you're guessing.
        3. Ask what they were doing when it crashed, one or two short questions at a time.
        """ : """
        1. Read the files. Don't change them.
        2. Ask the user what went wrong: what they did, what they expected, what happened instead and whether it happens every time. Ask one or two short questions at a time.
        3. Look for evidence in `ouch.log` (and the config) that matches what they describe. Check the docs: if it's expected behaviour or a config mistake, say so and help fix that instead of filing a report.
        """
        return """
        # Help report a\(crashed ? " crash in" : " bug in") Ouch

        Ouch is a tiling window manager for macOS. Its source code is private, so work only from the files below.

        \(files)\(guide)

        ## Steps

        \(steps)
        4. Write `report.md` in that folder:
           - First line: `# <one-line summary>`
           - Sections: What happened, Steps to reproduce, Expected, Evidence (quote the relevant log lines or crash frames), Likely cause (mark guesses as guesses).
           - Keep personal details out of it.
        5. Show the user the report and ask if it's right. When they agree, run:
           `open "ouch://report?id=\(r.id)"`
           Ouch then shows the report so the user can send it. Don't send it any other way, and don't edit the other files.
        """
    }

    /// For chat apps that can't read files: the user attaches them by hand.
    static func chat(for r: BugReport) -> String {
        let crash = r.crash != nil
        return "Help me report a \(crash ? "crash" : "bug") in Ouch, a macOS tiling window manager. "
            + "The attached files are its setup, log and config\(crash ? " and crash report" : ""). "
            + "\(crash ? "Explain why it crashed, then ask" : "Ask") me a few short questions and write a Markdown bug report."
    }
}

// MARK: - Sending

/// Sends a finished report. Normally straight to the report relay (`OuchReportURL` in Info.plist, see
/// report-relay/), which files it as a Linear issue with the files attached. Without a relay it falls
/// back to a Mail draft to Linear's intake address (`OuchReportEmail`), and without that to the clipboard.
enum ReportSender {
    static var endpoint: URL? { info("OuchReportURL").flatMap(URL.init(string:)) }
    static var address: String? { info("OuchReportEmail") }
    static var canSend: Bool { endpoint != nil || address != nil }

    private static func info(_ key: String) -> String? {
        let v = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
        return v?.isEmpty == false ? v : nil
    }

    /// `done(true)` once the report is filed (or handed to Mail); `false` leaves the card open to retry.
    static func send(_ r: BugReport, text: String, crash: CrashSummary?, done: @escaping (Bool) -> Void) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try? body.write(to: r.report, atomically: true, encoding: .utf8)
        let first = body.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "# ")) ?? ""
        let title = String((first.isEmpty ? (crash.map { "Crash: \($0.headline)" } ?? "Bug report") : first).prefix(110))

        if let endpoint { return post(r, to: endpoint, title: title, body: body, done: done) }
        guard let address else {
            copy(r, body: body)
            return done(true)
        }
        let files = r.attachments
        if let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: [body] + files) {
            mail.recipients = [address]
            mail.subject = "[Ouch] " + title
            mail.perform(withItems: [body] + files)
            Log.info("bug report: \(r.id) handed to Mail")
            return done(true)
        }
        copy(r, body: body)
        done(true)
    }

    private static func post(_ r: BugReport, to url: URL, title: String, body: String, done: @escaping (Bool) -> Void) {
        let boundary = "ouch-\(UUID().uuidString)"
        var data = Data()
        func part(_ header: String, _ content: Data) {
            data.append(Data("--\(boundary)\r\n\(header)\r\n\r\n".utf8))
            data.append(content)
            data.append(Data("\r\n".utf8))
        }
        let version = Bundle.main.infoDictionary.map {
            "\($0["CFBundleShortVersionString"] as? String ?? "?") (\($0["CFBundleVersion"] as? String ?? "?"))"
        } ?? ""
        for (name, value) in [("title", title), ("body", body), ("version", version)] {
            part("Content-Disposition: form-data; name=\"\(name)\"", Data(value.utf8))
        }
        for file in r.attachments where file != r.report {
            guard let content = try? Data(contentsOf: file) else { continue }
            part("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: text/plain", content)
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
                    Log.info("bug report: \(r.id) filed as \(id ?? "?")")
                    done(true)
                } else {
                    Log.info("bug report: \(r.id) not sent (\(status) \(error?.localizedDescription ?? ""))")
                    done(false)
                }
            }
        }.resume()
    }

    private static func copy(_ r: BugReport, body: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting(r.attachments)
        HUD.shared.show("Report copied", on: nil)
    }
}
