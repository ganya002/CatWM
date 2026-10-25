import AppKit
import ApplicationServices
import os

enum EnhancedUI {
    private struct Table {
        var held: [pid_t: (count: Int, wasOn: Bool)] = [:]
        var locks: [pid_t: NSLock] = [:]
    }
    private static let table = OSAllocatedUnfairLock(initialState: Table())
    private static let attr = "AXEnhancedUserInterface"

    static func suspend(_ pid: pid_t) {
        let pidLock = lock(pid)
        pidLock.lock(); defer { pidLock.unlock() }
        if let hold = table.withLock({ $0.held[pid] }) {
            table.withLock { $0.held[pid] = (hold.count + 1, hold.wasOn) }
            return
        }
        let app = axApp(pid)
        let wasOn = app.flag(attr)
        if wasOn { app.set(attr, kCFBooleanFalse) }
        table.withLock { $0.held[pid] = (1, wasOn) }
    }
    static func resume(_ pid: pid_t) {
        let pidLock = lock(pid)
        pidLock.lock(); defer { pidLock.unlock() }
        guard let hold = table.withLock({ $0.held[pid] }) else { return }
        if hold.count > 1 { table.withLock { $0.held[pid] = (hold.count - 1, hold.wasOn) }; return }
        table.withLock { $0.held[pid] = nil }
        if hold.wasOn { axApp(pid).set(attr, kCFBooleanTrue) }
    }

    static func terminated(_ pid: pid_t) {
        table.withLock {
            $0.held[pid] = nil
            $0.locks[pid] = nil
        }
    }

    private static func lock(_ pid: pid_t) -> NSLock {
        table.withLock {
            if let existing = $0.locks[pid] { return existing }
            let created = NSLock()
            $0.locks[pid] = created
            return created
        }
    }
}
