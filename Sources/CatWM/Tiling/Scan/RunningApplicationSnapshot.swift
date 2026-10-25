import AppKit

struct RunningApplicationSnapshot {
    let pid: pid_t
    let bundleID: String?
    let regular: Bool
    let hidden: Bool

    static func read() -> [Self] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid != getpid() else { return nil }
            let regular = app.activationPolicy == .regular
            return Self(pid: pid, bundleID: regular ? app.bundleIdentifier : nil,
                        regular: regular, hidden: regular && app.isHidden)
        }
    }
}
