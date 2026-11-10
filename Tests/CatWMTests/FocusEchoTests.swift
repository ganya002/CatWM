@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct FocusEchoTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func matchesOtherAppInsideWindow() {
        let echo = FocusEcho(id: 7, other: 42, now: start)
        #expect(echo.matches(42, at: start.addingTimeInterval(0.01)))
    }

    @Test func ignoresOtherPids() {
        let echo = FocusEcho(id: 7, other: 42, now: start)
        #expect(!echo.matches(43, at: start.addingTimeInterval(0.01)))
        #expect(!echo.matches(nil, at: start.addingTimeInterval(0.01)))
    }

    @Test func expires() {
        let echo = FocusEcho(id: 7, other: 42, now: start)
        #expect(!echo.matches(42, at: start.addingTimeInterval(FocusEcho.window + 0.01)))
    }
}
