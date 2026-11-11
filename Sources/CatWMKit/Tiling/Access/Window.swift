import AppKit
import os

private struct ElementReference: Sendable {
    let element: AXUIElement
}

@MainActor package final class Window {
    package enum FloatingChoice: Equatable {
        case automatic
        case chosen(Bool)
    }

    package nonisolated let id: CGWindowID
    private nonisolated let reference: ElementReference
    package nonisolated var element: AXUIElement { reference.element }
    package nonisolated let pid: pid_t
    package nonisolated let bundleID: String?
    package nonisolated let backend: any WindowBackend
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

    package nonisolated static let messagingTimeout: Float = 0.5

    package nonisolated init(id: CGWindowID, element: AXUIElement, pid: pid_t, bundleID: String?,
                             backend: any WindowBackend = AXBackend.shared) {
        self.id = id
        reference = ElementReference(element: element)
        self.pid = pid
        self.bundleID = bundleID
        self.backend = backend
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    private struct FrameState {
        var last = CGRect.null
        var version = 0
        var observation = Date.distantPast
        var placementHeld = false
    }

    private nonisolated let frameState = OSAllocatedUnfairLock(initialState: FrameState())

    package nonisolated var placementSuspended: Bool {
        get { frameState.withLock { $0.placementHeld } }
        set { frameState.withLock { $0.placementHeld = newValue } }
    }

    package nonisolated var frame: CGRect {
        let version = frameRevision
        let readAt = Date()
        let current = backend.frame(of: self)
        remember(current, ifRevision: version, readAt: readAt)
        return current
    }
    package nonisolated var cachedFrame: CGRect {
        frameState.withLock { $0.last }
    }
    package nonisolated func remember(_ observed: CGRect) {
        if !observed.isNull {
            frameState.withLock { $0.last = observed; $0.version += 1; $0.observation = Date() }
        }
    }
    package nonisolated var frameRevision: Int { frameState.withLock { $0.version } }
    package nonisolated func remember(_ observed: CGRect, ifRevision version: Int, readAt: Date = Date()) {
        guard !observed.isNull else { return }
        frameState.withLock {
            guard $0.version == version, readAt >= $0.observation else { return }
            $0.last = observed
            $0.observation = readAt
        }
    }
    package nonisolated var isValid: Bool { element.string(kAXRoleAttribute) != nil }
    package nonisolated var isNativeFullscreen: Bool { element.flag("AXFullScreen") }

    package nonisolated func unlessStalled<T>(_ stalled: T, _ read: () -> T) -> T {
        AXStalls.shared.isStalled(pid) ? stalled : read()
    }
    package nonisolated var isValidUnlessStalled: Bool { unlessStalled(false) { isValid } }
    package nonisolated var fullscreenUnlessStalled: Bool { unlessStalled(false) { isNativeFullscreen } }
    package nonisolated var minimizedUnlessStalled: Bool {
        unlessStalled(false) { element.flag(kAXMinimizedAttribute) }
    }
    package nonisolated var frameUnlessStalled: CGRect { unlessStalled(.null) { frame } }

    @discardableResult
    package nonisolated func setPosition(_ origin: CGPoint) -> Bool {
        guard backend.setPosition(self, origin) else { return false }
        frameState.withLock { if !$0.last.isNull { $0.last.origin = origin; $0.version += 1 } }
        return true
    }
    @discardableResult
    package nonisolated func setSize(_ size: CGSize) -> Bool {
        guard backend.setSize(self, size) else { return false }
        frameState.withLock { if !$0.last.isNull { $0.last.size = size; $0.version += 1 } }
        return true
    }
    @discardableResult
    package nonisolated func setFrame(_ rect: CGRect) -> Bool {
        setSize(rect.size)
        let moved = setPosition(rect.origin)
        let sized = setSize(rect.size)
        return moved && sized
    }

    package nonisolated func focus(ifCurrent: () -> Bool = { true }) { backend.focus(self, ifCurrent: ifCurrent) }

    @discardableResult
    package nonisolated func close() -> String { backend.close(self) }

    package nonisolated func closeFromMenu() -> Bool {
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
