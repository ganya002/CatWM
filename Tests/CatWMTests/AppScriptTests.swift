@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct AppScriptTests {
    @Test func returnsTheScriptOutputAndPassesArguments() async {
        let source = "function run(argv) { return JSON.stringify(argv); }"
        let output = await AppScript.run(source, language: .javaScript, arguments: ["a b", "c"], timeout: 5)
        #expect(output == #"["a b","c"]"#)
    }

    @Test func stopsAScriptThatHangs() async {
        let started = Date()
        let output = await AppScript.run("delay(10)", language: .javaScript, timeout: 0.5)
        #expect(output == nil)
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func aFailedScriptGivesNoOutput() async {
        #expect(await AppScript.run("error \"no\"", language: .appleScript, timeout: 5) == nil)
    }

    @Test func blockingWorkReturnsTheFallbackAtTheTimeout() async {
        let started = Date()
        let release = DispatchSemaphore(value: 0)
        let value = await Blocking.run(timeout: 0.2, fallback: 0) {
            release.wait()
            return 1
        }
        release.signal()
        #expect(value == 0)
        #expect(Date().timeIntervalSince(started) < 1)
    }

    @Test func anAppThatIsNotRunningIsNotAsked() async {
        #expect(await Automation.access("com.example.not-installed", ask: false, timeout: 2) == .notRunning)
    }
}
