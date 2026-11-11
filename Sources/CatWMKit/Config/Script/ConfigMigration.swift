import AppKit

package enum ConfigMigration {
    package static let note = "catwm migration:"

    package static func typescript(from text: String, header: [String]) -> String {
        var reader = MigrationReader(Config.parse(text))
        for line in text.components(separatedBy: .newlines) { reader.read(line) }
        return reader.render(header: header)
    }

    package static func typescript(from value: [String: JSON], header: [String]) -> String {
        var reader = MigrationReader(Config())
        reader.read(value)
        return reader.render(header: header)
    }

    package static func renamed(_ value: [String: JSON]) -> [String: JSON] {
        var value = value
        let groupsFirst = ConfigScript.renamed.filter { !$0.key.contains(".") }
            .sorted { ($0.value.split(separator: ".").count, $0.key) < ($1.value.split(separator: ".").count, $1.key) }
        for (old, new) in groupsFirst {
            guard let moved = value.removeValue(forKey: old) else { continue }
            ConfigScript.set(moved, at: new, in: &value)
        }
        return value
    }
}

private struct MigrationVariable {
    package let name: String
    package let identifier: String
    package let value: String
    package let mods: [String]?
}

private struct MigrationBind {
    package let submap: String
    package let comments: [String]
    package let calls: [String]
}

private struct MigrationReader {
    package let parsed: Config
    package var comments: [String] = []
    package var variables: [MigrationVariable] = []
    package var paths: [(path: String, comments: [String])] = []
    package var binds: [MigrationBind] = []
    package var submap = ""
    package var blocks: [String] = []
    package var resolved: [(String, String)] = []
    package var variableComments: [String: [String]] = [:]
    package var given: [String: JSON] = [:]

    package init(_ parsed: Config) { self.parsed = parsed }
}

extension MigrationReader {
    package mutating func read(_ raw: String) {
        let parts = ConfigText.commentParts(raw)
        let line = parts.value.trimmingCharacters(in: .whitespaces)
        let comment = comment(parts.comment)
        if line.hasSuffix("{") {
            blocks.append(String(line.dropLast()).trimmingCharacters(in: .whitespaces))
        } else if line == "}" {
            _ = blocks.popLast()
        }
        if line.isEmpty || line.hasSuffix("{") || line == "}" {
            comments += comment
            return
        }
        guard let equals = line.firstIndex(of: "=") else { return unknown(raw, "expected `key = value`") }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        let expanded = expand(value)
        if key.hasPrefix("$") { return variable(key, value: expanded, comment: comment) }
        if key.lowercased() == "submap" {
            submap = expanded.lowercased() == "reset" ? "" : expanded
            comments += comment
            return
        }
        assign(key, value: value, expanded: expanded, raw: raw, comment: comment)
    }

    private mutating func assign(_ key: String, value: String, expanded: String, raw: String, comment: [String]) {
        var probe = Config()
        probe.currentSubmap = submap
        if let error = probe.apply((blocks + [key]).joined(separator: ":"), expanded) { return unknown(raw, error) }
        let lower = key.lowercased()
        if lower.hasPrefix("bind") {
            guard lower != "bindm" else { return unknown(raw, "mouse binds are not supported") }
            return bind(lower, value: value, expanded: expanded, raw: raw, comment: comment)
        }
        guard let path = Self.path(String(key.split(separator: ":").last ?? Substring(key))) else {
            return unknown(raw, "unknown option")
        }
        if let index = paths.firstIndex(where: { $0.path == path }) {
            paths[index].comments += comments + comment
        } else {
            paths.append((path, comments + comment))
        }
        comments = []
    }

    private static func path(_ key: String) -> String? {
        switch ConfigOption.norm(key) {
        case "layouts": "layouts"
        case "floating": "floating.apps"
        case "gaps_in": "gaps.size"
        case "screen_padding", "gaps_out": "padding"
        case "enabled", "animations": "motion.enabled"
        default: ConfigOption.named(key)?.script
        }
    }

