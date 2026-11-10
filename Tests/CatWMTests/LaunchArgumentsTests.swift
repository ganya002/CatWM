@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct LaunchArgumentsTests {
    @Test func noArgumentsStartsTheApp() {
        #expect(LaunchArguments.decide([]) == .start)
    }

    @Test(arguments: [
        ["--verbose"], ["--onboarding", "--verbose"], ["--gallery"], ["--crash-report"], ["--after-crash"],
        ["-psn_0_12345"], ["-NSDocumentRevisionsDebugMode", "YES"], ["-ApplePersistenceIgnoreState", "YES", "--verbose"]
    ])
    func startFlagsAndAppleArgumentsStartTheApp(_ arguments: [String]) {
        #expect(LaunchArguments.decide(arguments) == .start)
    }

    @Test(arguments: [
        ["windows"], ["windows", "--json"], ["--json", "windows"], ["--json"], ["--help"], ["-h"], ["help", "focus"]
    ])
    func commandsRunTheCLI(_ arguments: [String]) {
        #expect(LaunchArguments.decide(arguments) == .cli(arguments))
    }

    @Test(arguments: [
        ["--jsno", "windows"], ["-v"], ["--version"], ["--verbose", "windows"], ["--verbose", "--bogus"], ["-NSFoo"]
    ])
    func unknownArgumentsDoNotStartTheApp(_ arguments: [String]) {
        guard case .usage(let message) = LaunchArguments.decide(arguments) else {
            Issue.record("\(arguments) did not give a usage error")
            return
        }
        #expect(message.contains("--verbose"))
    }

    @Test func aNamedInstanceWithoutScopeNeedsTheFlag() {
        #expect(LaunchArguments.startRefusal(named: true, scoped: false, arguments: ["CatWM"]) != nil)
        #expect(LaunchArguments.startRefusal(named: true, scoped: false, arguments: ["CatWM", "--unscoped"]) == nil)
        #expect(LaunchArguments.startRefusal(named: true, scoped: true, arguments: ["CatWM"]) == nil)
        #expect(LaunchArguments.startRefusal(named: false, scoped: false, arguments: ["CatWM"]) == nil)
    }

    @Test func theUnscopedFlagIsAStartFlag() {
        #expect(LaunchArguments.decide(["--unscoped"]) == .start)
    }
}
