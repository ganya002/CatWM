import Foundation
import os

package enum RealInput {
    private struct State {
        var blocked = NSClassFromString("XCTestCase") != nil && !optedIn
        var refusals = 0
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    private static var optedIn: Bool {
        ProcessInfo.processInfo.environment.contains { $0.key.hasPrefix("CATWM_TEST_") && $0.value == "1" }
    }

    package static func block() { state.withLock { $0.blocked = true } }

    package static var isBlocked: Bool { state.withLock { $0.blocked } }

    package static var refusals: Int { state.withLock { $0.refusals } }

    package static func allows(_ action: @autoclosure () -> String, traps: Bool = true) -> Bool {
        let refused = state.withLock { state in
            if state.blocked && traps { state.refusals += 1 }
            return state.blocked
        }
        guard refused else { return true }
        let message = "blocked real \(action()): this process must not touch the user's input or Desktops"
        Log.info(message)
        if traps { assertionFailure(message) }
        return false
    }
}
