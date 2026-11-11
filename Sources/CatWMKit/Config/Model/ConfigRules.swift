import Foundation

package typealias ConfigValue = JSON

package struct RuleAction: Equatable, Sendable {
    package let dispatcher: String
    package let arg: String
}

package enum Fact: String, CaseIterable, Sendable {
    case app, title, pid, workspace, display, floating, minimized, fullscreen
    case windows, sameApp, apps, layout, name, focused
}

package enum Comparison: Sendable {
    case equal, atLeast, atMost, glob
}

package typealias Facts = [Fact: ConfigValue]

package indirect enum Condition: Equatable, @unchecked Sendable { // style-ok: NSRegularExpression is immutable
    case compare(Fact, Comparison, ConfigValue)
    case matches(Fact, NSRegularExpression)
    case all([Condition])

    package static func == (left: Condition, right: Condition) -> Bool {
        switch (left, right) {
        case let (.compare(fact, comparison, value), .compare(otherFact, otherOp, otherValue)):
            fact == otherFact && comparison == otherOp && value == otherValue
        case let (.matches(fact, regex), .matches(otherFact, otherRegex)):
            fact == otherFact && regex.pattern == otherRegex.pattern && regex.options == otherRegex.options
        case let (.all(conditions), .all(others)): conditions == others
        default: false
        }
    }

    package func holds(_ facts: Facts) -> Bool {
        switch self {
        case .all(let conditions): return conditions.allSatisfy { $0.holds(facts) }
        case .compare(let fact, let comparison, let expected):
            return Self.values(facts[fact]).contains { Self.compare($0, comparison, expected) }
        case .matches(let fact, let regex):
            return Self.values(facts[fact]).contains { value in
                guard let text = value.string else { return false }
                return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
        }
    }

    private static func values(_ value: ConfigValue?) -> [ConfigValue] {
        guard let value else { return [] }
        return value.array ?? [value]
    }

    private static func compare(_ actual: ConfigValue, _ comparison: Comparison, _ expected: ConfigValue) -> Bool {
        switch comparison {
        case .equal:
            if let left = actual.double, let right = expected.double { return left == right }
            return actual == expected
        case .atLeast: return actual.double.flatMap { left in expected.double.map { left >= $0 } } ?? false
        case .atMost: return actual.double.flatMap { left in expected.double.map { left <= $0 } } ?? false
        case .glob:
            return actual.string.flatMap { text in expected.string.map { Config.lists(text, in: [$0]) } } ?? false
        }
    }
}

package struct WindowRule: Equatable, Sendable {
    package let when: Condition
    package let actions: [RuleAction]
}

package struct WorkspaceRule: Equatable, Sendable {
    package let when: Condition
    package let set: [String: ConfigValue]
}

package struct WorkspaceFacts: Sendable {
    package var windows = 0
    package var sameApp = 0
    package var apps: [String] = []
    package var layout: Layout
    package var names: [String]
    package var displays: [String] = []
    package var focused = false

    package init(layout: Layout, names: [String]) {
        self.layout = layout
        self.names = names
    }

    var facts: Facts {
        [.windows: .int(windows), .sameApp: .int(sameApp), .apps: .array(apps.map(JSON.string)),
         .layout: .string(layout.rawValue), .name: .array(names.map(JSON.string)),
         .display: .array(displays.map(JSON.string)), .focused: .bool(focused)]
    }
}

extension Config {
    package func matchingRules(for workspace: WorkspaceFacts) -> [WorkspaceRule] {
        guard !workspaceRules.isEmpty else { return [] }
        let facts = workspace.facts
        return workspaceRules.filter { $0.when.holds(facts) }
    }

    package func resolved(for workspace: WorkspaceFacts) -> Config {
        var result = self
        var reader = ConfigScript.Reader(file: nil)
        for rule in matchingRules(for: workspace) {
            for (path, value) in rule.set {
                guard let leaf = ConfigScript.leaves[path] else { continue }
                reader.read(leaf, value, path: path, into: &result)
            }
        }
        return result
    }
}