    private func comment(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return [] }
        return ["//" + trimmed.dropFirst().replacingOccurrences(of: "##", with: "#")]
    }

    private mutating func unknown(_ raw: String, _ reason: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        comments.append("// \(ConfigMigration.note) not converted (\(reason)): \(line)")
    }

    private func expand(_ value: String) -> String {
        var expanded = value
        for (name, replacement) in resolved { expanded = expanded.replacingOccurrences(of: name, with: replacement) }
        return expanded
    }

    private mutating func variable(_ name: String, value: String, comment: [String]) {
        resolved.removeAll { $0.0 == name }
        resolved.append((name, value))
        resolved.sort { $0.0.count > $1.0.count }
        let flags = ConfigText.flags(value)
        let mods = flags.flatMap { flags in
            flags.isEmpty ? nil : ConfigScript.mods.filter { flags.contains($0.flag) }.map(\.name)
        }
        variables.append(MigrationVariable(name: name, identifier: identifier(name), value: value, mods: mods))
        comments += comment
        if !comments.isEmpty {
            variableComments[variables[variables.count - 1].identifier] = comments
            comments = []
        }
    }

    private func identifier(_ name: String) -> String {
        let reserved: Set<String> = ["break", "case", "catch", "class", "const", "continue", "debugger", "default",
                                     "delete", "do", "else", "export", "extends", "false", "finally", "for",
                                     "function", "if", "import", "in", "instanceof", "new", "null", "return",
                                     "super", "switch", "this", "throw", "true", "try", "typeof", "var", "void",
                                     "while", "with", "let", "static", "yield", "await", "enum"]
        var text = String(name.dropFirst()).map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "_" }.joined()
        if text.first?.isNumber == true { text = "_" + text }
        if text.isEmpty || reserved.contains(text) { text = "_" + text }
        let taken = Set(variables.map(\.identifier))
        var candidate = text, number = 2
        while taken.contains(candidate) {
            candidate = text + String(number)
            number += 1
        }
        return candidate
    }

    private mutating func bind(_ kind: String, value: String, expanded: String, raw line: String, comment: [String]) {
        guard let row = BindRow(value: expanded, kind: kind, submap: submap),
              let raw = BindRow(value: value, kind: kind, submap: submap),
              case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args)
        else { return }
        guard Actions.dispatchers.contains(row.dispatcher) else { return unknown(line, "unknown action") }
        let repeats = ["binde", "bindel", "bindle"].contains(kind)
        let calls = pairs.map { pair in
            let arg = pairs.count == 1 ? argLiteral(raw: raw.args, expanded: pair.arg) : ConfigScript.quoted(pair.arg)
            let run = pair.arg.isEmpty
                ? ConfigScript.quoted(row.dispatcher) : "[\(ConfigScript.quoted(row.dispatcher)), \(arg)]"
            return Self.call(mods: modsLiteral(raw.mods) ?? "[]", key: pair.key, run: run, submap: submap,
                             repeats: repeats)
        }
        binds.append(MigrationBind(submap: submap, comments: comments + comment, calls: calls))
        comments = []
    }

    private static func call(mods: String, key: String, run: String, submap: String, repeats: Bool) -> String {
        let options = (submap.isEmpty ? [] : ["submap: " + ConfigScript.quoted(submap)])
            + (repeats ? ["repeat: true"] : [])
        let tail = options.isEmpty ? "" : ", { " + options.joined(separator: ", ") + " }"
        let key = key.lowercased()
        let name = ConfigScript.quoted(ConfigScript.keyAliases[key] ?? key)
        return "catwm.bind(\(mods), \(name), " + run + tail + ")"
    }

    package mutating func read(_ object: [String: JSON]) {
        for path in ConfigScript.paths(object) {
            switch path {
            case "binds": binds(object[path]?.array ?? [], submap: "")
            case "submaps":
                let modes = object[path]?.object ?? [:]
                for name in modes.keys.sorted() { binds(modes[name]?.array ?? [], submap: name) }
            default:
                let json = path.split(separator: ".").reduce(JSON.object(object)) { $0.object?[String($1)] ?? .null }
                given[path] = json
                paths.append((path, []))
            }
        }
    }

    private mutating func binds(_ list: [JSON], submap: String) {
        let calls = list.compactMap { item -> String? in
            guard let bind = item.object, let key = bind["key"]?.string, let run = bind["run"] else { return nil }
            let mods = (bind["mods"]?.array ?? bind["mods"].map { [$0] } ?? []).compactMap(\.string)
            let action = run.array.map { "[" + $0.map { ConfigScript.literal($0) }.joined(separator: ", ") + "]" }
                ?? ConfigScript.literal(run)
            return Self.call(mods: ConfigScript.literal(.array(mods.map(JSON.string))), key: key, run: action,
                             submap: submap, repeats: bind["repeat"] == .bool(true))
        }
        self.binds.append(MigrationBind(submap: submap, comments: [], calls: calls))
    }

    private func modsLiteral(_ text: String) -> String? {
        var items: [String] = []
        for token in text.split(whereSeparator: { " _+".contains($0) }).map(String.init) {
            if let variable = variables.last(where: { $0.name == token }), let mods = variable.mods {
                items.append(mods.count == 1 ? variable.identifier : "..." + variable.identifier)
            } else if let flags = ConfigText.flags(expand(token)) {
                for mod in ConfigScript.mods where flags.contains(mod.flag) {
                    let name = ConfigScript.quoted(mod.name)
                    if !items.contains(name) { items.append(name) }
                }
            }
        }
        return items.isEmpty ? nil : "[" + items.joined(separator: ", ") + "]"
    }

    private func argLiteral(raw: String, expanded: String) -> String {
        let names = Set(variables.map(\.name))
        let used = names.compactMap { name in variables.last { $0.name == name } }
            .filter { $0.mods == nil && raw.contains($0.name) }
        guard !used.isEmpty else { return ConfigScript.quoted(expanded) }
        var text = raw.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        for variable in used.sorted(by: { $0.name.count > $1.name.count }) {
            text = text.replacingOccurrences(of: variable.name, with: "${\(variable.identifier)}")
        }
        return "`" + text + "`"
    }

    package func render(header: [String]) -> String {
        var out = header + ["import { catwm } from \"./catwm\"", ""]
        for variable in variables {
            out += variableComments[variable.identifier] ?? []
            let value = variable.mods.map { mods in
                mods.count == 1 ? ConfigScript.quoted(mods[0])
                    : "[" + mods.map(ConfigScript.quoted).joined(separator: ", ") + "] as const"
            } ?? ConfigScript.quoted(variable.value)
            out.append("const \(variable.identifier) = \(value)")
        }
        if !variables.isEmpty { out.append("") }
        if let first = variables.first(where: { $0.name.lowercased().contains("mod") && $0.mods != nil }),
           let mod = variables.last(where: { $0.name == first.name && $0.mods != nil }) {
            out.append("catwm.mod = \(mod.identifier)")
        }
        let split = paths.contains { $0.path.hasPrefix("padding.") }
        for (path, comments) in paths {
            if path == "padding", split {
                let sides = ["left", "right", "top", "bottom"]
                for side in sides where !paths.contains(where: { $0.path == "padding." + side }) {
                    out += setter("padding." + side, comments: side == "left" ? comments : [])
                }
            } else {
                out += setter(path, comments: comments)
            }
        }
        for submap in [""] + submapNames {
            for bind in binds.filter({ $0.submap == submap }) { out += bind.comments + bind.calls }
        }
        out += comments
        return out.joined(separator: "\n") + "\n"
    }

    private func setter(_ path: String, comments: [String]) -> [String] {
        comments + ["catwm.\(path) = " + ConfigScript.literal(value(path))]
    }

    private var submapNames: [String] {
        var names: [String] = []
        for bind in binds where !bind.submap.isEmpty && !names.contains(bind.submap) { names.append(bind.submap) }
        return names
    }

    private func value(_ path: String) -> JSON {
        if let json = given[path] { return json }
        switch path {
        case "layouts": return .array(parsed.layouts.map { .string($0.rawValue) })
        case "floating.apps": return .array(parsed.floating.map(JSON.string))
        case "padding":
            let sides = [parsed.paddingLeft, parsed.paddingRight, parsed.paddingTop, parsed.paddingBottom]
            if Set(sides).count == 1, let option = ConfigOption.named("screen-padding-left") {
                return ConfigScript.json(option, in: parsed)
            }
            return .object(Dictionary(uniqueKeysWithValues: ["left", "right", "top", "bottom"].compactMap { side in
                ConfigOption.named("screen-padding-" + side).map { (side, ConfigScript.json($0, in: parsed)) }
            }))
        default:
            guard let option = Options.all.first(where: { $0.script == path }) else { return .null }
            return ConfigScript.json(option, in: parsed)
        }
    }
}
