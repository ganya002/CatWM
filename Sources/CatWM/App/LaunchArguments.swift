import Foundation

enum LaunchFlag: String, CaseIterable {
    case verbose = "--verbose"
    case onboarding = "--onboarding"
    case gallery = "--gallery"
    case crashReport = "--crash-report"
    case afterCrash = "--after-crash"

    var isSet: Bool { CommandLine.arguments.contains(rawValue) }
}

enum LaunchArguments {
    enum Decision: Equatable {
        case start
        case cli([String])
        case usage(String)
    }

    static func decide(_ arguments: [String]) -> Decision {
        guard let first = arguments.first else { return .start }
        if !first.hasPrefix("-") || ["--help", "-h"].contains(first) || arguments.contains("--json") {
            return .cli(arguments)
        }
        var rest = arguments[...]
        while let word = rest.popFirst() {
            if LaunchFlag(rawValue: word) != nil || word.hasPrefix("-psn_") { continue }
            if isAppleDefault(word), rest.first.map({ !$0.hasPrefix("-") }) == true {
                rest.removeFirst()
                continue
            }
            let flags = LaunchFlag.allCases.map(\.rawValue).joined(separator: ", ")
            return .usage("catwm: unknown argument '\(word)'. "
                + "Usage: catwm <command> [arguments] [--json]. Run `catwm help` to see the commands. "
                + "Start flags: \(flags).")
        }
        return .start
    }

    private static func isAppleDefault(_ word: String) -> Bool {
        word.count > 2 && !word.hasPrefix("--") && word.dropFirst().first?.isUppercase == true
    }
}
