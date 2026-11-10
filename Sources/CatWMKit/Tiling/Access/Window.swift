import AppKit
import ApplicationServices

package final class Window {
    package enum FloatingChoice: Equatable {
        case automatic
        case chosen(Bool)
    }

    package let id: CGWindowID
    package let element: AXUIElement
    package let pid: pid_t
    package let bundleID: String?
    package let backend: any WindowBackend
    package var autoFloating = false
    package var userFloating = FloatingChoice.automatic
    package var naturalFrame = CGRect.null
    package var observedAt = Date.distantPast
    package var title: String?
    package var resizable = true
    package var minimized = false
    package var fullscreen = false
    package var isFloating: Bool {
        if case .chosen(let floating) = userFloating { return floating }
        return autoFloating
    }

    package static let messagingTimeout: Float = 0.5

    package init(id: CGWindowID, element: AXUIElement, pid: pid_t, bundleID: String?,
                 backend: any WindowBackend = AXBackend.shared) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID; self.backend = backend
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    private let frameLock = NSLock()
    private var lastFrame = CGRect.null
    private var frameVersion = 0
    private var lastFrameObservation = Date.distantPast
    private var placementHeld = false

    package var placementSuspended: Bool {
        get { frameLock.withLock { placementHeld } }
        set { frameLock.withLock { placementHeld = newValue } }
    }

    package var frame: CGRect {
        let version = frameRevision
        let readAt = Date()
        let current = backend.frame(of: self)
        remember(current, ifRevision: version, readAt: readAt)
        return current
    }
    package var cachedFrame: CGRect {
        frameLock.withLock { lastFrame }
    }
    package func remember(_ observed: CGRect) {
        if !observed.isNull {
            frameLock.withLock { lastFrame = observed; frameVersion += 1; lastFrameObservation = Date() }
        }
    }
    package var frameRevision: Int { frameLock.withLock { frameVersion } }
    package func remember(_ observed: CGRect, ifRevision version: Int, readAt: Date = Date()) {
        guard !observed.isNull else { return }
        frameLock.withLock {
            guard frameVersion == version, readAt >= lastFrameObservation else { return }
            lastFrame = observed
            lastFrameObservation = readAt
        }
    }
    package var isValid: Bool { element.string(kAXRoleAttribute) != nil }
    package var isNativeFullscreen: Bool { element.flag("AXFullScreen") }

    package func unlessStalled<T>(_ stalled: T, _ read: () -> T) -> T {
        AXStalls.shared.isStalled(pid) ? stalled : read()
    }
    package var isValidUnlessStalled: Bool { unlessStalled(false) { isValid } }
    package var fullscreenUnlessStalled: Bool { unlessStalled(false) { isNativeFullscreen } }
    package var minimizedUnlessStalled: Bool { unlessStalled(false) { element.flag(kAXMinimizedAttribute) } }
    package var frameUnlessStalled: CGRect { unlessStalled(.null) { frame } }

    package func setPosition(_ origin: CGPoint) {
        if backend.setPosition(self, origin) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.origin = origin; frameVersion += 1 } }
        }
    }
    package func setSize(_ size: CGSize) {
        if backend.setSize(self, size) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.size = size; frameVersion += 1 } }
        }
    }
    package func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
    }

    package func focus(ifCurrent: () -> Bool = { true }) { backend.focus(self, ifCurrent: ifCurrent) }

    @discardableResult
    package func close() -> String { backend.close(self) }

    package func closeFromMenu() -> Bool {
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

package struct WindowPlacementState {
    package let blocked: Bool
    private static let names = ["AXFullScreen", kAXMinimizedAttribute]

    package static func blocksPlacement(_ element: AXUIElement) -> Bool {
        var values: CFArray?
        if AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
           let values = values as? [Any], let state = decode(values) { return state.blocked }
        return element.flag(names[0]) || element.flag(names[1])
    }

    package static func decode(_ values: [Any]) -> Self? {
        guard values.count == names.count else { return nil }
        return Self(blocked: (values[0] as? Bool ?? false) || (values[1] as? Bool ?? false))
    }
}
