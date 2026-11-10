import AppKit

enum ConfigScript {
    private enum Leaf {
        case option(ConfigOption)
        case mod, layouts, floatingApps, padding, binds, submaps
        case feature(Feature)
    }

    struct Mod {
        let name: String
        let flag: NSEvent.ModifierFlags
        let conf: String
    }

    static let mods = [
        Mod(name: "cmd", flag: .command, conf: "SUPER"), Mod(name: "alt", flag: .option, conf: "ALT"),
        Mod(name: "ctrl", flag: .control, conf: "CTRL"), Mod(name: "shift", flag: .shift, conf: "SHIFT")
    ]

    static let keyAliases = [
        "enter": "return", "esc": "escape", "caps": "capslock", "caps_lock": "capslock", "prior": "pageup",
        "next": "pagedown", "quote": "apostrophe", "'": "apostrophe", "=": "equal", "-": "minus",
        "]": "bracketright", "[": "bracketleft", ";": "semicolon", "\\": "backslash", "/": "slash", ".": "period",
        "`": "grave"
    ]

    static var keyNames: [String] {
        keyCodes.keys.filter { keyAliases[$0] == nil }.sorted { (keyCodes[$0] ?? 0, $0) < (keyCodes[$1] ?? 0, $1) }
    }

    private static let leaves: [String: Leaf] = {
        var leaves: [String: Leaf] = [
            "mod": .mod, "layouts": .layouts, "floating.apps": .floatingApps, "padding": .padding,
            "binds": .binds, "submaps": .submaps
        ]
        for option in Options.all { leaves[option.script] = .option(option) }
        for feature in Feature.allCases { leaves[feature.path] = .feature(feature) }
        return leaves
    }()

    static let groups: [String: [String]] = {
        var groups: [String: [String]] = [:]
        for path in leaves.keys {
            var parts = path.split(separator: ".").map(String.init)
            while parts.count > 1 {
                let name = parts.removeLast()
                let parent = parts.joined(separator: ".")
                if !(groups[parent] ?? []).contains(name) { groups[parent, default: []].append(name) }
            }
        }
        return groups.mapValues { $0.sorted() }
    }()

    static func read(_ value: JSON, into config: inout Config, file: String?) -> [ConfigDiagnostic] {
        var reader = Reader(file: file)
        guard let object = value.object else {
            reader.fail("", "the default export must be an object, such as `export default { gaps: { size: 8 } }`")
            return reader.diagnostics
        }
        reader.read(object, prefix: "", into: &config)
        for feature in Feature.allCases where config.features.contains(feature) {
            for need in feature.needs where !config.features.contains(need) {
                reader.fail(feature.path, "needs `\(need.path)`, which is off")
            }
        }
        return reader.diagnostics
    }

    private static func list(_ group: String) -> String {
        (groups[group] ?? []).joined(separator: ", ")
    }
}

extension ConfigScript {
    private struct Reader {
        let file: String?
        var diagnostics: [ConfigDiagnostic] = []

        mutating func fail(_ path: String, _ message: String) {
            let text = path.isEmpty ? message : "`\(path)` \(message)"
            diagnostics.append(ConfigDiagnostic(file: file, phase: .validate, message: text))
        }

        mutating func read(_ object: [String: JSON], prefix: String, into config: inout Config) {
            for key in object.keys.sorted() {
                guard let value = object[key] else { continue }
                let path = prefix.isEmpty ? key : prefix + "." + key
                if let leaf = ConfigScript.leaves[path], !(path == "padding" && value.object != nil) {
                    read(leaf, value, path: path, into: &config)
                } else if ConfigScript.groups[path] != nil {
                    guard let group = value.object else {
                        fail(path, "must be an object with \(ConfigScript.list(path))")
                        continue
                    }
                    read(group, prefix: path, into: &config)
                } else {
                    let known = prefix.isEmpty ? "" : " (\(prefix) has \(ConfigScript.list(prefix)))"
                    fail(path, "is not a CatWM option\(known)")
                }
            }
        }

