import AppKit
import ApplicationServices

final class Window {
    enum FloatingChoice: Equatable {
        case automatic
        case chosen(Bool)
    }

    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    var autoFloating = false
    var userFloating = FloatingChoice.automatic
    var naturalFrame = CGRect.null
    var observedAt = Date.distantPast
    var title: String?
    var resizable = true
    var minimized = false
    var fullscreen = false
    var isFloating: Bool {
        if case .chosen(let floating) = userFloating { return floating }
        return autoFloating
    }

    static let messagingTimeout: Float = 0.5

    init(id: CGWindowID, element: AXUIElement, pid: pid_t, bundleID: String?) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
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
        let current = element.frame
        remember(current, ifRevision: version, readAt: readAt)
        return current
    }
    var cachedFrame: CGRect {
        frameLock.withLock { lastFrame }
    }
    func remember(_ observed: CGRect) {
        if !observed.isNull {
            frameLock.withLock { lastFrame = observed; frameVersion += 1; lastFrameObservation = Date() }
        }
    }
    var frameRevision: Int { frameLock.withLock { frameVersion } }
    func remember(_ observed: CGRect, ifRevision version: Int, readAt: Date = Date()) {
        guard !observed.isNull else { return }
        frameLock.withLock {
            guard frameVersion == version, readAt >= lastFrameObservation else { return }
            lastFrame = observed
            lastFrameObservation = readAt
        }
    }
    var isValid: Bool { element.string(kAXRoleAttribute) != nil }
    var isNativeFullscreen: Bool { element.flag("AXFullScreen") }

    func unlessStalled<T>(_ stalled: T, _ read: () -> T) -> T {
        AXStalls.shared.isStalled(pid) ? stalled : read()
    }
    var isValidUnlessStalled: Bool { unlessStalled(false) { isValid } }
    var fullscreenUnlessStalled: Bool { unlessStalled(false) { isNativeFullscreen } }
    var minimizedUnlessStalled: Bool { unlessStalled(false) { element.flag(kAXMinimizedAttribute) } }
    var frameUnlessStalled: CGRect { unlessStalled(.null) { frame } }

    func setPosition(_ origin: CGPoint) {
        var point = origin
        if let value = AXValueCreate(.cgPoint, &point), element.set(kAXPositionAttribute, value) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.origin = point; frameVersion += 1 } }
        }
    }
    func setSize(_ newSize: CGSize) {
        var size = newSize
        if let value = AXValueCreate(.cgSize, &size), element.set(kAXSizeAttribute, value) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.size = size; frameVersion += 1 } }
        }
    }
    func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
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
        let result = button.noted { AXUIElementPerformAction(button, kAXPressAction as CFString) }
        return result == .success ? "pressed" : "press failed (AX error \(result.rawValue))"
    }

    func closeFromMenu() -> Bool {
        let bar = axApp(pid).element(kAXMenuBarAttribute)
        for top in bar?.elements(kAXChildrenAttribute) ?? [] {
            for menu in top.elements(kAXChildrenAttribute) {
                for item in menu.elements(kAXChildrenAttribute)
                where ["Close Window", "Close"].contains(item.string(kAXTitleAttribute) ?? "") {
                    guard item.flag(kAXEnabledAttribute, default: true) else { continue }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }
}
