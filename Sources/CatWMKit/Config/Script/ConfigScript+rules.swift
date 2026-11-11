import Foundation

extension ConfigScript {
    package static func defaults(for config: Config) -> JSON {
        var root: [String: JSON] = [
            "binds": .array([]), "submaps": .object([:]), "windowRules": .array([]), "workspaceRules": .array([])
        ]
        for (path, leaf) in leaves {
            switch leaf {
            case .option(let option): set(json(option, in: config), at: path, in: &root)
            case .mod: root[path] = json(mod: config.mainMod)
            case .layouts: root[path] = .array(config.layouts.map { .string($0.rawValue) })
            case .floatingApps: set(.array(config.floating.map(JSON.string)), at: path, in: &root)
            case .feature(let feature): set(.bool(config.features.contains(feature)), at: path, in: &root)
            case .padding, .binds, .submaps, .windowRules, .workspaceRules: continue
            }
        }
        return .object(root)
    }

    package static func renamingOverrides(_ overrides: [String: JSON]) -> [String: JSON] {
        var result = overrides
        for (old, new) in renamed where old != "animation" {
            guard let value = value(at: old, in: result) else { continue }
            remove(old, from: &result)
            set(value, at: new, in: &result)
        }
        return result
    }

    private static func value(at path: String, in object: [String: JSON]) -> JSON? {
        var current: JSON? = .object(object)
        for part in path.split(separator: ".") { current = current?[String(part)] }
        return current
    }
}

extension ConfigScript.Reader {
    private enum Field {
        case glob, text, textOrRegex, number, bool, count, layout
    }

    private static let windowFields: [String: (Fact, Field)] = [
        "app": (.app, .glob), "title": (.title, .textOrRegex), "pid": (.pid, .number),
        "workspace": (.workspace, .text), "display": (.display, .text), "floating": (.floating, .bool),
        "minimized": (.minimized, .bool), "fullscreen": (.fullscreen, .bool)
    ]

    private static let workspaceFields: [String: (Fact, Field)] = [
        "windows": (.windows, .count), "sameApp": (.sameApp, .count), "app": (.apps, .glob),
        "layout": (.layout, .layout), "name": (.name, .text), "display": (.display, .text),
        "focused": (.focused, .bool)
    ]

    mutating func readWindowRules(_ value: JSON, into config: inout Config) {
        config.windowRules = []
        guard let list = value.array else { return fail("windowRules", "must be a list") }
        for (index, item) in list.enumerated() {
            let name = "catwm.windows rule \(index + 1)"
            guard let match = item["match"]?.object, let actions = item["set"]?.array else {
                fail("", "\(name) is not a valid rule")
                continue
            }
            guard let condition = condition(match, Self.windowFields, name: name) else { continue }
            var parsed: [RuleAction] = []
            for (number, action) in actions.enumerated() {
                guard let (dispatcher, arg) = run(action, path: "\(name) action \(number + 1)") else { break }
                parsed.append(RuleAction(dispatcher: dispatcher, arg: arg))
            }
            if parsed.count == actions.count { config.windowRules.append(WindowRule(when: condition, actions: parsed)) }
        }
    }

    mutating func readWorkspaceRules(_ value: JSON, into config: inout Config) {
        config.workspaceRules = []
        guard let list = value.array else { return fail("workspaceRules", "must be a list") }
        for (index, item) in list.enumerated() {
            let name = "catwm.workspaces rule \(index + 1)"
            guard let match = item["match"]?.object, let set = item["set"]?.object else {
                fail("", "\(name) is not a valid rule")
                continue
            }
            guard let condition = condition(match, Self.workspaceFields, name: name) else { continue }
            if let layout = match["layout"], let layouts = set["layouts"]?.array, !layouts.contains(layout) {
                fail("", "\(name) matches a layout that its `layouts` leaves out, so it would switch back and forth")
                continue
            }
            let before = diagnostics.count
            for path in set.keys.sorted() {
                guard let leaf = ConfigScript.leaves[path] else {
                    fail("", "\(name) sets `\(path)`, which is not a CatWM option")
                    continue
                }
                guard leaf.isScoped else {
                    let scoped = ConfigScript.leaves.filter(\.value.isScoped).keys.sorted().joined(separator: ", ")
                    fail("", "\(name) can't set `\(path)`. A workspace rule can set only \(scoped)")
                    continue
                }
                var scratch = Config()
                read(leaf, set[path] ?? .null, path: path, into: &scratch)
            }
            if diagnostics.count == before {
                config.workspaceRules.append(WorkspaceRule(when: condition, set: set))
            }
        }
    }

