import AppKit

struct ConfigOption {
    let key: String
    var aliases: [String] = []
    var group = OptionGroup.general
    var section: String? = nil
    var note: String? = nil
    var valid: ClosedRange<Double>? = nil
    var setting: SettingInfo? = nil
    let path: PartialKeyPath<Config>
    let read: (inout Config, _ value: String, _ rawKey: String) -> String?
    let text: (Config) -> String
    let copy: (inout Config, Config) -> Void
    let number: (Config) -> Double

    init<V>(_ key: String, _ path: WritableKeyPath<Config, V>, read: @escaping (String, _ rawKey: String) -> (V?, String?),
            text: @escaping (V) -> String, number: @escaping (V) -> Double = { _ in 0 }) {
        self.key = key
        self.path = path
        self.read = { c, v, raw in
            let (value, error) = read(v, raw)
            if let value { c[keyPath: path] = value }
            return error
        }
        self.text = { text($0[keyPath: path]) }
        self.copy = { $0[keyPath: path] = $1[keyPath: path] }
        self.number = { number($0[keyPath: path]) }
    }

    var names: [String] { [key] + aliases }
    var defaultText: String { text(Config()) }

    func aliases(_ a: String...) -> Self { var o = self; o.aliases = a; return o }
    func section(_ s: String) -> Self { var o = self; o.section = s; return o }
    func note(_ s: String) -> Self { var o = self; o.note = s; return o }
    func animation() -> Self { var o = self; o.group = .animation; return o }
    func setting(_ pane: Pane, _ id: String, _ label: String, help: String? = nil, keywords: String = "", advanced: Bool = false,
                 range: ClosedRange<Double>? = nil, scale: Double = 1) -> Self {
        var o = self
        o.setting = SettingInfo(pane: pane, id: id, label: label, help: help, keywords: keywords, advanced: advanced, range: range, scale: scale)
        return o
    }

    static let trueWords = ["true", "yes", "on", "1"], falseWords = ["false", "no", "off", "0"]

    static func readBool(_ v: String, _ rawKey: String) -> (Bool, String?) {
        let l = v.lowercased()
        return (trueWords.contains(l), trueWords.contains(l) || falseWords.contains(l) ? nil : "`\(rawKey)` needs true or false")
    }

    static func bool(_ key: String, _ path: WritableKeyPath<Config, Bool>) -> Self {
        Self(key, path, read: { v, raw in let (b, error) = readBool(v, raw); return (b, error) }, text: { $0 ? "true" : "false" })
    }

    static func number<V>(_ key: String, _ path: WritableKeyPath<Config, V>, valid: ClosedRange<Double>? = nil,
                          convert: @escaping (Double) -> Double = { $0 }, make: @escaping (Double) -> V,
                          text: @escaping (V) -> String, number: @escaping (V) -> Double) -> Self {
        var o = Self(key, path, read: { v, raw in
            guard let n = Double(v), n.isFinite else { return (nil, "`\(raw)` needs a number") }
            var x = convert(n)
            if let valid { x = min(valid.upperBound, max(valid.lowerBound, x)) }
            return (make(x), nil)
        }, text: text, number: number)
        o.valid = valid
        return o
    }

    static func points(_ key: String, _ path: WritableKeyPath<Config, CGFloat>, valid: ClosedRange<Double>? = nil,
                       convert: @escaping (Double) -> Double = { $0 }) -> Self {
        number(key, path, valid: valid, convert: convert, make: { CGFloat($0) }, text: { String(format: "%g", Double($0)) }, number: { Double($0) })
    }

    static func choice<V: RawRepresentable & CaseIterable>(_ key: String, _ path: WritableKeyPath<Config, V>, noun: String) -> Self
    where V.RawValue == String {
        Self(key, path, read: { v, _ in
            guard let x = V(rawValue: v.lowercased()) else {
                return (nil, "unknown \(noun) `\(v)` (\(V.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            return (x, nil)
        }, text: { $0.rawValue })
    }

    private static let byName: [String: ConfigOption] = {
        var d: [String: ConfigOption] = [:]
        for o in Options.all { for n in o.names { d[norm(n)] = o } }
        return d
    }()

    static func named(_ key: String) -> ConfigOption? { byName[norm(key)] }

    static func at(_ path: PartialKeyPath<Config>) -> ConfigOption {
        guard let o = Options.all.first(where: { $0.path == path }) else { fatalError("no config option for \(path)") }
        return o
    }

    static func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "-", with: "_") }
}
