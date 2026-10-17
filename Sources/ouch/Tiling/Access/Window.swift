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
    var observedAt = Date.distantPast
    var title: String?
    var resizable = true
    var minimized = false
    var fullscreen = false
    var isFloating: Bool { userFloating ?? autoFloating }

    init(id: CGWindowID, element: AXUIElement, pid: pid_t, bundleID: String?) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID
        AXUIElementSetMessagingTimeout(element, 0.5)
    }

    private let frameLock = NSLock()
    private var lastFrame = CGRect.null
    private var frameVersion = 0
    private var lastFrameObservation = Date.distantPast
    private var placementHeld = false

    var placementSuspended: Bool {
        get { frameLock.withLock { placementHeld } }
        set { frameLock.withLock { placementHeld = newValue } }
    }

    var frame: CGRect {
        let version = frameRevision
        let readAt = Date()
        let f = element.frame
        remember(f, ifRevision: version, readAt: readAt)
        return f
    }
    var cachedFrame: CGRect {
        frameLock.withLock { lastFrame }
    }
    func remember(_ f: CGRect) {
        if !f.isNull { frameLock.withLock { lastFrame = f; frameVersion += 1; lastFrameObservation = Date() } }
    }
    var frameRevision: Int { frameLock.withLock { frameVersion } }
    func remember(_ f: CGRect, ifRevision version: Int, readAt: Date = Date()) {
        guard !f.isNull else { return }
        frameLock.withLock {
            guard frameVersion == version, readAt >= lastFrameObservation else { return }
            lastFrame = f
            lastFrameObservation = readAt
        }
    }
    var isValid: Bool { element.string(kAXRoleAttribute) != nil }
    var isNativeFullscreen: Bool { element.bool("AXFullScreen") ?? false }

    func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p), element.set(kAXPositionAttribute, v) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.origin = p; frameVersion += 1 } }
        }
    }
    func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s), element.set(kAXSizeAttribute, v) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.size = s; frameVersion += 1 } }
        }
    }
    func setFrame(_ r: CGRect) {
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)
    }

    func focus(ifCurrent: () -> Bool = { true }) {
        guard ifCurrent() else { return }
        if !WindowServerFocus.focus(pid: pid, window: id) {
            axApp(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        guard ifCurrent() else { return }
        element.set(kAXMainAttribute, kCFBooleanTrue)
        guard ifCurrent() else { return }
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
