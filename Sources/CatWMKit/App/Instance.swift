import Foundation
import os

package struct InstancePaths: Equatable {
    package static let maxLength = 24

    package let id: String?
    package let home: URL

    package init?(id: String?, home: URL) {
        if let id, !Self.isValid(id) { return nil }
        self.id = id
        self.home = home
    }

    package static func isValid(_ id: String) -> Bool {
        (1...maxLength).contains(id.count)
            && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    package var rootFolder: URL { home.appendingPathComponent(".config/catwm") }
    package var instancesFolder: URL { rootFolder.appendingPathComponent("instances") }
    package var configFolder: URL { named(rootFolder) }
    package var logURL: URL { home.appendingPathComponent("Library/Logs/CatWM\(id.map { "-\($0)" } ?? "").log") }
    package var supportFolder: URL { named(home.appendingPathComponent("Library/Application Support/CatWM")) }
    package var cacheFolder: URL { named(home.appendingPathComponent("Library/Caches/catwm")) }
    package var pidFile: URL { configFolder.appendingPathComponent("catwm.pid") }
    package var scopeFile: URL { configFolder.appendingPathComponent("scope") }
    private var stagedScopeFile: URL { instancesFolder.appendingPathComponent(".\(id ?? "default").scope") }
    package var mayRelaunchItself: Bool { id == nil }
    package var defaultsSuite: String? { id.map { "local.catwm.instance.\($0)" } }

    private func named(_ folder: URL) -> URL {
        id.map { folder.appendingPathComponent("instances/\($0)") } ?? folder
    }

    package func namedPidFiles(fileManager: FileManager = .default) -> [URL] {
        let ids = (try? fileManager.contentsOfDirectory(atPath: instancesFolder.path)) ?? []
        return ids.filter { $0 != id }.map { instancesFolder.appendingPathComponent("\($0)/catwm.pid") }
    }

    package func writeClaim(_ claim: ScopeClaim) throws {
        try FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true)
        try Data(claim.text.utf8).write(to: stagedScopeFile)
        try Self.move(stagedScopeFile, to: scopeFile)
    }

    package func removeClaim() throws {
        try Self.move(scopeFile, to: stagedScopeFile)
        try FileManager.default.removeItem(at: stagedScopeFile)
    }

    private static func move(_ source: URL, to target: URL) throws {
        guard rename(source.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    package static func readPid(_ url: URL) -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    package static func pidsToClose(own: pid_t, named: Bool, recorded: pid_t?, running: [pid_t],
                                    otherInstances: Set<pid_t>) -> [pid_t] {
        var pids: [pid_t] = []
        if let recorded, recorded != own, running.contains(recorded) { pids.append(recorded) }
        if !named {
            pids += running.filter { $0 != own && !otherInstances.contains($0) && !pids.contains($0) }
        }
        return pids
    }
}

package final class Embedding: Sendable {
    private struct State {
        var id: String?
        var frozen = false
        var scope: WindowScope?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    package var scope: WindowScope? {
        get { state.withLock { $0.scope } }
        set { state.withLock { $0.scope = newValue } }
    }

    package func claim(_ id: String) -> Bool {
        state.withLock { state in
            guard !state.frozen || state.id == id else { return false }
            state.id = id
            return true
        }
    }

    package func freeze() -> String? {
        state.withLock { state in
            state.frozen = true
            return state.id
        }
    }
}

package enum Instance {
    package static let embedding = Embedding()
    package static let embeddedID = embedding.freeze()
    package static let isEmbedded = embeddedID != nil

    package static let paths: InstancePaths = {
        let id = embeddedID ?? ProcessInfo.processInfo.environment["CATWM_INSTANCE"]
        guard let paths = InstancePaths(id: id, home: FileManager.default.homeDirectoryForCurrentUser) else {
            fail("CATWM_INSTANCE must be 1 to \(InstancePaths.maxLength) characters of a-z, 0-9 and -")
        }
        return paths
    }()

    package static let id = paths.id
    package static let isNamed = paths.id != nil
    package static let configFolder = paths.configFolder
    package static let logURL = paths.logURL
    package static let supportFolder = paths.supportFolder
    package static let cacheFolder = paths.cacheFolder
    package static let pidFile = paths.pidFile

    package static let scope: WindowScope? = {
        guard !isEmbedded, let text = ProcessInfo.processInfo.environment["CATWM_SCOPE"] else { return nil }
        guard isNamed else { fail("CATWM_SCOPE needs CATWM_INSTANCE") }
        guard let scope = WindowScope(text) else {
            fail("CATWM_SCOPE must be pids:<pid>,<pid>... with an optional ;display:<display UUID>")
        }
        if let refusal = scope.refusal { fail(refusal) }
        return scope
    }()

    package static let keys = ProcessInfo.processInfo.environment["CATWM_KEYS"]

    @MainActor package static let defaults: UserDefaults = {
        guard let suite = paths.defaultsSuite else { return .standard }
        guard let defaults = UserDefaults(suiteName: suite) else { fail("cannot open the defaults suite \(suite)") }
        return defaults
    }()

    package static func check() {
        _ = paths
        _ = scope
    }

    package static func writePid() {
        Log.attempt("write \(pidFile.path)") {
            try FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true)
            try Data("\(getpid())".utf8).write(to: pidFile, options: .atomic)
            guard let scope else { return }
            try paths.writeClaim(ScopeClaim(owner: getpid(), scope: scope))
        }
    }

    package static func removePid() {
        guard InstancePaths.readPid(pidFile) == getpid() else { return }
        Log.attempt("remove \(pidFile.path)") { try FileManager.default.removeItem(at: pidFile) }
        guard scope != nil else { return }
        Log.attempt("remove \(paths.scopeFile.path)") { try paths.removeClaim() }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("catwm: \(message)\n".utf8))
        exit(2)
    }
}
