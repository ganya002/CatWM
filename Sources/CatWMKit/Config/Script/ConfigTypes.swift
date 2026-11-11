import Foundation

package enum ConfigTypes {
    package static let fileName = "catwm.d.ts"

    package static let tsconfig = """
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

    private struct Leaf {
        let read: String
        let write: String
        let doc: String
        let scoped: Bool
    }

    private indirect enum Node {
        case leaf(Leaf)
        case group([String: Node])
    }

    package static func render() -> String {
        var out = [
            "// The types of catwm.config.ts. CatWM writes this file each time it starts, so don't edit it.",
            "// Your config: `import { catwm } from \"./catwm\"`, then set options, such as `catwm.gaps.size = 12`.",
            "",
            "export type Mod = " + ConfigScript.mods.map { ConfigScript.quoted($0.name) }.joined(separator: " | "),
            "",
            "export type Key =\n  | " + ConfigScript.keyNames.map(ConfigScript.quoted).joined(separator: "\n  | "),
            "",
            "export type Layout = " + Layout.allCases.map { ConfigScript.quoted($0.rawValue) }.joined(separator: " | "),
            "",
            "/** The motion styles of Settings → Motion. Setting one sets its fields together. */",
            "export type MotionStyle = " + MotionStyle.all.map { ConfigScript.quoted($0.id) }.joined(separator: " | "),
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
            "/** A list you can change in place: `push`, or `remove` every copy of a value. */",
            "export interface List<T> extends Array<T> {",
            "  remove(value: T): void",
            "}",
            "",
            "/** What you can assign to a group: an object that merges, a list that replaces, `undefined` to reset. */",
            "export type Input<T> = {",
            "  [K in keyof T]?: T[K] extends List<infer U> ? readonly U[] | undefined",
            "    : T[K] extends object ? Input<T[K]> | undefined : T[K] | undefined",
            "}",
            ""
        ]
        let root = tree()
        out += interfaces(root, prefix: "", path: [])
        out += interfaces(scopedTree(root), prefix: "Scoped", path: [])
        out += apiTypes
        return out.joined(separator: "\n")
    }

    static func arguments(_ action: WindowAction) -> String {
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
        func add(_ path: String, read: String, write: String? = nil, _ doc: String, scoped: Bool = false) {
            let leaf = Leaf(read: read, write: write ?? read + " | undefined", doc: doc, scoped: scoped)
            insert(path.split(separator: ".").map(String.init), .leaf(leaf), into: &root)
        }
        func addList(_ path: String, _ element: String, _ doc: String, scoped: Bool = false) {
            add(path, read: "List<\(element)>", write: "readonly \(element)[] | undefined", doc, scoped: scoped)
        }
        add("mod", read: "Mod | readonly Mod[]",
            "Your main modifier. Window mode and the pointer actions use it. The default is `alt`.")
        addList("layouts", "Layout", "The layouts that `cyclelayout` steps through, each one once.", scoped: true)
        addList("floating.apps", "string",
                "Bundle IDs of the apps that float. `com.adobe.*` matches every Adobe app.")
        add("motion.style", read: "MotionStyle | undefined",
            "Sets the duration, curve and bounce together, like the style tiles in Settings → Motion. "
                + "A field you set after it overrides only that field.", scoped: true)
        for option in Options.all {
            if option.scriptKind == .strings {
                addList(option.script, "string", doc(option), scoped: option.isScoped)
            } else {
                add(option.script, read: type(option), doc(option), scoped: option.isScoped)
            }
        }
        for feature in Feature.allCases {
            add(feature.path, read: "boolean",
                feature.summary + (feature.isEmbeddable ? ". On by default, off by default in embedded mode."
                    : ". On by default. Embedded mode doesn't have it."))
        }
        return root
    }

    private static func scopedTree(_ nodes: [String: Node]) -> [String: Node] {
        nodes.compactMapValues { node in
            switch node {
            case .leaf(let leaf): return leaf.scoped ? node : nil
            case .group(let children):
                let kept = scopedTree(children)
                return kept.isEmpty ? nil : .group(kept)
            }
        }
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

    private static func interfaces(_ nodes: [String: Node], prefix: String, path: [String]) -> [String] {
        let name = prefix + path.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined() + "Options"
        var children: [String] = []
        var body: [String] = []
        for key in nodes.keys.sorted() {
            let property = ConfigScript.property(key)
            switch nodes[key] {
            case .leaf(let leaf):
                body += ["  /** \(leaf.doc) */", "  get \(property)(): \(leaf.read)",
                         "  set \(property)(value: \(leaf.write))"]
            case .group(let group):
                let child = path + [key]
                children += interfaces(group, prefix: prefix, path: child)
                let childName = prefix + child.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined() + "Options"
                let input = "Input<\(childName)> | undefined"
                let write = key == "padding" ? "number | \(input)" : input
                let doc = key == "padding"
                    ? ["  /** Space between the screen edges and the windows. A number sets all four sides. */"] : []
                let read = path.isEmpty && key == "workspaces" ? childName + " & WorkspaceRuleCall" : childName
                body += doc + ["  get \(property)(): \(read)", "  set \(property)(value: \(write))"]
            case nil: break
            }
        }
        return children + ["export interface \(name) {"] + body + ["}", ""]
    }
}
