import Foundation
import SQLite3

package struct CodeEditorAdapter: AppAdapter {
    package static let supportFolders = [
        "com.microsoft.VSCode": "Code", "com.microsoft.VSCodeInsiders": "Code - Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor", "com.vscodium": "VSCodium", "com.exafunction.windsurf": "Windsurf"
    ]
    package let bundleIDs = Set(Self.supportFolders.keys)
    package let captureNeedsAutomation = false
    package let restoreNeedsAutomation = false

    package func capture(bundleID: String, windows: [AppStateCapture.Window],
                         timeout: TimeInterval) async -> [ScriptedWindow] {
        guard let folder = Self.supportFolders[bundleID] else { return [] }
        let database = NSHomeDirectory() + "/Library/Application Support/\(folder)/User/globalStorage/state.vscdb"
        let projects = await Blocking.run(timeout: timeout, fallback: [URL]()) {
            let query = "select value from ItemTable where key = 'history.recentlyOpenedPathsList'"
            return SQLiteRead.strings(database, query).first.map(Self.recentProjects) ?? []
        }
        return ProjectGuess.windows(windows, projects: projects)
    }

    package func restore(_ state: AppState, bundleID _: String, appURL: URL, timeout _: TimeInterval) async -> Bool {
        await ProjectGuess.open(state, appURL: appURL)
    }

    private struct RecentWorkspace: Decodable { var configPath: String }

    private struct Recent: Decodable {
        package var folderUri: String?
        package var workspace: RecentWorkspace?
    }

    private struct RecentList: Decodable { var entries: [Recent] }

    package static func recentProjects(_ json: String) -> [URL] {
        guard let list = try? JSONDecoder().decode(RecentList.self, from: Data(json.utf8)) else { return [] }
        return list.entries.compactMap { URL(string: $0.folderUri ?? $0.workspace?.configPath ?? "") }
            .filter(\.isFileURL)
    }
}

package struct ZedAdapter: AppAdapter {
    package let bundleIDs: Set<String> = ["dev.zed.Zed", "dev.zed.Zed-Preview"]
    package let captureNeedsAutomation = false
    package let restoreNeedsAutomation = false

    package func capture(bundleID: String, windows: [AppStateCapture.Window],
                         timeout: TimeInterval) async -> [ScriptedWindow] {
        let channel = bundleID.hasSuffix("Preview") ? "0-preview" : "0-stable"
        let database = NSHomeDirectory() + "/Library/Application Support/Zed/db/\(channel)/db.sqlite"
        let projects = await Blocking.run(timeout: timeout, fallback: [URL]()) {
            let query = "select paths from workspaces where paths is not null and paths != '' "
                + "order by timestamp desc limit 100"
            return SQLiteRead.strings(database, query).compactMap { paths -> URL? in
                paths.split(separator: "\n").first.map { URL(fileURLWithPath: String($0), isDirectory: true) }
            }
        }
        return ProjectGuess.windows(windows, projects: projects)
    }

    package func restore(_ state: AppState, bundleID _: String, appURL: URL, timeout _: TimeInterval) async -> Bool {
        await ProjectGuess.open(state, appURL: appURL)
    }
}

package struct XcodeAdapter: AppAdapter {
    package let bundleIDs: Set<String> = ["com.apple.dt.Xcode"]
    package let captureNeedsAutomation = false
    package let restoreNeedsAutomation = false

    package func capture(bundleID _: String, windows: [AppStateCapture.Window],
                         timeout: TimeInterval) async -> [ScriptedWindow] {
        await Blocking.run(timeout: timeout, fallback: []) {
            windows.compactMap { window in
                guard let project = window.document.flatMap(URL.init(string:)).flatMap(ProjectGuess.xcodeProject) else {
                    return nil
                }
                return ScriptedWindow(title: window.title, frame: window.frame,
                                      state: AppState(tabs: [project.absoluteString]))
            }
        }
    }

    package func restore(_ state: AppState, bundleID _: String, appURL: URL, timeout _: TimeInterval) async -> Bool {
        await ProjectGuess.open(state, appURL: appURL)
    }
}

package enum ProjectGuess {
    package static func windows(_ windows: [AppStateCapture.Window], projects: [URL]) -> [ScriptedWindow] {
        windows.compactMap { window in
            guard let project = pick(projects, title: window.title, document: window.document) else { return nil }
            return ScriptedWindow(title: window.title, frame: window.frame,
                                  state: AppState(tabs: [project.absoluteString]))
        }
    }

    package static func pick(_ projects: [URL], title: String, document: String?) -> URL? {
        let parts = Set(title.components(separatedBy: " — ").flatMap { $0.components(separatedBy: " - ") }
            .map { $0.trimmingCharacters(in: .whitespaces) })
        let named = projects.filter { names($0).contains(where: parts.contains) }
        let candidates = named.isEmpty ? projects : named
        if let url = document.flatMap(URL.init(string:)), url.isFileURL {
            let path = url.standardizedFileURL.path
            let owners = candidates.filter {
                let projectPath = $0.standardizedFileURL.path
                return path == projectPath
                    || ($0.pathExtension != "code-workspace" && path.hasPrefix(projectPath + "/"))
            }
            if let owner = owners.max(by: { $0.standardizedFileURL.path.count < $1.standardizedFileURL.path.count }) {
                return owner
            }
        }
        return named.first
    }

    package static func xcodeProject(_ document: URL) -> URL? {
        guard document.isFileURL else { return nil }
        if ["xcodeproj", "xcworkspace", "playground"].contains(document.pathExtension) { return document }
        var folder = document.deletingLastPathComponent()
        let manager = FileManager.default
        for _ in 0..<12 where folder.path != "/" && folder.path != NSHomeDirectory() {
            let items = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
            if let found = items.sorted().first(where: { $0.hasSuffix(".xcworkspace") })
                ?? items.sorted().first(where: { $0.hasSuffix(".xcodeproj") }) {
                return folder.appendingPathComponent(found)
            }
            if items.contains("Package.swift") { return folder.appendingPathComponent("Package.swift") }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }

    static func open(_ state: AppState, appURL: URL) async -> Bool {
        guard let url = state.current.flatMap(URL.init(string:)), url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return false }
        return await Launcher.open(url, withApp: appURL)
    }

    private static func names(_ url: URL) -> [String] {
        guard url.pathExtension == "code-workspace" else { return [url.lastPathComponent] }
        let name = url.deletingPathExtension().lastPathComponent
        return [name, name + " (Workspace)", name + " [Workspace]"]
    }
}

package enum SQLiteRead {
    package static func strings(_ path: String, _ query: String) -> [String] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(database, 200)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { values.append(String(cString: text)) }
        }
        return values
    }
}