    private mutating func condition(_ match: [String: JSON], _ fields: [String: (Fact, Field)],
                                    name: String) -> Condition? {
        var conditions: [Condition] = []
        let before = diagnostics.count
        for key in match.keys.sorted() {
            guard let (fact, field) = fields[key] else {
                let known = fields.keys.sorted().joined(separator: ", ")
                fail("", "\(name) has an unknown match field `\(key)` (\(known))")
                continue
            }
            if let condition = condition(fact, field, match[key] ?? .null, label: "\(name) match `\(key)`") {
                conditions.append(condition)
            }
        }
        return diagnostics.count == before ? .all(conditions) : nil
    }

    private mutating func condition(_ fact: Fact, _ field: Field, _ value: JSON, label: String) -> Condition? {
        switch (field, value) {
        case (.glob, .string): return .compare(fact, .glob, value)
        case (.text, .string), (.bool, .bool): return .compare(fact, .equal, value)
        case (.textOrRegex, .string): return .compare(fact, .equal, value)
        case (.number, .int), (.number, .number): return .compare(fact, .equal, value)
        case (.layout, .string(let name)) where Layout(rawValue: name) != nil: return .compare(fact, .equal, value)
        case (.count, .int), (.count, .number): return .compare(fact, .equal, value)
        case (.count, .object(let bounds)):
            let ops: [(String, Comparison)] = [("atLeast", .atLeast), ("atMost", .atMost)]
            let found = ops.compactMap { key, comparison in bounds[key].map { (key, comparison, $0) } }
            guard !found.isEmpty, found.count == bounds.count, found.allSatisfy({ $0.2.double != nil }) else {
                fail("", "\(label) must be a number or { atLeast, atMost }")
                return nil
            }
            return .all(found.map { .compare(fact, $0.1, $0.2) })
        case (.textOrRegex, .object(let regex)): return regexCondition(fact, regex, label: label)
        default:
            let noun = switch field {
            case .glob, .text, .textOrRegex: "a string"
            case .number: "a number"
            case .bool: "true or false"
            case .count: "a number or { atLeast, atMost }"
            case .layout: "a layout name"
            }
            fail("", "\(label) must be \(noun)")
            return nil
        }
    }

    private mutating func regexCondition(_ fact: Fact, _ value: [String: JSON], label: String) -> Condition? {
        guard let pattern = value["regex"]?.string, let flags = value["flags"]?.string else {
            fail("", "\(label) must be a string or a regular expression")
            return nil
        }
        var options: NSRegularExpression.Options = []
        for flag in flags {
            switch flag {
            case "i": options.insert(.caseInsensitive)
            case "m": options.insert(.anchorsMatchLines)
            case "s": options.insert(.dotMatchesLineSeparators)
            case "g", "u", "y", "d": continue
            default:
                fail("", "\(label) uses the regular expression flag `\(flag)`, which CatWM can't match")
                return nil
            }
        }
        do {
            return .matches(fact, try NSRegularExpression(pattern: pattern, options: options))
        } catch {
            fail("", "\(label) is the regular expression /\(pattern)/, which CatWM can't match: "
                + "\(error.localizedDescription)")
            return nil
        }
    }
}
