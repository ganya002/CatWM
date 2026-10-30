import AppKit

struct ConfigText {
    private struct Assignment {
        let key: String
        let blocks: [String]
        var fullKey: String { (blocks + [key]).joined(separator: ":") }
        var optionKeys: [String] {
            switch ConfigOption.norm(key) {
            case "screen_padding", "gaps_out":
                return ["screen-padding-left", "screen-padding-right", "screen-padding-top", "screen-padding-bottom"]
            case "gaps_in": return ["window-margin-size"]
            default: return [optionKey]
            }
        }

        var optionKey: String {
            if fullKey.lowercased() == "animations:enabled" { return "animate" }
            return ConfigOption.named(key)?.key ?? ConfigOption.norm(key)
        }
    }

    private struct Line {
        var raw: String
        var ending: String
        var assignment: Assignment?
        var bind: BindRow?
        var settingValue: String?

        func removingAssignment() -> Self {
            var copy = self
            copy.raw = ConfigText.commentParts(raw).comment.trimmingCharacters(in: .whitespaces)
            return copy
        }

        func replacing(key: String? = nil, value: String) -> Self {
            guard let equals = raw.firstIndex(of: "=") else { return self }
            var copy = self
            let prefix = key.map { name in String(raw.prefix(while: \.isWhitespace)) + name + " " }
                ?? String(raw[..<equals])
            let suffix = ConfigText.commentParts(raw).comment
            copy.raw = prefix + "= " + ConfigText.escape(value) + suffix
            return copy
        }
    }

    private var lines: [Line] = []
    private(set) var config = Config()
    private(set) var vars: [VarRow] = []
    private(set) var binds: [BindRow] = []
    private(set) var extraLines: [String] = []

    init(_ text: String) {
        var start = text.startIndex
        for index in text.indices where text[index].isNewline {
            lines.append(Line(raw: String(text[start..<index]), ending: String(text[index])))
            start = text.index(after: index)
        }
        if start < text.endIndex { lines.append(Line(raw: String(text[start...]), ending: "")) }
        var reader = Reader()
        for index in lines.indices { read(index, reader: &reader) }
        for block in reader.blocks {
            config.errors.append("line \(block.line): block `\(block.name)` is missing a closing `}`")
        }
        config.reportEmptySubmaps()
    }

    private struct Reader {
        var resolved: [(String, String)] = []
        var blocks: [(name: String, line: Int)] = []
        var modVar: String?
    }

    private mutating func read(_ index: Int, reader: inout Reader) {
        let raw = lines[index].raw
        let line = Self.commentParts(raw).value.trimmingCharacters(in: .whitespaces)
        if readBlock(line, number: index + 1, reader: &reader) { return }
        if line.isEmpty { return }
        guard let equals = line.firstIndex(of: "=") else {
            config.errors.append("line \(index + 1): expected `key = value`")
            extraLines.append(raw)
            return
        }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        var expanded = value
        for (name, replacement) in reader.resolved {
            expanded = expanded.replacingOccurrences(of: name, with: replacement)
        }
        let assignment = Assignment(key: key, blocks: reader.blocks.map(\.name))
        lines[index].assignment = assignment
        if key.hasPrefix("$") { return readVariable(key, value: value, expanded: expanded, reader: &reader) }
        if key.lowercased() == "submap" {
            config.currentSubmap = expanded.lowercased() == "reset" ? "" : expanded
            lines[index].settingValue = expanded == value ? nil : expanded
            return
        }
        if key.lowercased().hasPrefix("bind") { readBind(index, key: key, value: value) }
        if let error = config.apply(assignment.fullKey, expanded) {
            config.errors.append("line \(index + 1): \(error)")
            if lines[index].bind == nil { extraLines.append(raw) }
        } else {
            lines[index].settingValue = lines[index].bind == nil && expanded != value ? expanded : nil
        }
    }

