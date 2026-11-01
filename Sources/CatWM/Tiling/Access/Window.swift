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
    let backend: any WindowBackend
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

    init(id: CGWindowID, element: AXUIElement, pid: pid_t, bundleID: String?,
         backend: any WindowBackend = AXBackend.shared) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID; self.backend = backend
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
        let current = backend.frame(of: self)
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
        if backend.setPosition(self, origin) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.origin = origin; frameVersion += 1 } }
        }
    }
    func setSize(_ size: CGSize) {
        if backend.setSize(self, size) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.size = size; frameVersion += 1 } }
        }
    }
    func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
    }

    func focus(ifCurrent: () -> Bool = { true }) { backend.focus(self, ifCurrent: ifCurrent) }

    @discardableResult
    func close() -> String { backend.close(self) }

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

struct WindowPlacementState {
    let blocked: Bool
    private static let names = ["AXFullScreen", kAXMinimizedAttribute]

    static func blocksPlacement(_ element: AXUIElement) -> Bool {
        var values: CFArray?
        if AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
           let values = values as? [Any], let state = decode(values) { return state.blocked }
        return element.flag(names[0]) || element.flag(names[1])
    }

    static func decode(_ values: [Any]) -> Self? {
        guard values.count == names.count else { return nil }
        return Self(blocked: (values[0] as? Bool ?? false) || (values[1] as? Bool ?? false))
    }
}
