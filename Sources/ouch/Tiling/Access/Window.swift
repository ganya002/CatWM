import AppKit
import ApplicationServices

final class Window {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    var autoFloating = false
    var userFloating: Bool?
    var naturalFrame = CGRect.null
    var isFloating: Bool { userFloating ?? autoFloating }

    init(id: CGWindowID, element: AXUIElement, pid: pid_t, bundleID: String?) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID
        AXUIElementSetMessagingTimeout(element, 0.5)
    }

    private let frameLock = NSLock()
    private var lastFrame = CGRect.null

    var frame: CGRect {
        let f = element.frame
        if !f.isNull { frameLock.withLock { lastFrame = f } }
        return f
    }
    var cachedFrame: CGRect {
        let f = frameLock.withLock { lastFrame }
        return f.isNull ? frame : f
    }
    func remember(_ f: CGRect) {
        if !f.isNull { frameLock.withLock { lastFrame = f } }
    }
    var isValid: Bool { element.string(kAXRoleAttribute) != nil }
    var isNativeFullscreen: Bool { element.bool("AXFullScreen") ?? false }

    func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p), element.set(kAXPositionAttribute, v) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.origin = p } }
        }
    }
    func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s), element.set(kAXSizeAttribute, v) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.size = s } }
        }
    }
    func setFrame(_ r: CGRect) {
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)
    }

    func focus() {
        if !WindowServerFocus.focus(pid: pid, window: id) {
            axApp(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        element.set(kAXMainAttribute, kCFBooleanTrue)
        element.perform(kAXRaiseAction)
    }

    @discardableResult
    func close() -> String {
        let button = element.element(kAXCloseButtonAttribute)
            ?? element.elements(kAXChildrenAttribute).first { $0.string(kAXSubroleAttribute) == kAXCloseButtonSubrole }
        guard let button else { return "no close button" }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        return result == .success ? "pressed" : "press failed (AX error \(result.rawValue))"
    }

    func closeFromMenu() -> Bool {
        let bar = axApp(pid).element(kAXMenuBarAttribute)
        for top in bar?.elements(kAXChildrenAttribute) ?? [] {
            for menu in top.elements(kAXChildrenAttribute) {
                for item in menu.elements(kAXChildrenAttribute) where ["Close Window", "Close"].contains(item.string(kAXTitleAttribute) ?? "") {
                    guard item.bool(kAXEnabledAttribute) != false else { continue }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }
}
