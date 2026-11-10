import AppKit

extension ConfigStore {
    package var isScript: Bool { isLoaded && source == .script }
    package var overriddenPaths: [String] { isScript ? ConfigScript.paths(readOverrides().value) : [] }

    package func set(option: ConfigOption, _ value: String) throws {
        guard source == .script else { return try Config.write(option: option.key, value, to: confURL) }
        var edited = current
        if let problem = option.read(&edited, value, option.key) { throw ConfigError(message: problem) }
        var overrides = readOverrides().value
        ConfigScript.set(ConfigScript.json(option, in: edited), at: option.script, in: &overrides)
        try writeOverrides(overrides)
    }

    package func set(_ path: String, to value: JSON) throws {
        var overrides = readOverrides().value
        ConfigScript.set(value, at: path, in: &overrides)
        var probe = base
        if let problem = ConfigScript.read(.object(overrides), into: &probe, file: nil, embedded: embedded).first {
            throw ConfigError(message: problem.message)
        }
        try writeOverrides(overrides)
    }

    package var overrides: [String: JSON] { readOverrides().value }

    package struct SettingsCopy {
        package let text: String
        package let shown: Config
        package let source: Config
    }

    package var settingsCopy: SettingsCopy {
        let text = settingsText
        return SettingsCopy(text: text, shown: ConfigText(text).config, source: current)
    }

    package func save(settings edited: Config, from copy: SettingsCopy) throws {
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

    package func resetOverride(_ path: String?) throws {
        var overrides = readOverrides().value
        if let path {
            ConfigScript.remove(path, from: &overrides)
            if path == "binds" || path == "submaps" { overrides["binds"] = nil; overrides["submaps"] = nil }
        } else {
            overrides = [:]
        }
        try writeOverrides(overrides)
    }

    package var settingsText: String {
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

    func readOverrides() -> (value: [String: JSON], problems: [ConfigDiagnostic]) {
        if embedded { return (heldOverrides, []) }
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

    func writeOverrides(_ overrides: [String: JSON]) throws {
        if embedded { return heldOverrides = overrides }
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
