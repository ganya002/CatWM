import AppKit

struct ConfigOption {
    let key: String
    var aliases: [String] = []
    var group = OptionGroup.general
    var section: String?
    var note: String?
    var valid: ClosedRange<Double>?
    var setting: SettingInfo?
    var valueDescription = "value"
    var documentation = ""
    var choices: [(String, String)] = []
    var setNumber: ((inout Config, Double) -> Void)?
    var script = ""
    var scriptKind = ScriptKind.string
    var scriptType: String?
    let path: PartialKeyPath<Config>
    let read: (inout Config, _ value: String, _ rawKey: String) -> String?
    let text: (Config) -> String
    let copy: (inout Config, Config) -> Void
    let number: (Config) -> Double

    init<V>(_ key: String, _ path: WritableKeyPath<Config, V>,
            read: @escaping (String, _ rawKey: String) -> (V?, String?),
            text: @escaping (V) -> String, number: @escaping (V) -> Double = { _ in 0 }) {
        self.valueDescription = V.self == Bool.self ? "bool" : "value"
        self.scriptKind = V.self == Bool.self ? .bool : .string
        self.key = key
        self.path = path
        self.read = { config, input, raw in
            let (value, error) = read(input, raw)
            if let value { config[keyPath: path] = value }
            return error
        }
        self.text = { text($0[keyPath: path]) }
        self.copy = { $0[keyPath: path] = $1[keyPath: path] }
        self.number = { number($0[keyPath: path]) }
    }

    var names: [String] { [key] + aliases }
    var defaultText: String { text(Config()) }

    func documented(_ value: String?, _ notes: String) -> Self {
        var option = self
        if let value { option.valueDescription = value }
        option.documentation = notes
        return option
    }

    func script(_ path: String, type: String? = nil) -> Self {
        var option = self
        option.script = path
        option.scriptType = type
        return option
    }
    func aliases(_ names: String...) -> Self { var option = self; option.aliases = names; return option }
    func section(_ title: String) -> Self { var option = self; option.section = title; return option }
    func note(_ text: String) -> Self { var option = self; option.note = text; return option }
    func animation() -> Self { var option = self; option.group = .animation; return option }
    func setting(_ pane: Pane, _ id: String, _ label: String, help: String? = nil, keywords: String = "",
                 advanced: Bool = false, range: ClosedRange<Double>? = nil, scale: Double = 1,
                 section: String? = nil, order: Int = 0, enabled: @escaping (Config) -> Bool = { _ in true },
                 unit: String = " pt", width: CGFloat = 160) -> Self {
        var option = self
        option.setting = SettingInfo(pane: pane, id: id, label: label, help: help, keywords: keywords,
                                     advanced: advanced, range: range, scale: scale,
                                     section: section ?? pane.defaultSection, order: order, enabled: enabled,
                                     unit: unit, width: width)
        return option
    }

    static let trueWords = ["true", "yes", "on", "1"], falseWords = ["false", "no", "off", "0"]

    static func readBool(_ input: String, _ rawKey: String) -> (Bool, String?) {
        let word = input.lowercased()
        let known = trueWords.contains(word) || falseWords.contains(word)
        return (trueWords.contains(word), known ? nil : "`\(rawKey)` needs true or false")
    }

    static func bool(_ key: String, _ path: WritableKeyPath<Config, Bool>) -> Self {
        Self(key, path, read: { input, raw in
            let (value, error) = readBool(input, raw)
            return (error == nil ? value : nil, error)
        }, text: { $0 ? "true" : "false" })
    }

    static func number<V>(_ key: String, _ path: WritableKeyPath<Config, V>, valid: ClosedRange<Double>? = nil,
                          convert: @escaping (Double) -> Double = \.self, make: @escaping (Double) -> V,
                          text: @escaping (V) -> String, number: @escaping (V) -> Double) -> Self {
        var option = Self(key, path, read: { input, raw in
            guard let parsed = Double(input), parsed.isFinite else { return (nil, "`\(raw)` needs a number") }
            var value = convert(parsed)
            if let valid { value = min(valid.upperBound, max(valid.lowerBound, value)) }
            return (make(value), nil)
        }, text: text, number: number)
        option.setNumber = { $0[keyPath: path] = make($1) }
        option.valueDescription = "number"
        option.scriptKind = .number
        option.valid = valid
        return option
    }

    static func points(_ key: String, _ path: WritableKeyPath<Config, CGFloat>, valid: ClosedRange<Double>? = nil,
                       convert: @escaping (Double) -> Double = \.self) -> Self {
        number(key, path, valid: valid, convert: convert, make: { CGFloat($0) },
               text: { String(format: "%g", Double($0)) }, number: { Double($0) })
    }

    static func list(_ key: String, _ path: WritableKeyPath<Config, [String]>) -> Self {
        var option = Self(key, path, read: { input, _ in (Config.listItems(input), nil) },
                          text: { $0.joined(separator: ", ") })
        option.scriptKind = .strings
        return option
    }

    static func choice<V: RawRepresentable & CaseIterable>(_ key: String, _ path: WritableKeyPath<Config, V>,
                                                           noun: String) -> Self
    where V.RawValue == String {
        var option = Self(key, path, read: { input, _ in
            guard let value = V(rawValue: input.lowercased()) else {
                return (nil, "unknown \(noun) `\(input)` (\(V.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            return (value, nil)
        }, text: { $0.rawValue })
        option.choices = V.allCases.map { ($0.rawValue, $0.rawValue) }
        option.valueDescription = V.allCases.map { "`\($0.rawValue)`" }.joined(separator: " ")
        return option
    }

    private static let byName: [String: ConfigOption] = {
        var options: [String: ConfigOption] = [:]
        for option in Options.all { for name in option.names { options[norm(name)] = option } }
        return options
    }()

    static func named(_ key: String) -> ConfigOption? { byName[norm(key)] }

    static func at(_ path: PartialKeyPath<Config>) -> ConfigOption {
        guard let option = Options.all.first(where: { $0.path == path }) else {
            fatalError("no config option for \(path)")
        }
        return option
    }

    static func norm(_ name: String) -> String { name.lowercased().replacingOccurrences(of: "-", with: "_") }
}

enum ScriptKind {
    case bool, number, string, strings
}

enum OptionGroup {
    case general
    case animation
}

struct SettingInfo {
    let pane: Pane
    let id: String
    let label: String
    var help: String?
    var keywords = ""
    var advanced = false
    var range: ClosedRange<Double>?
    var scale: Double = 1
    var section = ""
    var order = 0
    var enabled: (Config) -> Bool = { _ in true }
    var unit = " pt"
    var width: CGFloat = 160
}

extension Pane {
    var defaultSection: String {
        switch self {
        case .general: "General"
        case .layout: "Gaps"
        case .windows: "Focus"
        case .motion: "Feel"
        case .templates: "Saved templates"
        case .shortcuts: "Keyboard"
        }
    }
}
