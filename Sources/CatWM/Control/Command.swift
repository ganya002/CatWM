import Foundation

enum ArgKind: Equatable {
    case string, int, number, bool, strings
    case choice([String])

    var schemaName: String {
        switch self {
        case .string: "string"
        case .int: "int"
        case .number: "number"
        case .bool: "bool"
        case .strings: "string[]"
        case .choice: "enum"
        }
    }
}

struct CommandArg {
    let name: String
    let kind: ArgKind
    let summary: String
    var required = true

    static func text(_ name: String, _ summary: String, required: Bool = true) -> Self {
        Self(name: name, kind: .string, summary: summary, required: required)
    }

    static func choice(_ name: String, _ choices: [String], _ summary: String, required: Bool = true) -> Self {
        Self(name: name, kind: .choice(choices), summary: summary, required: required)
    }
}

struct Field {
    let name: String
    let type: String
    let summary: String
}

enum ResultShape {
    case none
    case text
    case value
    case object([Field])
    case list([Field])
}

enum CommandAccess: String {
    case `public`, dev, keybindOnly
}

struct ControlError: Error, Equatable {
    let code: String
    let message: String

    static func unknownCommand(_ name: String) -> Self {
        Self(code: "unknown_command", message: "Unknown command `\(name)`")
    }
    static func invalid(_ message: String) -> Self { Self(code: "invalid_args", message: message) }
    static func forbidden(_ name: String) -> Self {
        Self(code: "forbidden", message: "`\(name)` is only allowed from keybinds")
    }
    static func failed(_ message: String) -> Self { Self(code: "failed", message: message) }
    static func badRequest(_ message: String) -> Self { Self(code: "bad_request", message: message) }
}

struct Invocation {
    let args: [String: JSON]
    let client: ControlConnection?
    let manager: WindowManager

    func text(_ name: String) -> String { args[name]?.string ?? "" }
}

struct Command {
    let name: String
    let group: String
    let summary: String
    var args: [CommandArg] = []
    var result = ResultShape.none
    var access = CommandAccess.public
    let run: (Invocation) throws -> JSON

    func validate(_ given: [String: JSON]) throws -> [String: JSON] {
        for key in given.keys where !args.contains(where: { $0.name == key }) {
            throw ControlError.invalid("`\(name)` has no argument `\(key)`")
        }
        var checked: [String: JSON] = [:]
        for arg in args {
            guard let value = given[arg.name], value != .null else {
                if arg.required { throw ControlError.invalid("`\(name)` needs `\(arg.name)`") }
                continue
            }
            checked[arg.name] = try Self.check(value, as: arg, in: name)
        }
        return checked
    }

    private static func check(_ value: JSON, as arg: CommandArg, in command: String) throws -> JSON {
        func wrong(_ expected: String) -> ControlError {
            .invalid("`\(command)` needs `\(arg.name)` to be \(expected)")
        }
        switch arg.kind {
        case .string:
            guard value.string != nil else { throw wrong("a string") }
        case .int:
            guard let number = value.int else { throw wrong("an integer") }
            return .int(number)
        case .number:
            guard let number = value.double else { throw wrong("a number") }
            return .number(number)
        case .bool:
            guard value.isBool else { throw wrong("true or false") }
        case .strings:
            guard let list = value.array, list.allSatisfy({ $0.string != nil }) else {
                throw wrong("a list of strings")
            }
        case .choice(let choices):
            guard let text = value.string?.lowercased(), choices.contains(text) else {
                throw wrong("one of \(choices.joined(separator: ", "))")
            }
            return .string(text)
        }
        return value
    }
}
