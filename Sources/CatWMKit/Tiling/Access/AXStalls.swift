import ApplicationServices
import QuartzCore

package final class AXStalls {
    package static let shared = AXStalls()
    package static let hangLine: CFTimeInterval = 0.25
    package static let memory: CFTimeInterval = 3

    private let lock = NSLock()
    private var stalledAt: [pid_t: CFTimeInterval] = [:]
    private let now: () -> CFTimeInterval

    package init(now: @escaping () -> CFTimeInterval = CACurrentMediaTime) { self.now = now }

    package func note(_ element: AXUIElement, _ error: AXError, since start: CFTimeInterval) {
        switch error {
        case .success:
            lock.withLock {
                guard !stalledAt.isEmpty, let pid = element.ownerPID else { return }
                stalledAt[pid] = nil
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
        lock.withLock {
            switch error {
            case .success: stalledAt[pid] = nil
            case .cannotComplete where seconds >= Self.hangLine: stalledAt[pid] = now()
            default: break
            }
        }
    }

    package func isStalled(_ pid: pid_t) -> Bool {
        lock.withLock {
            guard let since = stalledAt[pid] else { return false }
            if now() - since < Self.memory { return true }
            stalledAt[pid] = nil
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
