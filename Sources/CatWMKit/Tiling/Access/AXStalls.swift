import ApplicationServices
import os
import QuartzCore

package final class AXStalls: Sendable {
    package static let shared = AXStalls()
    package static let hangLine: CFTimeInterval = 0.25
    package static let memory: CFTimeInterval = 3

    private let stalledAt = OSAllocatedUnfairLock(initialState: [pid_t: CFTimeInterval]())
    private let now: @Sendable () -> CFTimeInterval

    package init(now: @escaping @Sendable () -> CFTimeInterval = CACurrentMediaTime) { self.now = now }

    package func note(_ element: AXUIElement, _ error: AXError, since start: CFTimeInterval) {
        switch error {
        case .success:
            let pid = element.ownerPID
            stalledAt.withLock { stalled in
                guard !stalled.isEmpty, let pid else { return }
                stalled[pid] = nil
            }
        case .cannotComplete:
            let took = now() - start
            guard took >= Self.hangLine, let pid = element.ownerPID else { return }
            record(pid, error, took: took)
        default:
            break
        }
    }

    package func record(_ pid: pid_t, _ error: AXError, took seconds: CFTimeInterval) {
        stalledAt.withLock { stalled in
            switch error {
            case .success: stalled[pid] = nil
            case .cannotComplete where seconds >= Self.hangLine: stalled[pid] = now()
            default: break
            }
        }
    }

    package func isStalled(_ pid: pid_t) -> Bool {
        stalledAt.withLock { stalled in
            guard let since = stalled[pid] else { return false }
            if now() - since < Self.memory { return true }
            stalled[pid] = nil
            return false
        }
    }
}

private extension AXUIElement {
    var ownerPID: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(self, &pid) == .success ? pid : nil
    }
}
