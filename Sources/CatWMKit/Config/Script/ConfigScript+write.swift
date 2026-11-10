import AppKit

extension ConfigScript {
    package static func json(_ option: ConfigOption, in config: Config) -> JSON {
        let text = option.text(config)
        switch option.scriptKind {
        case .bool: return .bool(text == "true")
        case .number:
            let number = option.number(config)
            return number.rounded() == number && abs(number) < 1e15 ? .int(Int(number)) : .number(number)
        case .string: return .string(text)
        case .strings: return .array(Config.listItems(text).map(JSON.string))
        }
    }

    package static func modNames(_ flags: CGEventFlags) -> [String] {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
        return mods.filter { flags.contains($0.flag) }.map(\.name)
    }

    package static func json(mod flags: CGEventFlags) -> JSON {
        let names = modNames(flags)
        return names.count == 1 ? .string(names[0]) : .array(names.map(JSON.string))
    }

    package static func keyName(_ code: UInt16) -> String? { keyNames.first { keyCodes[$0] == code } }

    package static func json(_ binding: KeyBinding) -> JSON {
        var bind: [String: JSON] = [
            "key": .string(keyName(binding.keyCode) ?? "\(binding.keyCode)"),
            "run": binding.arg.isEmpty
                ? .string(binding.dispatcher) : .array([.string(binding.dispatcher), .string(binding.arg)])
        ]
        let mods = modNames(binding.mods)
        if !mods.isEmpty { bind["mods"] = .array(mods.map(JSON.string)) }
        if binding.repeats { bind["repeat"] = .bool(true) }
        return .object(bind)
    }

    package static func json(binds bindings: [KeyBinding]) -> (binds: JSON, submaps: JSON) {
        var submaps: [String: [JSON]] = [:]
        for binding in bindings where !binding.submap.isEmpty {
            submaps[binding.submap, default: []].append(json(binding))
        }
        return (.array(bindings.filter(\.submap.isEmpty).map(json)), .object(submaps.mapValues(JSON.array)))
    }

    package static func set(_ value: JSON, at path: String, in object: inout [String: JSON]) {
        var parts = path.split(separator: ".").map(String.init)
        let last = parts.removeLast()
        guard let first = parts.first else {
            object[last] = value
            return
        }
        var child = object[first]?.object ?? [:]
        set(value, at: (parts.dropFirst() + [last]).joined(separator: "."), in: &child)
        object[first] = .object(child)
    }

    @discardableResult
    package static func remove(_ path: String, from object: inout [String: JSON]) -> Bool {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first else { return false }
        guard parts.count > 1 else { return object.removeValue(forKey: first) != nil }
        guard var child = object[first]?.object,
              remove(parts.dropFirst().joined(separator: "."), from: &child) else { return false }
        object[first] = child.isEmpty ? nil : .object(child)
        return true
    }

    package static func paths(_ object: [String: JSON], prefix: String = "") -> [String] {
        object.keys.sorted().flatMap { key -> [String] in
            let path = prefix.isEmpty ? key : prefix + "." + key
            if let child = object[key]?.object, groups[path] != nil { return paths(child, prefix: path) }
            return [path]
        }
    }

    package static func label(_ path: String) -> String {
        if let option = Options.all.first(where: { $0.script == path }) { return option.setting?.label ?? path }
        switch path {
        case "binds", "submaps": return "Shortcuts"
        case "mod": return "Main modifier"
        case "layouts": return "Layouts"
        case "floating.apps": return "Floating apps"
        default: return path
        }
    }

    package static func literal(_ value: JSON, indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent + 2), end = String(repeating: " ", count: indent)
        switch value {
        case .null: return "null"
        case .bool(let isOn): return isOn ? "true" : "false"
        case .int(let number): return "\(number)"
        case .number(let number): return "\(number)"
        case .string(let text): return quoted(text)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let flat = "[" + items.map { literal($0) }.joined(separator: ", ") + "]"
            if !flat.contains("\n"), flat.count + indent < 100 { return flat }
            return "[\n" + items.map { pad + literal($0, indent: indent + 2) + ",\n" }.joined() + end + "]"
        case .object(let fields):
            if fields.isEmpty { return "{}" }
            let rows = fields.keys.sorted().map { key in
                property(key) + ": " + literal(fields[key] ?? .null, indent: indent + 2)
            }
            let flat = "{ " + rows.joined(separator: ", ") + " }"
            if !flat.contains("\n"), flat.count + indent < 100 { return flat }
            return "{\n" + rows.map { pad + $0 + ",\n" }.joined() + end + "}"
        }
    }

    package static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(text), let quoted = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return quoted
    }

    package static func property(_ key: String) -> String {
        key.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#, options: .regularExpression) != nil ? key : quoted(key)
    }
}
