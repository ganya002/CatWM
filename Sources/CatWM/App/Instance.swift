import Foundation

struct InstancePaths: Equatable {
    static let maxLength = 24

    let id: String?
    let home: URL

    init?(id: String?, home: URL) {
        if let id, !Self.isValid(id) { return nil }
        self.id = id
        self.home = home
    }

    static func isValid(_ id: String) -> Bool {
        (1...maxLength).contains(id.count)
            && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    var rootFolder: URL { home.appendingPathComponent(".config/catwm") }
    var instancesFolder: URL { rootFolder.appendingPathComponent("instances") }
    var configFolder: URL { named(rootFolder) }
    var logURL: URL { home.appendingPathComponent("Library/Logs/CatWM\(id.map { "-\($0)" } ?? "").log") }
    var supportFolder: URL { named(home.appendingPathComponent("Library/Application Support/CatWM")) }
    var cacheFolder: URL { named(home.appendingPathComponent("Library/Caches/catwm")) }
    var pidFile: URL { configFolder.appendingPathComponent("catwm.pid") }
    var defaultsSuite: String? { id.map { "local.catwm.instance.\($0)" } }

    private func named(_ folder: URL) -> URL {
        id.map { folder.appendingPathComponent("instances/\($0)") } ?? folder
    }

    func namedPidFiles(fileManager: FileManager = .default) -> [URL] {
        let ids = (try? fileManager.contentsOfDirectory(atPath: instancesFolder.path)) ?? []
        return ids.filter { $0 != id }.map { instancesFolder.appendingPathComponent("\($0)/catwm.pid") }
    }

    static func readPid(_ url: URL) -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func pidsToClose(own: pid_t, named: Bool, recorded: pid_t?, running: [pid_t],
                            otherInstances: Set<pid_t>) -> [pid_t] {
        var pids: [pid_t] = []
        if let recorded, recorded != own, running.contains(recorded) { pids.append(recorded) }
        if !named {
            pids += running.filter { $0 != own && !otherInstances.contains($0) && !pids.contains($0) }
        }
        return pids
    }
}

enum Instance {
    static let paths: InstancePaths = {
        let id = ProcessInfo.processInfo.environment["CATWM_INSTANCE"]
        guard let paths = InstancePaths(id: id, home: FileManager.default.homeDirectoryForCurrentUser) else {
            fail("CATWM_INSTANCE must be 1 to \(InstancePaths.maxLength) characters of a-z, 0-9 and -")
        }
        return paths
    }()

    static let id = paths.id
    static let isNamed = paths.id != nil
    static let configFolder = paths.configFolder
    static let logURL = paths.logURL
    static let supportFolder = paths.supportFolder
    static let cacheFolder = paths.cacheFolder
    static let pidFile = paths.pidFile

    static let scope: WindowScope? = {
        guard let text = ProcessInfo.processInfo.environment["CATWM_SCOPE"] else { return nil }
        guard let scope = WindowScope(text) else {
            fail("CATWM_SCOPE must be pids:<pid>,<pid>... with an optional ;display:<display UUID>")
        }
        return scope
    }()

    static let keys = ProcessInfo.processInfo.environment["CATWM_KEYS"]
    static let input = GlobalInput(scope: scope, keys: keys)

    static let defaults: UserDefaults = {
        guard let suite = paths.defaultsSuite else { return .standard }
        guard let defaults = UserDefaults(suiteName: suite) else { fail("cannot open the defaults suite \(suite)") }
        return defaults
    }()

    static func check() {
        _ = paths
        _ = scope
    }

    static func writePid() {
        Log.attempt("write \(pidFile.path)") {
            try FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true)
            try Data("\(getpid())".utf8).write(to: pidFile, options: .atomic)
        }
    }

    static func removePid() {
        guard InstancePaths.readPid(pidFile) == getpid() else { return }
        Log.attempt("remove \(pidFile.path)") { try FileManager.default.removeItem(at: pidFile) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("catwm: \(message)\n".utf8))
        exit(2)
    }
}
