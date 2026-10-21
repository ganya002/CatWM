import AppKit

enum TerminalFolders {
    static func urls(_ state: AppState) -> (folders: [URL], selected: Int)? {
        let folders = state.tabs.compactMap { URL(string: $0) }.filter(\.isFileURL)
        guard !folders.isEmpty else { return nil }
        let selected = state.current.flatMap { URL(string: $0) }.flatMap { folders.firstIndex(of: $0) } ?? 0
        return (folders, selected)
    }

    static func url(path: String) -> String {
        path.isEmpty ? "" : URL(fileURLWithPath: path, isDirectory: true).absoluteString
    }

    static func tool(_ name: String, bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .appendingPathComponent("Contents/MacOS/\(name)")
    }
}

private struct KittyOSWindow: Decodable {
    var platformWindowID: UInt32?
    var tabs: [KittyTab]

    enum CodingKeys: String, CodingKey {
        case platformWindowID = "platform_window_id"
        case tabs
    }
}

private struct KittyTab: Decodable {
    var title: String?
    var isActive = false
    var windows: [KittyPane]

    enum CodingKeys: String, CodingKey {
        case title, windows
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        windows = try values.decode([KittyPane].self, forKey: .windows)
    }
}

private struct KittyPane: Decodable {
    var cwd: String?
    var isActive = false
    var foregroundProcesses: [KittyProcess] = []

    enum CodingKeys: String, CodingKey {
        case cwd
        case isActive = "is_active"
        case foregroundProcesses = "foreground_processes"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd)
        isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        foregroundProcesses = try values.decodeIfPresent([KittyProcess].self, forKey: .foregroundProcesses) ?? []
    }

    var directory: String { foregroundProcesses.first?.cwd ?? cwd ?? "" }
}

private struct KittyProcess: Decodable {
    var cwd: String?
}

private struct WezTermPane: Decodable {
    var windowID: Int
    var tabID: Int
    var paneID: Int
    var windowTitle: String?
    var cwd: String?
    var isActive = false

    enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case tabID = "tab_id"
        case paneID = "pane_id"
        case windowTitle = "window_title"
        case cwd
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        windowID = try values.decode(Int.self, forKey: .windowID)
        tabID = try values.decode(Int.self, forKey: .tabID)
        paneID = try values.decode(Int.self, forKey: .paneID)
        windowTitle = try values.decodeIfPresent(String.self, forKey: .windowTitle)
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd)
        isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
}

struct GhosttyAdapter: AppAdapter {
    let bundleIDs: Set<String> = ["com.mitchellh.ghostty"]
    let captureNeedsAutomation = true
    let restoreNeedsAutomation = true

    func capture(bundleID: String, windows _: [AppStateCapture.Window],
                 timeout: TimeInterval) async -> [ScriptedWindow] {
        let source = ScriptText.frameHelper + """
        function run() {
          const app = Application("\(bundleID)");
          return JSON.stringify(app.windows().map(w => safe(() => {
            const tabs = w.tabs();
            if (tabs.length === 0) return null;
            return { title: safe(() => w.name(), ""), frame: safe(() => frameOf(w.bounds()), null),
                     tabs: tabs.map(t => safe(() => t.focusedTerminal().workingDirectory(), "")),
                     selected: Math.max(0, tabs.findIndex(t => safe(() => t.selected(), false))) };
          }, null)));
        }
        """
        let output = await AppScript.run(source, language: .javaScript, timeout: timeout)
        return ScriptedEntry.decode(output).compactMap { entry in
            entry.window(tabs: entry.tabs.map(TerminalFolders.url(path:)))
        }
    }

    func restore(_ state: AppState, bundleID: String, appURL _: URL, timeout: TimeInterval) async -> Bool {
        guard let (folders, selected) = TerminalFolders.urls(state) else { return false }
        let source = """
        on run argv
          tell application id "\(bundleID)"
            set cfg to new surface configuration
            set initial working directory of cfg to (item 2 of argv)
            set targetWindow to new window with configuration cfg
            repeat with i from 3 to count argv
              set tabConfig to new surface configuration
              set initial working directory of tabConfig to (item i of argv)
              new tab in targetWindow with configuration tabConfig
            end repeat
            select tab ((item 1 of argv) as integer) of targetWindow
          end tell
        end run
        """
        let output = await AppScript.run(source, language: .appleScript,
                                         arguments: [String(selected + 1)] + folders.map(\.path), timeout: timeout)
        return output != nil
    }
}

struct KittyAdapter: AppAdapter {
    let bundleIDs: Set<String> = ["net.kovidgoyal.kitty"]
    let captureNeedsAutomation = false
    let restoreNeedsAutomation = false

    func capture(bundleID: String, windows: [AppStateCapture.Window],
                 timeout: TimeInterval) async -> [ScriptedWindow] {
        guard let kitten = TerminalFolders.tool("kitten", bundleID: bundleID) else { return [] }
        for socket in Self.sockets() {
            guard let output = await ExternalCommand.run(kitten, ["@", "--to", "unix:" + socket, "ls"],
                                                         timeout: timeout) else { continue }
            let found = Self.parse(output, windows: windows)
            if !found.isEmpty { return found }
        }
        return []
    }

