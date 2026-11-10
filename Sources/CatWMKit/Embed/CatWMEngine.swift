import AppKit

@MainActor
public final class CatWMEngine {
    private final class Active {
        weak var engine: CatWMEngine?
    }

    private static let active = Active()

    public let name: String
    private let paths: InstancePaths
    private let backend: any WindowBackend
    private let readPermissions: () -> Set<Permission>
    private let store: ConfigStore
    private var manager: WindowManager
    private var permissions: PermissionWatcher?
    private var claimed: WindowScope?
    private var streams: [UUID: AsyncStream<Event>.Continuation] = [:]

    public private(set) var isRunning = false

    public convenience init(name: String? = nil) throws {
        guard let id = Self.instanceID(name) else { throw EngineError.invalidName(name ?? "") }
        guard Instance.embedding.claim(id), Instance.id == id else {
            throw EngineError.invalidName("this process already uses CatWM as `\(Instance.id ?? "standalone")`")
        }
        self.init(paths: Instance.paths, defaults: Instance.defaults, backend: AXBackend.shared,
                  permissions: { Set(Permission.allCases.filter(\.isGranted)) })
    }

    package init(paths: InstancePaths, defaults: UserDefaults, backend: any WindowBackend,
                 permissions: @escaping () -> Set<Permission>) {
        name = paths.id ?? ""
        self.paths = paths
        self.backend = backend
        readPermissions = permissions
        store = ConfigStore(folder: paths.configFolder, defaults: defaults, embedded: true)
        manager = Self.makeManager(backend: backend, config: .embedded, scope: nil, store: store, paths: paths)
        if Self.active.engine == nil { WindowManager.install(manager) }
    }

