import AppKit
import ApplicationServices

enum EnhancedUI {
    private static var held: [pid_t: (count: Int, wasOn: Bool)] = [:]
    private static var locks: [pid_t: NSLock] = [:]
    private static let tableLock = NSLock()
    private static let attr = "AXEnhancedUserInterface"

    static func suspend(_ pid: pid_t) {
        let l = lock(pid)
        l.lock(); defer { l.unlock() }
        if let h = tableLock.withLock({ held[pid] }) { tableLock.withLock { held[pid] = (h.count + 1, h.wasOn) }; return }
        let app = axApp(pid)
        let on = app.bool(attr) ?? false
        if on { app.set(attr, kCFBooleanFalse) }
        tableLock.withLock { held[pid] = (1, on) }
    }
    static func resume(_ pid: pid_t) {
        let l = lock(pid)
        l.lock(); defer { l.unlock() }
        guard let h = tableLock.withLock({ held[pid] }) else { return }
        if h.count > 1 { tableLock.withLock { held[pid] = (h.count - 1, h.wasOn) }; return }
        tableLock.withLock { held[pid] = nil }
        if h.wasOn { axApp(pid).set(attr, kCFBooleanTrue) }
    }

    private static func lock(_ pid: pid_t) -> NSLock {
        tableLock.withLock {
            if let l = locks[pid] { return l }
            let l = NSLock()
            locks[pid] = l
            return l
        }
    }
}
