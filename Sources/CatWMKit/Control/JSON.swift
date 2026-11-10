import Foundation

public enum JSON: Equatable, Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var int: Int? {
        switch self {
        case .int(let value): value
        case .number(let value): Int(exactly: value)
        default: nil
        }
    }
    public var double: Double? {
        switch self {
        case .int(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }
    public var isTrue: Bool { self == .bool(true) }
    public var isBool: Bool { if case .bool = self { true } else { false } }
    public var array: [JSON]? { if case .array(let value) = self { value } else { nil } }
    public var object: [String: JSON]? { if case .object(let value) = self { value } else { nil } }

    public subscript(key: String) -> JSON? { object?[key] }

    package static func parse(_ data: Data) -> JSON? { try? JSONDecoder().decode(JSON.self, from: data) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    package func encoded(pretty: Bool = false) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
            : [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    package var text: String { String(bytes: encoded(), encoding: .utf8) ?? "null" }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
}

extension JSON {
    package static func rect(_ rect: CGRect) -> JSON {
        guard !rect.isNull, !rect.isInfinite else { return .null }
        return ["x": .number(rect.minX), "y": .number(rect.minY),
                "width": .number(rect.width), "height": .number(rect.height)]
    }
}