    private mutating func readBlock(_ line: String, number: Int, reader: inout Reader) -> Bool {
        if line.hasSuffix("{") {
            reader.blocks.append((String(line.dropLast()).trimmingCharacters(in: .whitespaces), number))
            return true
        }
        guard line == "}" else { return false }
        if reader.blocks.popLast() == nil {
            config.errors.append("line \(number): unexpected `}` (no open block)")
        }
        return true
    }

    private mutating func readVariable(_ key: String, value: String, expanded: String, reader: inout Reader) {
        vars.removeAll { $0.name == key }
        vars.append(VarRow(name: key, value: value))
        reader.resolved.removeAll { $0.0 == key }
        reader.resolved.append((key, expanded))
        reader.resolved.sort { $0.0.count > $1.0.count }
        if key.lowercased().contains("mod"), (reader.modVar ?? key) == key, let flags = Self.flags(expanded) {
            reader.modVar = key
            config.mainMod = CGEventFlags(rawValue: UInt64(flags.rawValue))
        }
    }

    private mutating func readBind(_ index: Int, key: String, value: String) {
        guard key.lowercased() != "bindm",
              let row = BindRow(value: value, kind: key.lowercased(), submap: config.currentSubmap) else {
            extraLines.append(lines[index].raw)
            return
        }
        binds.append(row)
        lines[index].bind = row
    }

    static func keyboard(vars: [VarRow], binds: [BindRow]) -> String {
        var lines = vars.map { "\($0.name) = \(escape($0.value))" }
        var mode = ""
        for row in binds {
            if row.submap != mode {
                mode = row.submap
                lines.append("submap = \(mode.isEmpty ? "reset" : mode)")
            }
            lines.append("\(row.kind) = \(escape(row.value))")
        }
        if !mode.isEmpty { lines.append("submap = reset") }
        return lines.joined(separator: "\n") + "\n"
    }

    static func commentParts(_ text: String) -> (value: String, comment: String) {
        var value = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let next = text.index(after: cursor)
            if text[cursor] == "#" {
                if next < text.endIndex && text[next] == "#" {
                    value.append("#")
                    cursor = text.index(after: next)
                    continue
                }
                let spaces = text[..<cursor].reversed().prefix(while: \.isWhitespace).reversed()
                return (value, String(spaces) + text[cursor...])
            }
            value.append(text[cursor])
            cursor = next
        }
        return (value, "")
    }

    static func escape(_ value: String) -> String { value.replacingOccurrences(of: "#", with: "##") }

    static func flags(_ mods: String) -> NSEvent.ModifierFlags? {
        var flags: NSEvent.ModifierFlags = []
        for token in mods.uppercased().split(whereSeparator: { " _+".contains($0) }) {
            switch token {
            case "SUPER", "CMD", "COMMAND", "WIN", "META", "MOD4": flags.insert(.command)
            case "ALT", "OPT", "OPTION", "MOD1": flags.insert(.option)
            case "CTRL", "CONTROL": flags.insert(.control)
            case "SHIFT": flags.insert(.shift)
            default: return nil
            }
        }
        return flags
    }

    func materializingSettings() -> Self {
        var edited = lines
        for index in lines.indices {
            if let value = lines[index].settingValue {
                edited[index] = lines[index].replacing(value: value)
            }
        }
        return Self(Self.text(edited))
    }

    func setting(option key: String, to value: String) -> String {
        var edited = lines
        set(option: key, value: value, in: &edited, replacementKey: key)
        return Self.text(edited)
    }

    func editing(config editedConfig: Config, vars editedVars: [VarRow], binds editedBinds: [BindRow]) -> String {
        var edited = lines
        for option in Options.all where option.text(config) != option.text(editedConfig) {
            set(option: option.key, value: option.text(editedConfig), in: &edited)
        }
        if config.layouts != editedConfig.layouts {
            Self.append("layouts = " + editedConfig.layouts.map(\.rawValue).joined(separator: ", "), to: &edited)
        }
        if config.floating != editedConfig.floating {
            Self.append("floating = " + Self.escape(editedConfig.floating.joined(separator: ", ")), to: &edited)
        }
        let addedVars = editVariables(editedVars, in: &edited)
        editBinds(editedBinds, in: &edited)
        let newline = lines.first(where: { !$0.ending.isEmpty })?.ending ?? "\n"
        return addedVars.map { $0 + newline }.joined() + Self.text(edited)
    }
}

