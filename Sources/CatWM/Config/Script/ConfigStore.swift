import AppKit

final class ConfigStore {
    enum Source {
        case script, conf
    }

    static let shared = ConfigStore(folder: Instance.configFolder, defaults: Instance.defaults)

    static let scriptName = "catwm.config.ts"
    static let timeLimit = 3.0
    static let overridesName = "catwm.overrides.json"

    let folder: URL
    private let defaults: UserDefaults
    private(set) var source = Source.script
    private(set) var isLoaded = false
    private(set) var base = Config()
    private(set) var current = Config()
    private(set) var failures: [ConfigDiagnostic] = []
    private var engine: ConfigEngine?
    private var watcher: ConfigWatcher?
    private var files: [URL] = []
    private var onChange: ((Config) -> Void)?
    private var hasPublished = false

    var scriptURL: URL { folder.appendingPathComponent(Self.scriptName) }
    var overridesURL: URL { folder.appendingPathComponent(Self.overridesName) }
    var confURL: URL { folder.appendingPathComponent("catwm.conf") }

    init(folder: URL, defaults: UserDefaults) {
        self.folder = folder
        self.defaults = defaults
    }

    func load() -> Config {
        isLoaded = true
        Log.attempt("create config folder") {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: scriptURL.path) { failures = prepareScript() }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            source = .conf
            return loadConf()
        }
        source = .script
        writeTypes()
        publish(evaluate(.all), notify: false)
        return current
    }

    private func makeEngine() -> ConfigEngine {
        let scriptPath = scriptURL.path
        return ConfigEngine(entry: scriptURL) { value in
            var config = Config()
            return ConfigScript.read(value, into: &config, file: scriptPath)
        }
    }

    private func evaluate(_ pass: ConfigEngine.Pass) -> ConfigEngine.Run {
        let engine = engine ?? makeEngine()
        self.engine = engine
        return engine.run(pass, timeout: Self.timeLimit) ?? stuck(engine)
    }

    private func stuck(_ engine: ConfigEngine) -> ConfigEngine.Run {
        if self.engine === engine { self.engine = nil }
        let message = "the config didn't finish within \(Int(Self.timeLimit)) s, so CatWM stopped waiting. "
            + "Look for an endless loop, save, and restart CatWM to free the stuck thread"
        return ConfigEngine.Run(value: nil, failures: [ConfigDiagnostic(file: scriptURL.path, phase: .evaluate,
                                                                         message: message)], isStuck: true)
    }

    func reload(_ pass: ConfigEngine.Pass) -> Config {
        guard isLoaded else { return load() }
        guard source == .script else { return loadConf() }
        publish(evaluate(pass), notify: false)
        return current
    }

    private func loadConf() -> Config {
        let text = (try? String(contentsOf: confURL, encoding: .utf8)) ?? defaultText
        var config = Config.parse(text)
        config.diagnostics = failures + config.errors.map {
            ConfigDiagnostic(file: confURL.path, phase: .validate, message: $0)
        }
        config.errors = config.diagnostics.map(\.text)
        base = config
        current = config
        return config
    }

    func watch(_ apply: @escaping (Config) -> Void) {
        guard isLoaded, source == .script else { return }
        onChange = apply
        let watcher = watcher ?? ConfigWatcher { [weak self] paths in self?.changed(paths) }
        self.watcher = watcher
        watcher.watch(folders)
    }

    private var folders: [URL] { [folder] + files.map { $0.deletingLastPathComponent() } }

    private func changed(_ paths: [String]) {
        let relevant = paths.contains { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name == Self.overridesName || (name.hasSuffix(".ts") && !name.hasSuffix(".d.ts"))
                || name.hasSuffix(".js")
        }
        guard relevant else { return }
        let engine = engine ?? makeEngine()
        self.engine = engine
        var finished = false
        engine.run(.changed) { run in
            DispatchQueue.main.async { [weak self] in
                finished = true
                guard let self, self.engine === engine else { return }
                publish(run, notify: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeLimit) { [weak self] in
            guard let self, !finished, self.engine === engine else { return }
            publish(stuck(engine), notify: true)
        }
    }

    private func publish(_ run: ConfigEngine.Run, notify: Bool) {
        if !run.files.isEmpty { files = run.files }
        var failures = run.failures
        var base = Config()
        if let value = run.value { _ = ConfigScript.read(value, into: &base, file: scriptURL.path) }
        var current = base
        let overrides = readOverrides()
        let problems = overrides.problems
            + ConfigScript.read(.object(overrides.value), into: &current, file: overridesURL.path)
        if hasPublished, run.isStuck || run.value == nil {
            base = self.base
            current = self.current
        } else if problems.isEmpty {
            hasPublished = true
        } else {
            failures += problems
            if hasPublished {
                base = self.base
                current = self.current
            }
        }
        current.errors = []
        current.reportEmptySubmaps()
        let notes = current.errors.map { ConfigDiagnostic(file: scriptURL.path, phase: .validate, message: $0) }
        current.diagnostics = failures + notes
        current.errors = current.diagnostics.map(\.text)
        self.failures = failures
        self.base = base
        self.current = current
        let names = run.ran.map { URL(fileURLWithPath: $0).lastPathComponent }
        let time = String(format: "%.1f ms", run.milliseconds)
        if let failure = failures.first {
            Log.info("config: kept the last good config, \(failure.phase.rawValue) failed: \(failure.text) (\(time))")
        } else if names.isEmpty {
            Log.debug("config: no module changed (\(time))")
        } else {
            let count = "\(names.count) of \(files.count) modules"
            Log.info("config: ran \(names.joined(separator: ", ")) (\(count)) in \(time)")
        }
        watcher?.watch(folders)
        guard notify else { return }
        onChange?(current)
        NotificationCenter.default.post(name: .configStoreChanged, object: self)
    }

    private func prepareScript() -> [ConfigDiagnostic] {
        let conf = try? String(contentsOf: confURL, encoding: .utf8)
        if let conf, !defaults.bool(forKey: DefaultsKey.migratedConfigToTypeScript) {
            if let problem = migrate(conf) {
                Log.info("config: \(problem.text)")
                return [problem]
            }
            Log.info("config: converted catwm.conf to \(Self.scriptName); catwm.conf stays as a backup")
        } else {
            Log.attempt("write the default config") {
                try Self.defaultScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            }
        }
        defaults.set(true, forKey: DefaultsKey.migratedConfigToTypeScript)
        return []
    }

    private func migrate(_ conf: String) -> ConfigDiagnostic? {
        let fail = { (reason: String) in
            ConfigDiagnostic(file: self.confURL.path, phase: .migrate,
                             message: "CatWM couldn't convert catwm.conf to \(Self.scriptName), so it still uses "
                                + "catwm.conf: \(reason)")
        }
        let source = ConfigMigration.typescript(from: conf, header: [
            "// CatWM config, converted from catwm.conf.",
            "// catwm.conf stays next to it as a backup that CatWM no longer reads.",
            "// Types and completion come from catwm.d.ts. Save the file and CatWM applies the change."
        ])
        let trial = folder.appendingPathComponent(".catwm.config.converting.ts")
        defer {
            if FileManager.default.fileExists(atPath: trial.path) {
                Log.attempt("remove the trial config") { try FileManager.default.removeItem(at: trial) }
            }
        }
        do {
            try source.write(to: trial, atomically: true, encoding: .utf8)
        } catch {
            return fail(error.localizedDescription)
        }
        guard let run = ConfigEngine(entry: trial).run(.all, timeout: Self.timeLimit) else {
            return fail("the converted config didn't finish")
        }
        if let failure = run.failures.first { return fail(failure.message) }
        var config = Config()
        if let problem = run.value.map({ ConfigScript.read($0, into: &config, file: nil) })?.first {
            return fail(problem.message)
        }
        var parsed = Config.parse(conf)
        parsed.bindings.removeAll { !Actions.dispatchers.contains($0.dispatcher) }
        let changes = config.changes(from: parsed)
        if !changes.isEmpty { return fail("the result differs in \(changes.sorted().joined(separator: ", "))") }
        do {
            try FileManager.default.moveItem(at: trial, to: scriptURL)
        } catch {
            return fail(error.localizedDescription)
        }
        return nil
    }

    private func writeTypes() {
        let types = folder.appendingPathComponent(ConfigTypes.fileName)
        let text = ConfigTypes.render()
        if (try? String(contentsOf: types, encoding: .utf8)) != text {
            Log.attempt("write \(ConfigTypes.fileName)") {
                try text.write(to: types, atomically: true, encoding: .utf8)
            }
        }
        let tsconfig = folder.appendingPathComponent("tsconfig.json")
        if !FileManager.default.fileExists(atPath: tsconfig.path) {
            Log.attempt("write tsconfig.json") {
                try ConfigTypes.tsconfig.write(to: tsconfig, atomically: true, encoding: .utf8)
            }
        }
    }

    static let defaultScript: String = {
        let conf = defaultText.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
        return ConfigMigration.typescript(from: conf, header: [
            "// CatWM config. Types and completion come from catwm.d.ts, next to this file.",
            "// Save the file and CatWM applies the change. A broken save keeps the last good config."
        ])
    }()
}

extension ConfigStore {
    var isScript: Bool { isLoaded && source == .script }
    var overriddenPaths: [String] { isScript ? ConfigScript.paths(readOverrides().value) : [] }

    func set(option: ConfigOption, _ value: String) throws {
        guard source == .script else { return try Config.write(option: option.key, value, to: confURL) }
        var edited = current
        if let problem = option.read(&edited, value, option.key) { throw ConfigError(message: problem) }
        var overrides = readOverrides().value
        ConfigScript.set(ConfigScript.json(option, in: edited), at: option.script, in: &overrides)
        try writeOverrides(overrides)
    }

    struct SettingsCopy {
        let text: String
        let shown: Config
        let source: Config
    }

    var settingsCopy: SettingsCopy {
        let text = settingsText
        return SettingsCopy(text: text, shown: ConfigText(text).config, source: current)
    }

    func save(settings edited: Config, from copy: SettingsCopy) throws {
        let shown = copy.shown
        var merged = current
        for option in Options.all where option.text(edited) != option.text(shown) { option.copy(&merged, edited) }
        if edited.layouts != shown.layouts { merged.layouts = edited.layouts }
        if edited.floating != shown.floating { merged.floating = edited.floating }
        if edited.mainMod != shown.mainMod { merged.mainMod = edited.mainMod }
        if edited.changes(from: shown).contains("bindings") {
            let aligned = shown.bindings.count == copy.source.bindings.count
            merged.bindings = edited.bindings.map { binding in
                guard aligned, let index = shown.bindings.firstIndex(of: binding) else { return binding }
                return copy.source.bindings[index]
            }
        }
        try writeOverrides(overrides(merged))
    }

    private func overrides(_ edited: Config) -> [String: JSON] {
        var overrides: [String: JSON] = [:]
        for option in Options.all where option.text(edited) != option.text(base) {
            ConfigScript.set(ConfigScript.json(option, in: edited), at: option.script, in: &overrides)
        }
        let changes = edited.changes(from: base)
        if changes.contains("layouts") { overrides["layouts"] = .array(edited.layouts.map { .string($0.rawValue) }) }
        if changes.contains("floating") {
            ConfigScript.set(.array(edited.floating.map(JSON.string)), at: "floating.apps", in: &overrides)
        }
        if changes.contains("mod") { overrides["mod"] = ConfigScript.json(mod: edited.mainMod) }
        if changes.contains("bindings") {
            let binds = ConfigScript.json(binds: edited.bindings)
            overrides["binds"] = binds.binds
            overrides["submaps"] = binds.submaps
        }
        return overrides
    }

    func resetOverride(_ path: String?) throws {
        var overrides = readOverrides().value
        if let path {
            ConfigScript.remove(path, from: &overrides)
            if path == "binds" || path == "submaps" { overrides["binds"] = nil; overrides["submaps"] = nil }
        } else {
            overrides = [:]
        }
        try writeOverrides(overrides)
    }

    var settingsText: String {
        let main = NSEvent.ModifierFlags(rawValue: UInt(current.mainMod.rawValue))
        let mainText = ConfigScript.mods.filter { main.contains($0.flag) }.map(\.conf).joined(separator: " ")
        let rows = current.bindRows.map { row -> BindRow in
            guard !main.isEmpty, let flags = ConfigText.flags(row.mods), flags.isSuperset(of: main) else { return row }
            var copy = row
            let rest = ConfigScript.mods.filter { flags.subtracting(main).contains($0.flag) }.map(\.conf)
            copy.mods = ([Self.settingsMod] + rest).joined(separator: " ")
            return copy
        }
        let mod = VarRow(name: Self.settingsMod, value: mainText.isEmpty ? "ALT" : mainText)
        return ConfigText.keyboard(vars: [mod], binds: rows)
            + Options.lines(current).joined(separator: "\n") + "\n"
    }

    private static let settingsMod = "$__catwm_main_mod"

    private func readOverrides() -> (value: [String: JSON], problems: [ConfigDiagnostic]) {
        guard FileManager.default.fileExists(atPath: overridesURL.path) else { return ([:], []) }
        guard let data = try? Data(contentsOf: overridesURL) else {
            let problem = ConfigDiagnostic(file: overridesURL.path, phase: .read, message: "CatWM can't read this file")
            return ([:], [problem])
        }
        guard let object = JSON.parse(data)?.object else {
            return ([:], [ConfigDiagnostic(file: overridesURL.path, phase: .read,
                                           message: "isn't a JSON object, so CatWM leaves it out")])
        }
        return (object, [])
    }

    private func writeOverrides(_ overrides: [String: JSON]) throws {
        if overrides.isEmpty {
            if FileManager.default.fileExists(atPath: overridesURL.path) {
                try FileManager.default.removeItem(at: overridesURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(JSON.object(overrides)).write(to: overridesURL, options: .atomic)
    }
}

struct ConfigError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension Notification.Name {
    static let configStoreChanged = Notification.Name("CatWM.configStoreChanged")
}