    package static func instanceID(_ name: String?) -> String? {
        if let name { return InstancePaths.isValid(name) ? name : nil }
        let host = (Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName).lowercased()
        let words = host.unicodeScalars.map {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) ? Character($0) : "-"
        }
        return String(("embed-" + String(words)).prefix(InstancePaths.maxLength))
    }

    private static func makeManager(backend: any WindowBackend, config: Config, scope: WindowScope?,
                                    store: ConfigStore, paths: InstancePaths) -> WindowManager {
        let manager = WindowManager(backend: backend, config: config, scope: scope, embedded: true)
        manager.store = store
        manager.socketPath = paths.configFolder.appendingPathComponent("catwm.sock").path
        manager.surface = EngineSurface()
        return manager
    }

    public func start(config: ConfigSource, scope: Scope? = nil) throws {
        guard !isRunning, Self.active.engine == nil else { throw EngineError.alreadyRunning }
        let loaded = try read(config)
        if !store.failures.isEmpty { throw EngineError.config(store.failures.map(Diagnostic.init)) }
        let windowScope = scope.map { WindowScope(pids: Set($0.pids), display: $0.display) }
        Instance.embedding.scope = windowScope
        manager = Self.makeManager(backend: backend, config: loaded, scope: windowScope, store: store, paths: paths)
        WindowManager.install(manager)
        Self.active.engine = self
        isRunning = true
        if let windowScope {
            Log.attempt("claim the scope") { try paths.writeClaim(ScopeClaim(owner: getpid(), scope: windowScope)) }
            claimed = windowScope
        }
        let watcher = PermissionWatcher(read: readPermissions)
        watcher.start()
        watcher.subscribe { [weak self] granted, changed in self?.permissionsChanged(granted, changed) }
        permissions = watcher
        manager.mayTile = { [weak watcher] in watcher?.granted.contains(.accessibility) == true }
        manager.startServices()
        if manager.config.features.contains(.tiling), manager.mayTile() { manager.startTiling() }
        Log.info("embed: started \(name) with \(manager.config.features.map(\.path).sorted().joined(separator: ", "))")
    }

    private func read(_ source: ConfigSource) throws -> Config {
        let entry: URL?
        switch source {
        case .file(let url):
            entry = url
        case .text(let text):
            entry = nil
            do {
                try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
                try text.write(to: store.folder.appendingPathComponent(ConfigStore.scriptName), atomically: true,
                               encoding: .utf8)
            } catch {
                throw EngineError.config([Diagnostic(file: nil, line: nil, phase: "read",
                                                     message: error.localizedDescription)])
            }
        }
        guard store.isLoaded else {
            if let entry { _ = store.use(entry: entry) }
            return store.isLoaded ? store.current : store.load()
        }
        return store.use(entry: entry)
    }

    private func permissionsChanged(_ granted: Set<Permission>, _ changed: Set<Permission>) {
        guard isRunning, !changed.isEmpty else { return }
        EventBus.shared.permissionsChanged(granted)
        guard changed.contains(.accessibility) else { return }
        if manager.isStarted {
            manager.setInputTaps(enabled: granted.contains(.accessibility))
        } else if granted.contains(.accessibility), manager.config.features.contains(.tiling) {
            manager.startTiling()
        }
    }

    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        permissions?.stop()
        permissions = nil
        let manager = manager
        await withCheckedContinuation { done in manager.stopTiling { done.resume() } }
        manager.stopServices()
        Instance.embedding.scope = nil
        if claimed != nil {
            Log.attempt("remove the scope claim") { try paths.removeClaim() }
            claimed = nil
        }
        streams.values.forEach { $0.finish() }
        streams = [:]
        Self.active.engine = nil
        Log.info("embed: stopped \(name)")
    }

    public func loadConfig(at url: URL) throws {
        try running()
        try apply(read(.file(url)))
    }

    public func replaceConfig(_ text: String) throws {
        try running()
        try apply(read(.text(text)))
    }

    public var options: [Option] {
        let config = isRunning ? manager.config : store.current
        return Options.all.compactMap { Option($0, in: config) }
            + Feature.allCases.filter(\.isEmbeddable).map { Option($0, in: config) }
    }

    public var overrides: [String: JSON] { store.overrides }

    public func setOption(_ id: String, to value: JSON) throws {
        guard options.contains(where: { $0.id == id }) else { throw EngineError.unknownOption(id) }
        do {
            try store.set(id, to: value)
        } catch {
            throw EngineError.invalidValue(error.localizedDescription)
        }
        if isRunning { try apply(store.reload(.changed)) }
    }

    public func resetOption(_ id: String) throws {
        guard options.contains(where: { $0.id == id }) else { throw EngineError.unknownOption(id) }
        do {
            try store.resetOverride(id)
        } catch {
            throw EngineError.invalidValue(error.localizedDescription)
        }
        if isRunning { try apply(store.reload(.changed)) }
    }

    private func apply(_ config: Config) throws {
        manager.apply(config, showHUD: false)
        if !store.failures.isEmpty { throw EngineError.config(store.failures.map(Diagnostic.init)) }
    }

    private func running() throws {
        guard isRunning else { throw EngineError.notRunning }
    }

    public func snapshot() -> Snapshot {
        let granted = permissions?.granted ?? readPermissions()
        return Snapshot(
            isRunning: isRunning, isTiling: manager.isStarted,
            features: Feature.allCases.filter(manager.config.features.contains).map(\.path),
            permissions: Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0.id, granted.contains($0)) }),
            diagnostics: store.current.diagnostics.map(Diagnostic.init),
            windows: manager.windowsJSON(), workspaces: manager.workspacesJSON(), screens: manager.screensJSON(),
            mode: Hotkeys.shared.submap)
    }

    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let token = EventBus.shared.listen { name, data in continuation.yield(Event(name: name, data: data)) }
            streams[token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    EventBus.shared.stopListening(token)
                    self?.streams[token] = nil
                }
            }
        }
    }

    @discardableResult
    public func perform(_ command: String, _ args: [String: JSON] = [:]) throws -> JSON {
        try running()
        do {
            return try CommandRegistry.execute(command, args, client: nil, manager: manager)
        } catch let error as ControlError {
            throw EngineError.command(code: error.code, message: error.message)
        }
    }
}
