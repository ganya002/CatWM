import AppKit

package enum ConfigMigration {
    package static let note = "catwm migration:"

    package static func typescript(from text: String, header: [String]) -> String {
        var reader = MigrationReader(Config.parse(text))
        for line in text.components(separatedBy: .newlines) { reader.read(line) }
        return reader.render(header: header)
    }
}

private struct MigrationVariable {
    package let name: String
    package let identifier: String
    package let value: String
    package let mods: [String]?
}

private indirect enum MigrationEntry {
    case leaf(key: String, value: String, comments: [String])
    case group(key: String, entries: [MigrationEntry], comments: [String])

    package var key: String {
        switch self {
        case .leaf(let key, _, _), .group(let key, _, _): key
        }
    }
}

private struct MigrationBind {
    package let submap: String
    package let comments: [String]
    package let objects: [String]
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
        case "enabled", "animations": "animation.enabled"
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
        let mods = modsLiteral(raw.mods)
        let repeats = ["binde", "bindel", "bindle"].contains(kind)
        let objects = pairs.map { pair in
            var fields: [String] = []
            if let mods { fields.append("mods: \(mods)") }
            let key = pair.key.lowercased()
            fields.append("key: " + ConfigScript.quoted(ConfigScript.keyAliases[key] ?? key))
            let arg = pairs.count == 1 ? argLiteral(raw: raw.args, expanded: pair.arg) : ConfigScript.quoted(pair.arg)
            fields.append("run: " + (pair.arg.isEmpty
                ? ConfigScript.quoted(row.dispatcher) : "[\(ConfigScript.quoted(row.dispatcher)), \(arg)]"))
            if repeats { fields.append("repeat: true") }
            return "{ " + fields.joined(separator: ", ") + " }"
        }
        binds.append(MigrationBind(submap: submap, comments: comments + comment, objects: objects))
        comments = []
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
        var out = header + ["import type { Config } from \"./catwm\"", ""]
        for variable in variables {
            out += variableComments[variable.identifier] ?? []
            let value = variable.mods.map { mods in
                mods.count == 1 ? ConfigScript.quoted(mods[0])
                    : "[" + mods.map(ConfigScript.quoted).joined(separator: ", ") + "] as const"
            } ?? ConfigScript.quoted(variable.value)
            out.append("const \(variable.identifier) = \(value)")
        }
        if !variables.isEmpty { out.append("") }
        out.append("export default {")
        var entries: [MigrationEntry] = []
        if let first = variables.first(where: { $0.name.lowercased().contains("mod") && $0.mods != nil }),
           let mod = variables.last(where: { $0.name == first.name && $0.mods != nil }) {
            entries.append(.leaf(key: "mod", value: mod.identifier, comments: []))
        }
        let split = paths.contains { $0.path.hasPrefix("padding.") }
        for (path, comments) in paths {
            if path == "padding", split {
                let sides = ["left", "right", "top", "bottom"]
                for side in sides where !paths.contains(where: { $0.path == "padding." + side }) {
                    insert("padding." + side, comments: side == "left" ? comments : [], into: &entries)
                }
            } else {
                insert(path, comments: comments, into: &entries)
            }
        }
        out += lines(entries, indent: 2)
        for (index, submap) in ([""] + submapNames).enumerated() {
            let rows = binds.filter { $0.submap == submap }
            let pad = submap.isEmpty ? "    " : "      "
            if index == 1 { out.append("  submaps: {") }
            out.append(submap.isEmpty ? "  binds: [" : "    \(ConfigScript.property(submap)): [")
            for bind in rows { out += bind.comments.map { pad + $0 } + bind.objects.map { pad + $0 + "," } }
            out.append(submap.isEmpty ? "  ]," : "    ],")
        }
        if !submapNames.isEmpty { out.append("  },") }
        out += comments.map { "  " + $0 }
        out.append("} satisfies Config")
        return out.joined(separator: "\n") + "\n"
    }

    private var submapNames: [String] {
        var names: [String] = []
        for bind in binds where !bind.submap.isEmpty && !names.contains(bind.submap) { names.append(bind.submap) }
        return names
    }

    private func value(_ path: String) -> JSON {
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

    private func insert(_ path: String, comments: [String], into entries: inout [MigrationEntry]) {
        insert(path.split(separator: ".").map(String.init), full: path, comments: comments, into: &entries)
    }

    private func insert(_ parts: [String], full: String, comments: [String], into entries: inout [MigrationEntry]) {
        guard let first = parts.first else { return }
        guard parts.count > 1 else {
            let depth = full.split(separator: ".").count * 2
            let literal = ConfigScript.literal(value(full), indent: depth)
            entries.append(.leaf(key: first, value: literal, comments: comments))
            return
        }
        if let index = entries.firstIndex(where: { $0.key == first }),
           case .group(let key, var children, let groupComments) = entries[index] {
            insert(Array(parts.dropFirst()), full: full, comments: comments, into: &children)
            entries[index] = .group(key: key, entries: children, comments: groupComments)
        } else {
            var children: [MigrationEntry] = []
            insert(Array(parts.dropFirst()), full: full, comments: comments, into: &children)
            entries.append(.group(key: first, entries: children, comments: []))
        }
    }

    private func lines(_ entries: [MigrationEntry], indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        return entries.flatMap { entry -> [String] in
            switch entry {
            case .leaf(let key, let value, let comments):
                let line = key == value ? key : "\(ConfigScript.property(key)): \(value)"
                return comments.map { pad + $0 } + [pad + line + ","]
            case .group(let key, let children, let comments):
                return comments.map { pad + $0 } + [pad + ConfigScript.property(key) + ": {"]
                    + lines(children, indent: indent + 2) + [pad + "},"]
            }
        }
    }
}
