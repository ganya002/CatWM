import AppKit
import ApplicationServices

struct EnhancedUI {
    private static let attr = "AXEnhancedUserInterface"
    let pid: pid_t
    private var holds = 0
    private var wasOn = false

    init(pid: pid_t) { self.pid = pid }

    mutating func suspend() {
        holds += 1
        guard holds == 1 else { return }
        let app = axApp(pid)
        wasOn = app.flag(Self.attr)
        if wasOn { app.set(Self.attr, kCFBooleanFalse) }
    }

    mutating func resume() {
        guard holds > 0 else { return }
        holds -= 1
        if holds == 0, wasOn { axApp(pid).set(Self.attr, kCFBooleanTrue) }
    }
}