extension ConfigText {
    private func set(option key: String, value: String, in edited: inout [Line], replacementKey: String? = nil) {
        let canonical = ConfigOption.named(key)?.key ?? ConfigOption.norm(key)
        if let index = lines.lastIndex(where: { $0.assignment?.optionKeys.contains(canonical) == true }),
           lines[index].assignment?.optionKey == canonical {
            let inBlock = lines[index].assignment?.blocks.isEmpty == false
            edited[index] = lines[index].replacing(key: inBlock ? nil : replacementKey, value: value)
        } else {
            Self.append("\(key) = \(Self.escape(value))", to: &edited)
        }
    }

    private func editVariables(_ editedVars: [VarRow], in edited: inout [Line]) -> [String] {
        var added: [String] = []
        for variable in editedVars {
            if let original = vars.first(where: { $0.name == variable.name }) {
                if variable != original,
                   let index = lines.lastIndex(where: { $0.assignment?.key == variable.name }) {
                    edited[index] = lines[index].replacing(value: variable.value)
                }
            } else {
                added.append("\(variable.name) = \(Self.escape(variable.value))")
            }
        }
        for index in lines.indices {
            if let name = lines[index].assignment?.key, name.hasPrefix("$"),
               !editedVars.contains(where: { $0.name == name }) { edited[index] = lines[index].removingAssignment() }
        }
        return added
    }

    private func editBinds(_ editedBinds: [BindRow], in edited: inout [Line]) {
        for index in lines.indices {
            guard let original = lines[index].bind else { continue }
            guard let row = editedBinds.first(where: { $0.id == original.id }), row.submap == original.submap else {
                edited[index] = lines[index].removingAssignment()
                continue
            }
            if row != original { edited[index] = lines[index].replacing(key: row.kind, value: row.value) }
        }
        let added = editedBinds.filter { row in !binds.contains { $0.id == row.id && $0.submap == row.submap } }
        guard !added.isEmpty else { return }
        Self.append("submap = reset", to: &edited)
        for row in added {
            if !row.submap.isEmpty { Self.append("submap = \(row.submap)", to: &edited) }
            Self.append("\(row.kind) = \(Self.escape(row.value))", to: &edited)
            if !row.submap.isEmpty { Self.append("submap = reset", to: &edited) }
        }
    }

    private static func append(_ raw: String, to lines: inout [Line]) {
        let newline = lines.first(where: { !$0.ending.isEmpty })?.ending ?? "\n"
        if let last = lines.indices.last, lines[last].ending.isEmpty { lines[last].ending = newline }
        lines.append(Line(raw: raw, ending: newline))
    }

    private static func text(_ lines: [Line]) -> String { lines.map { $0.raw + $0.ending }.joined() }
}

struct VarRow: Equatable {
    var name: String
    var value: String
}

struct BindRow: Identifiable, Equatable {
    let id = UUID()
    var mods: String
    var key: String
    var dispatcher: String
    var args: String
    var submap = ""
    var kind = "bind"
}

extension BindRow {
    init?(value: String, kind: String, submap: String) {
        let parts = value.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return nil }
        self.init(mods: parts[0], key: parts[1], dispatcher: parts[2].lowercased(),
                  args: parts.count > 3 ? parts[3] : "", submap: submap, kind: kind)
    }

    var value: String {
        "\(mods), \(key), \(dispatcher)" + (args.isEmpty ? "" : ", \(args)")
    }
}
