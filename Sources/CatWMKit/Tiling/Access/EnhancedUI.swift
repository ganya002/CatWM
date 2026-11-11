import AppKit
import ApplicationServices
import os

package final class EnhancedUI: Sendable {
    package static let attr = "AXEnhancedUserInterface"
    package let pid: pid_t
    private let backend: any WindowBackend
    private struct State { var holds = 0, wasOn = false }
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init(pid: pid_t, backend: any WindowBackend) {
        self.pid = pid
        self.backend = backend
    }

    package func suspend() {
        guard state.withLock({ $0.holds += 1; return $0.holds == 1 }) else { return }
        let wasOn = backend.suspendEnhancedUI(pid)
        state.withLock { $0.wasOn = wasOn }
    }

    package func resume() {
        let restore = state.withLock { state -> Bool in
            guard state.holds > 0 else { return false }
            state.holds -= 1
            return state.holds == 0 && state.wasOn
        }
        if restore { backend.resumeEnhancedUI(pid) }
    }
}
