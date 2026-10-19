import AppKit
import ApplicationServices

enum EnhancedUI {
    private static var held: [pid_t: (count: Int, wasOn: Bool)] = [:]
    private static var locks: [pid_t: NSLock] = [:]
    private static let tableLock = NSLock()
    private static let attr = "AXEnhancedUserInterface"

    static func suspend(_ pid: pid_t) {
        let pidLock = lock(pid)
        pidLock.lock(); defer { pidLock.unlock() }
        if let hold = tableLock.withLock({ held[pid] }) {
            tableLock.withLock { held[pid] = (hold.count + 1, hold.wasOn) }
            return
        }
        let app = axApp(pid)
        let wasOn = app.flag(attr)
        if wasOn { app.set(attr, kCFBooleanFalse) }
        tableLock.withLock { held[pid] = (1, wasOn) }
    }
    static func resume(_ pid: pid_t) {
        let pidLock = lock(pid)
        pidLock.lock(); defer { pidLock.unlock() }
        guard let hold = tableLock.withLock({ held[pid] }) else { return }
        if hold.count > 1 { tableLock.withLock { held[pid] = (hold.count - 1, hold.wasOn) }; return }
        tableLock.withLock { held[pid] = nil }
        if hold.wasOn { axApp(pid).set(attr, kCFBooleanTrue) }
    }

    private static func lock(_ pid: pid_t) -> NSLock {
        tableLock.withLock {
            if let existing = locks[pid] { return existing }
            let created = NSLock()
            locks[pid] = created
            return created
        }
    }
}