        private mutating func read(_ leaf: Leaf, _ value: JSON, path: String, into config: inout Config) {
            switch leaf {
            case .option(let option): read(option, value, path: path, into: &config)
            case .feature(let feature):
                guard case .bool(let isOn) = value else { return fail(path, "must be true or false") }
                if isOn { config.features.insert(feature) } else { config.features.remove(feature) }
            case .mod:
                guard let flags = flags(value, path: path) else { return }
                config.mainMod = CGEventFlags(rawValue: UInt64(flags.rawValue))
            case .layouts: readLayouts(value, path: path, into: &config)
            case .floatingApps:
                guard let apps = strings(value, path: path) else { return }
                config.floating = Config.listItems(apps.joined(separator: ","))
            case .padding:
                guard let number = value.double else {
                    return fail(path, "must be a number or { left, right, top, bottom }")
                }
                for side in ["left", "right", "top", "bottom"] {
                    if let option = ConfigOption.named("screen-padding-" + side) {
                        read(option, .number(number), path: path, into: &config)
                    }
                }
            case .binds: readBinds(value, path: path, into: &config)
            case .submaps: readSubmaps(value, path: path, into: &config)
            }
        }

        private mutating func readLayouts(_ value: JSON, path: String, into config: inout Config) {
            guard let names = strings(value, path: path) else { return }
            var layouts: [Layout] = []
            for name in names {
                guard let layout = Layout(rawValue: name) else { return fail(path, "has an unknown layout `\(name)`") }
                if !layouts.contains(layout) { layouts.append(layout) }
            }
            if layouts.isEmpty { return fail(path, "needs at least one layout") }
            config.layouts = layouts
        }

        private mutating func readBinds(_ value: JSON, path: String, into config: inout Config) {
            guard let list = value.array else { return fail(path, "must be a list of binds") }
            let read = binds(list, submap: "", path: path)
            config.bindings.removeAll { $0.submap.isEmpty }
            config.bindings.insert(contentsOf: read.bindings, at: 0)
            config.bindRows.removeAll { $0.submap.isEmpty }
            config.bindRows.insert(contentsOf: read.rows, at: 0)
        }

        private mutating func readSubmaps(_ value: JSON, path: String, into config: inout Config) {
            guard let modes = value.object else { return fail(path, "must map each mode name to a list of binds") }
            config.bindings.removeAll { !$0.submap.isEmpty }
            config.bindRows.removeAll { !$0.submap.isEmpty }
            for name in modes.keys.sorted() {
                guard let list = modes[name]?.array else {
                    fail(path + "." + name, "must be a list of binds")
                    continue
                }
                let read = binds(list, submap: name, path: path + "." + name)
                config.bindings += read.bindings
                config.bindRows += read.rows
            }
        }

        private mutating func read(_ option: ConfigOption, _ value: JSON, path: String, into config: inout Config) {
            let text: String
            switch (option.scriptKind, value) {
            case (.bool, .bool(let isOn)): text = isOn ? "true" : "false"
            case (.number, .int(let number)): text = "\(number)"
            case (.number, .number(let number)): text = "\(number)"
            case (.string, .string(let string)): text = string
            case (.strings, .array):
                guard let items = strings(value, path: path) else { return }
                text = items.joined(separator: ", ")
            default:
                let noun = switch option.scriptKind {
                case .bool: "true or false"
                case .number: "a number"
                case .string: "a string"
                case .strings: "a list of strings"
                }
                return fail(path, "must be \(noun)")
            }
            if let error = option.read(&config, text, path) {
                fail("", error.contains("`\(path)`") ? error : "`\(path)`: \(error)")
            }
        }

        private mutating func strings(_ value: JSON, path: String) -> [String]? {
            guard let list = value.array, list.allSatisfy({ $0.string != nil }) else {
                fail(path, "must be a list of strings")
                return nil
            }
            return list.compactMap(\.string)
        }