    func restore(_ state: AppState, bundleID: String, appURL: URL, timeout _: TimeInterval) async -> Bool {
        guard let (folders, selected) = TerminalFolders.urls(state) else { return false }
        let name = "Ouch-\(UUID().uuidString).kitty-session"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let text = Self.session(folders: folders, selected: selected)
        guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else { return false }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(at: file)
        }
        return await AppLaunch.open(appURL, bundleID: bundleID,
                                    arguments: ["--single-instance", "--session", file.path])
    }

    static func session(folders: [URL], selected: Int) -> String {
        folders.enumerated().map { index, folder in
            let quoted = "'" + folder.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return "new_tab\ncd \(quoted)\nlaunch\(index == selected ? "\nfocus" : "")"
        }.joined(separator: "\n") + "\n"
    }

    static func sockets() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/tmp")) ?? []
        return names.filter { $0.hasPrefix("kitty") }.map { "/tmp/" + $0 }.filter {
            var info = stat()
            return stat($0, &info) == 0 && (info.st_mode & S_IFMT) == S_IFSOCK
        }.sorted()
    }

    static func parse(_ output: String, windows: [AppStateCapture.Window]) -> [ScriptedWindow] {
        guard let data = output.data(using: .utf8),
              let list = try? JSONDecoder().decode([KittyOSWindow].self, from: data) else { return [] }
        return list.compactMap { entry in
            let paths = entry.tabs.map { tab in
                (tab.windows.first(where: \.isActive) ?? tab.windows.first)?.directory ?? ""
            }
            let owner = windows.first { $0.id == entry.platformWindowID }
            let active = entry.tabs.first(where: \.isActive)
            return ScriptedEntry(title: owner?.title ?? active?.title,
                                 frame: owner.map { [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height] },
                                 tabs: paths.map(TerminalFolders.url(path:)),
                                 selected: entry.tabs.firstIndex(where: \.isActive)).window()
        }
    }
}

struct WezTermAdapter: AppAdapter {
    let bundleIDs: Set<String> = ["com.github.wez.wezterm"]
    let captureNeedsAutomation = false
    let restoreNeedsAutomation = false

    func capture(bundleID: String, windows _: [AppStateCapture.Window],
                 timeout: TimeInterval) async -> [ScriptedWindow] {
        guard let wezterm = TerminalFolders.tool("wezterm", bundleID: bundleID),
              let output = await ExternalCommand.run(wezterm, ["cli", "list", "--format", "json"], timeout: timeout)
        else { return [] }
        return Self.parse(output)
    }

    func restore(_ state: AppState, bundleID: String, appURL: URL, timeout: TimeInterval) async -> Bool {
        guard let (folders, selected) = TerminalFolders.urls(state),
              let wezterm = TerminalFolders.tool("wezterm", bundleID: bundleID) else { return false }
        var pane = await ExternalCommand.run(wezterm, ["cli", "spawn", "--new-window", "--cwd", folders[0].path],
                                             timeout: timeout)
        if pane == nil {
            guard await Launcher.launch(appURL) else { return false }
            for _ in 0..<10 where pane == nil {
                try? await Task.sleep(nanoseconds: 300_000_000)
                pane = await ExternalCommand.run(wezterm, ["cli", "spawn", "--new-window", "--cwd", folders[0].path],
                                                 timeout: timeout)
            }
        }
        guard let first = pane, let id = Int(first),
              let list = await ExternalCommand.run(wezterm, ["cli", "list", "--format", "json"], timeout: timeout),
              let window = Self.windowID(ofPane: id, in: list) else { return false }
        var spawned: [Int] = [id]
        for folder in folders.dropFirst() {
            let output = await ExternalCommand.run(wezterm, ["cli", "spawn", "--window-id", String(window),
                                                             "--cwd", folder.path], timeout: timeout)
            guard let tab = output.flatMap({ Int($0) }) else { return false }
            spawned.append(tab)
        }
        if spawned.indices.contains(selected) {
            _ = await ExternalCommand.run(wezterm, ["cli", "activate-pane", "--pane-id", String(spawned[selected])],
                                          timeout: timeout)
        }
        return true
    }

    private static func panes(_ output: String) -> [WezTermPane] {
        guard let data = output.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WezTermPane].self, from: data)) ?? []
    }

    static func windowID(ofPane id: Int, in output: String) -> Int? {
        panes(output).first { $0.paneID == id }?.windowID
    }

    static func parse(_ output: String) -> [ScriptedWindow] {
        let panes = panes(output)
        var order: [Int] = []
        for pane in panes where !order.contains(pane.windowID) { order.append(pane.windowID) }
        return order.compactMap { windowID in
            let inWindow = panes.filter { $0.windowID == windowID }
            var tabs: [Int] = []
            for pane in inWindow where !tabs.contains(pane.tabID) { tabs.append(pane.tabID) }
            let paths = tabs.map { tab -> String in
                let group = inWindow.filter { $0.tabID == tab }
                let pane = group.first(where: \.isActive) ?? group[0]
                return pane.cwd.flatMap { URL(string: $0) }.map { TerminalFolders.url(path: $0.path) } ?? ""
            }
            return ScriptedEntry(title: inWindow[0].windowTitle, frame: nil, tabs: paths, selected: 0).window()
        }
    }
}
