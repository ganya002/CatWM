import Foundation

extension CatWMEngine {
    public enum ConfigSource: Sendable, Equatable {
        case file(URL)
        case text(String)
    }

    public struct Scope: Sendable, Equatable {
        public var pids: [Int32]
        public var display: String?

        public init(pids: [Int32], display: String? = nil) {
            self.pids = pids
            self.display = display
        }
    }

    public enum EngineError: Error, Equatable, LocalizedError {
        case alreadyRunning
        case notRunning
        case invalidName(String)
        case config([Diagnostic])
        case unknownOption(String)
        case invalidValue(String)
        case command(code: String, message: String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRunning: "A CatWM engine already runs in this process"
            case .notRunning: "The CatWM engine isn't running"
            case .invalidName(let name): "Can't use `\(name)` as the engine name: use 1 to 24 of a-z, 0-9 and -"
            case .config(let problems): problems.map(\.text).joined(separator: "\n")
            case .unknownOption(let id): "Unknown option `\(id)`"
            case .invalidValue(let message), .command(_, let message): message
            }
        }
    }

    public struct Diagnostic: Sendable, Equatable {
        public let file: String?
        public let line: Int?
        public let phase: String
        public let message: String

        public var text: String {
            ConfigDiagnostic(file: file, line: line, phase: .init(rawValue: phase) ?? .validate, message: message).text
        }

        init(file: String?, line: Int?, phase: String, message: String) {
            self.file = file
            self.line = line
            self.phase = phase
            self.message = message
        }

        init(_ diagnostic: ConfigDiagnostic) {
            self.init(file: diagnostic.file, line: diagnostic.line, phase: diagnostic.phase.rawValue,
                      message: diagnostic.message)
        }
    }

    public enum OptionKind: Sendable, Equatable {
        case bool, number, string, strings
    }

    public struct Option: Sendable, Equatable {
        public let id: String
        public let kind: OptionKind
        public let summary: String
        public let choices: [String]
        public let range: ClosedRange<Double>?
        public let defaultValue: JSON
        public let value: JSON
        public let feature: String?

        init?(_ option: ConfigOption, in config: Config) {
            guard !option.script.isEmpty, !Self.appOnly.contains(option.script) else { return nil }
            let feature = Self.feature(of: option.script)
            guard feature?.isEmbeddable != false else { return nil }
            id = option.script
            kind = switch option.scriptKind {
            case .bool: .bool
            case .number: .number
            case .string: .string
            case .strings: .strings
            }
            summary = option.documentation
            choices = option.choices.map(\.0)
            range = option.valid
            defaultValue = ConfigScript.json(option, in: .embedded)
            value = ConfigScript.json(option, in: config)
            self.feature = feature?.path
        }

        init(_ feature: Feature, in config: Config) {
            id = feature.path
            kind = .bool
            summary = feature.summary
            choices = []
            range = nil
            defaultValue = false
            value = .bool(config.features.contains(feature))
            self.feature = feature.needs.last?.path
        }

        private static let appOnly: Set<String> = ["panelAnimation", "modeEffect", "perfReports", "mouse.splitHandle"]

        private static func feature(of id: String) -> Feature? {
            switch id.split(separator: ".").first {
            case "mouse": .mouse
            case "layoutHud": .hud
            case "keyboardHelp": .keyHelp
            case "switcher": .switcher
            case "cursorActions": .cursorActions
            case "templateAppScripting": .templates
            case "tabs": id == "tabs.notificationBadges" ? .notifications : .tabStrips
            case "workspaces" where id == "workspaces.virtual": .desktops
            default: nil
            }
        }
    }

    public struct Event: Sendable, Equatable {
        public let name: String
        public let data: JSON
    }

    public struct Snapshot: Sendable, Equatable {
        public let isRunning: Bool
        public let isTiling: Bool
        public let features: [String]
        public let permissions: [String: Bool]
        public let diagnostics: [Diagnostic]
        public let windows: JSON
        public let workspaces: JSON
        public let screens: JSON
        public let mode: String
    }
}
