import Foundation

enum ConfigTypes {
    static let fileName = "catwm.d.ts"

    static let tsconfig = """
    {
      "compilerOptions": {
        "strict": true,
        "noEmit": true,
        "target": "es2022",
        "module": "esnext",
        "moduleResolution": "bundler",
        "erasableSyntaxOnly": true,
        "verbatimModuleSyntax": true
      },
      "include": ["**/*.ts"]
    }

    """

    private indirect enum Node {
        case leaf(type: String, doc: String)
        case group([String: Node])
    }

    static func render() -> String {
        var out = [
            "// The types of catwm.config.ts. CatWM writes this file each time it starts, so don't edit it.",
            "// Your config: `import type { Config } from \"./catwm\"`, then `export default { … } satisfies Config`.",
            "",
            "export type Mod = " + ConfigScript.mods.map { ConfigScript.quoted($0.name) }.joined(separator: " | "),
            "",
            "export type Key =\n  | " + ConfigScript.keyNames.map(ConfigScript.quoted).joined(separator: "\n  | "),
            "",
            "export type Layout = " + Layout.allCases.map { ConfigScript.quoted($0.rawValue) }.joined(separator: " | "),
            "",
            "/** Each action and its arguments. Binds pass the arguments as the `.conf` file did. */",
            "export interface Actions {"
        ]
        for name in Actions.dispatchers {
            let action = WindowActions.named(name)
            if let action { out.append("  /** \(action.summary). */") }
            let args = action.map(arguments) ?? ""
            out.append("  \(ConfigScript.property(name)): [\(args)]")
        }
        out += [
            "}",
            "",
            "/** An action name, or the name and its arguments: `\"sort\"` or `[\"workspace\", \"2\"]`. */",
            "export type Action = {",
            "  [A in keyof Actions]: [] extends Actions[A] ? A | [A, ...Actions[A]] : [A, ...Actions[A]]",
            "}[keyof Actions]",
            "",
            "export interface Bind {",
            "  /** The modifiers you hold with the key. */",
            "  mods?: readonly Mod[]",
            "  key: Key",
            "  run: Action",
            "  /** Run the action again while you hold the key. */",
            "  repeat?: boolean",
            "}",
            "",
            "export interface Config {"
        ]
        out += lines(tree(), indent: 2)
        out += ["}", ""]
        return out.joined(separator: "\n")
    }

    private static func arguments(_ action: WindowAction) -> String {
        if action.args.isEmpty { return "...args: (string | number)[]" }
        let hints = action.pickers.map(\.args).filter { !$0.isEmpty }
        return action.args.map { arg in
            var values: [String] = []
            if case .choice(let choices) = arg.kind { values = choices }
            for hint in hints where !values.contains(hint) && !hint.contains(",") { values.append(hint) }
            let type = values.isEmpty ? "string | number"
                : values.prefix(24).map(ConfigScript.quoted).joined(separator: " | ") + " | (string & {})"
            return "\(ConfigScript.property(arg.name))\(arg.required ? "" : "?"): \(type)"
        }.joined(separator: ", ")
    }

    private static func tree() -> [String: Node] {
        var root: [String: Node] = [:]
        func add(_ path: String, _ type: String, _ doc: String) {
            insert(path.split(separator: ".").map(String.init), .leaf(type: type, doc: doc), into: &root)
        }
        add("mod", "Mod | readonly Mod[]",
            "Your main modifier. Window mode and the pointer actions use it. The default is `alt`.")
        add("layouts", "readonly Layout[]", "The layouts that `cyclelayout` steps through, each one once.")
        add("floating.apps", "readonly string[]",
            "Bundle IDs of the apps that float. `com.adobe.*` matches every Adobe app.")
        for option in Options.all {
            add(option.script, type(option), doc(option))
        }
        add("binds", "readonly Bind[]", "The binds that work in every app.")
        add("submaps", "Record<string, readonly Bind[]>",
            "Key modes. `[\"submap\", \"window\"]` enters one and `[\"submap\", \"reset\"]` leaves it.")
        for feature in Feature.allCases {
            add(feature.path, "boolean",
                feature.summary + ". Embedded mode reads this. Standalone CatWM keeps every feature on for now.")
        }
        return root
    }

    private static func insert(_ parts: [String], _ leaf: Node, into node: inout [String: Node]) {
        guard let first = parts.first else { return }
        if parts.count == 1 {
            node[first] = leaf
            return
        }
        var children: [String: Node] = [:]
        if case .group(let existing) = node[first] { children = existing }
        insert(Array(parts.dropFirst()), leaf, into: &children)
        node[first] = .group(children)
    }

    private static func type(_ option: ConfigOption) -> String {
        if let type = option.scriptType { return type }
        switch option.scriptKind {
        case .bool: return "boolean"
        case .number: return "number"
        case .strings: return "readonly string[]"
        case .string:
            return option.choices.isEmpty ? "string"
                : option.choices.map { ConfigScript.quoted($0.0) }.joined(separator: " | ")
        }
    }

    private static func doc(_ option: ConfigOption) -> String {
        var parts: [String] = []
        if let setting = option.setting {
            parts.append(setting.label + ".")
            if let help = setting.help { parts.append(help + ".") }
        }
        if !option.documentation.isEmpty, option.setting?.help == nil {
            parts.append(option.documentation.prefix(1).uppercased() + option.documentation.dropFirst() + ".")
        }
        if let valid = option.valid { parts.append("From \(format(valid.lowerBound)) to \(format(valid.upperBound)).") }
        parts.append("Default: `\(option.defaultText.isEmpty ? "[]" : option.defaultText)`.")
        return parts.joined(separator: " ")
    }

    private static func format(_ number: Double) -> String { String(format: "%g", number) }

    private static func lines(_ node: [String: Node], indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        return node.keys.sorted().flatMap { key -> [String] in
            switch node[key] {
            case .leaf(let type, let doc):
                return ["\(pad)/** \(doc) */", "\(pad)\(ConfigScript.property(key))?: \(type)"]
            case .group(let children):
                let body = lines(children, indent: indent + 2)
                if key == "padding" {
                    let doc = "Space between the screen edges and the windows. A number sets all four sides."
                    return ["\(pad)/** \(doc) */",
                            "\(pad)padding?: number | {"] + body + ["\(pad)}"]
                }
                return ["\(pad)\(ConfigScript.property(key))?: {"] + body + ["\(pad)}"]
            case nil: return []
            }
        }
    }
}
