import AppKit
import ApplicationServices

protocol WindowBackend: AnyObject {
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

final class AXBackend: WindowBackend {
    static let shared = AXBackend()

    func applications() -> [RunningApplicationSnapshot] { RunningApplicationSnapshot.read() }

    func desktop(known: Set<CGWindowID>) -> WindowServerObservation { WindowServerObservation.read(known: known) }

    func scan(_ job: WindowScanner.Job, discovered: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
        WindowScanner.read(job, discovered: discovered)
    }

    func focusedWindow(pid: pid_t) -> FocusReader.Result { FocusReader.read(pid) }

    func screens() -> [Screen] { Screen.all() }

    func currentSpace(display: String) -> UInt64 { Spaces.current(display: display) }

    func isRunning(_ pid: pid_t) -> Bool { NSRunningApplication(processIdentifier: pid) != nil }

    func frontmostPID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    func frame(of window: Window) -> CGRect { window.element.frame }

    func setPosition(_ window: Window, _ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return window.element.set(kAXPositionAttribute, value)
    }

    func setSize(_ window: Window, _ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return window.element.set(kAXSizeAttribute, value)
    }

    func blocksPlacement(_ window: Window) -> Bool { WindowPlacementState.blocksPlacement(window.element) }

    func suspendEnhancedUI(_ pid: pid_t) -> Bool {
        let app = axApp(pid)
        guard app.flag(EnhancedUI.attr) else { return false }
        app.set(EnhancedUI.attr, kCFBooleanFalse)
        return true
    }

    func resumeEnhancedUI(_ pid: pid_t) { axApp(pid).set(EnhancedUI.attr, kCFBooleanTrue) }

    func focus(_ window: Window, ifCurrent: () -> Bool) {
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

    func close(_ window: Window) -> String {
        let button = window.element.element(kAXCloseButtonAttribute)
            ?? window.element.elements(kAXChildrenAttribute).first {
                $0.string(kAXSubroleAttribute) == kAXCloseButtonSubrole
            }
        guard let button else { return "no close button" }
        let result = button.noted { AXUIElementPerformAction(button, kAXPressAction as CFString) }
        return result == .success ? "pressed" : "press failed (AX error \(result.rawValue))"
    }

    func refreshCursor() { CursorRefresh.post() }
}
