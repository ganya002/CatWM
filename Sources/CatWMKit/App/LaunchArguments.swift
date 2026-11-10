import Foundation

package enum LaunchFlag: String, CaseIterable {
    case verbose = "--verbose"
    case onboarding = "--onboarding"
    case gallery = "--gallery"
    case crashReport = "--crash-report"
    case afterCrash = "--after-crash"
    case unscoped = "--unscoped"

    package var isSet: Bool { CommandLine.arguments.contains(rawValue) }
}

package enum LaunchArguments {
    package enum Decision: Equatable {
        case start
        case cli([String])
        case usage(String)
    }

    package static func decide(_ arguments: [String]) -> Decision {
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

    package static func startRefusal(named: Bool, scoped: Bool, arguments: [String]) -> String? {
        guard named, !scoped, !arguments.contains(LaunchFlag.unscoped.rawValue) else { return nil }
        return "catwm: an instance with CATWM_INSTANCE and no CATWM_SCOPE manages every window and fights the "
            + "default CatWM. Set CATWM_SCOPE=pids:<pid>,..., or pass \(LaunchFlag.unscoped.rawValue) to accept this."
    }

    private static func isAppleDefault(_ word: String) -> Bool {
        word.count > 2 && !word.hasPrefix("--") && word.dropFirst().first?.isUppercase == true
    }
}