        private mutating func flags(_ value: JSON, path: String) -> NSEvent.ModifierFlags? {
            let names = value.string.map { [$0] } ?? value.array?.compactMap(\.string)
            guard let names, names.count == (value.array?.count ?? 1) else {
                fail(path, "must be a list of modifiers: cmd, alt, ctrl, shift")
                return nil
            }
            var flags: NSEvent.ModifierFlags = []
            for name in names {
                guard let mod = ConfigScript.mods.first(where: { $0.name == name }) else {
                    fail(path, "has an unknown modifier `\(name)` (cmd, alt, ctrl, shift)")
                    return nil
                }
                flags.insert(mod.flag)
            }
            return flags
        }

        private mutating func binds(_ list: [JSON], submap: String,
                                    path: String) -> (bindings: [KeyBinding], rows: [BindRow]) {
            var bindings: [KeyBinding] = [], rows: [BindRow] = []
            for (index, item) in list.enumerated() {
                if let (binding, row) = bind(item, submap: submap, path: "\(path)[\(index)]") {
                    bindings.append(binding)
                    rows.append(row)
                }
            }
            return (bindings, rows)
        }

        private mutating func bind(_ item: JSON, submap: String, path: String) -> (KeyBinding, BindRow)? {
            guard let object = item.object else {
                fail(path, "must be a bind such as { mods: [\"alt\"], key: \"h\", run: [\"movefocus\", \"l\"] }")
                return nil
            }
            if let extra = object.keys.sorted().first(where: { !["mods", "key", "run", "repeat"].contains($0) }) {
                fail(path, "has an unknown field `\(extra)` (mods, key, run, repeat)")
                return nil
            }
            let flags = object["mods"].map { flags($0, path: path + ".mods") } ?? []
            guard let flags else { return nil }
            guard let key = object["key"]?.string else {
                fail(path + ".key", "must be a key name such as \"h\" or \"tab\"")
                return nil
            }
            guard let code = keyCodes[key.lowercased()] else {
                let hint = BindRange.isRange(key) ? ". Write one bind for each key, for example with map()" : ""
                fail(path + ".key", "is an unknown key `\(key)`\(hint)")
                return nil
            }
            guard let (dispatcher, arg) = run(object["run"], path: path + ".run") else { return nil }
            var repeats = false
            if let value = object["repeat"] {
                guard case .bool(let isOn) = value else {
                    fail(path + ".repeat", "must be true or false")
                    return nil
                }
                repeats = isOn
            }
            let binding = KeyBinding(keyCode: code, mods: CGEventFlags(rawValue: UInt64(flags.rawValue)),
                                     dispatcher: dispatcher, arg: arg, submap: submap, repeats: repeats)
            let mods = ConfigScript.mods.filter { flags.contains($0.flag) }.map(\.conf).joined(separator: " ")
            let row = BindRow(mods: mods, key: key.lowercased(), dispatcher: dispatcher, args: arg, submap: submap,
                              kind: repeats ? "binde" : "bind")
            return (binding, row)
        }

        private mutating func run(_ value: JSON?, path: String) -> (String, String)? {
            let parts = value?.string.map { [JSON.string($0)] } ?? value?.array ?? []
            guard let name = parts.first?.string else {
                fail(path, "must name an action, such as \"sort\" or [\"workspace\", \"2\"]")
                return nil
            }
            guard Actions.dispatchers.contains(name.lowercased()) else {
                fail(path, "is an unknown action `\(name)`")
                return nil
            }
            var args: [String] = []
            for part in parts.dropFirst() {
                switch part {
                case .string(let text): args.append(text)
                case .int(let number): args.append("\(number)")
                case .number(let number): args.append("\(number)")
                default:
                    fail(path, "arguments must be strings or numbers")
                    return nil
                }
            }
            return (name.lowercased(), args.joined(separator: ", "))
        }
    }
}
