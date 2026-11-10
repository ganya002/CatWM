import AppKit
import ApplicationServices

package struct EnhancedUI {
    package static let attr = "AXEnhancedUserInterface"
    package let pid: pid_t
    private let backend: any WindowBackend
    private var holds = 0
    private var wasOn = false

    package init(pid: pid_t, backend: any WindowBackend) {
        self.pid = pid
        self.backend = backend
    }

    package mutating func suspend() {
        holds += 1
        guard holds == 1 else { return }
        wasOn = backend.suspendEnhancedUI(pid)
    }

    package mutating func resume() {
        guard holds > 0 else { return }
        holds -= 1
        if holds == 0, wasOn { backend.resumeEnhancedUI(pid) }
    }
}
