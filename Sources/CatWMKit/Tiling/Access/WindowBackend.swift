import AppKit
import ApplicationServices

package protocol WindowBackend: AnyObject {
    func applications() -> [RunningApplicationSnapshot]
    func desktop(known: Set<CGWindowID>) -> WindowServerObservation
    func scan(_ job: WindowScanner.Job, discovered: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan
    func focusedWindow(pid: pid_t) -> FocusReader.Result
    func screens() -> [Screen]
    func currentSpace(display: String) -> UInt64
    func isRunning(_ pid: pid_t) -> Bool
    func frontmostPID() -> pid_t?
    func frame(of window: Window) -> CGRect
    func setPosition(_ window: Window, _ point: CGPoint) -> Bool
    func setSize(_ window: Window, _ size: CGSize) -> Bool
    func blocksPlacement(_ window: Window) -> Bool
    func suspendEnhancedUI(_ pid: pid_t) -> Bool
    func resumeEnhancedUI(_ pid: pid_t)
    func focus(_ window: Window, ifCurrent: () -> Bool)
    func refreshCursor()
    func close(_ window: Window) -> String
}

package final class AXBackend: WindowBackend {
    package static let shared = AXBackend()

    package func applications() -> [RunningApplicationSnapshot] { RunningApplicationSnapshot.read() }

    package func desktop(known: Set<CGWindowID>) -> WindowServerObservation {
        WindowServerObservation.read(known: known)
    }

    package func scan(_ job: WindowScanner.Job, discovered: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
        WindowScanner.read(job, discovered: discovered)
    }

    package func focusedWindow(pid: pid_t) -> FocusReader.Result { FocusReader.read(pid) }

    package func screens() -> [Screen] { Screen.all() }

    package func currentSpace(display: String) -> UInt64 { Spaces.current(display: display) }

    package func isRunning(_ pid: pid_t) -> Bool { NSRunningApplication(processIdentifier: pid) != nil }

    package func frontmostPID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    package func frame(of window: Window) -> CGRect { window.element.frame }

    package func setPosition(_ window: Window, _ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return window.element.set(kAXPositionAttribute, value)
    }

    package func setSize(_ window: Window, _ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return window.element.set(kAXSizeAttribute, value)
    }

    package func blocksPlacement(_ window: Window) -> Bool { WindowPlacementState.blocksPlacement(window.element) }

    package func suspendEnhancedUI(_ pid: pid_t) -> Bool {
        let app = axApp(pid)
        guard app.flag(EnhancedUI.attr) else { return false }
        app.set(EnhancedUI.attr, kCFBooleanFalse)
        return true
    }

    package func resumeEnhancedUI(_ pid: pid_t) { axApp(pid).set(EnhancedUI.attr, kCFBooleanTrue) }

    package func focus(_ window: Window, ifCurrent: () -> Bool) {
        guard ifCurrent() else { return }
        if !WindowServerFocus.focus(pid: window.pid, window: window.id) {
            axApp(window.pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
        guard ifCurrent() else { return }
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        guard ifCurrent() else { return }
        window.element.perform(kAXRaiseAction)
    }

    package func close(_ window: Window) -> String {
        let button = window.element.element(kAXCloseButtonAttribute)
            ?? window.element.elements(kAXChildrenAttribute).first {
                $0.string(kAXSubroleAttribute) == kAXCloseButtonSubrole
            }
        guard let button else { return "no close button" }
        let result = button.noted { AXUIElementPerformAction(button, kAXPressAction as CFString) }
        return result == .success ? "pressed" : "press failed (AX error \(result.rawValue))"
    }

    package func refreshCursor() { CursorRefresh.post() }
}
