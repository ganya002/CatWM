import AppKit
import ApplicationServices

package let axTimeout: Float = 0.3

package func axApp(_ pid: pid_t, timeout: Float = axTimeout) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, timeout)
    return app
}

package typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

package let axGetWindow: GetWindowFn? = {
    let path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"
    guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(address, to: GetWindowFn.self)
}()

package enum AXRead<T> {
    case value(T)
    case missing
    case stalled

    package var value: T? {
        if case .value(let found) = self { return found }
        return nil
    }
}

extension AXUIElement {
    package var windowNumber: CGWindowID? {
        var id: CGWindowID = 0
        guard let axGetWindow, axGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }

    package func read(_ attribute: String) -> AXRead<CFTypeRef> {
        var raw: CFTypeRef?
        switch AXUIElementCopyAttributeValue(self, attribute as CFString, &raw) {
        case .success:
            guard let raw else { return .missing }
            return .value(raw)
        case .cannotComplete:
            return .stalled
        default:
            return .missing
        }
    }

    package func readString(_ attribute: String) -> AXRead<String> {
        cast(read(attribute)) { $0 as? String }
    }

    package func readBool(_ attribute: String) -> AXRead<Bool> {
        cast(read(attribute)) { $0 as? Bool }
    }

    package func readElements(_ attribute: String) -> AXRead<[AXUIElement]> {
        switch read(attribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw):
            guard let list = raw as? [AXUIElement] else { return .stalled }
            return .value(list)
        }
    }

    package func readElement(_ attribute: String) -> AXRead<AXUIElement> {
        cast(read(attribute)) { raw in
            CFGetTypeID(raw) == AXUIElementGetTypeID() ? unsafeDowncast(raw, to: AXUIElement.self) : nil
        }
    }

    package func readSettable(_ attribute: String) -> AXRead<Bool> {
        var value = DarwinBoolean(false)
        switch AXUIElementIsAttributeSettable(self, attribute as CFString, &value) {
        case .success: return .value(value.boolValue)
        case .cannotComplete: return .stalled
        default: return .missing
        }
    }

    package func readFrame() -> AXRead<CGRect> {
        let origin = readPoint(kAXPositionAttribute)
        let extent = readSize(kAXSizeAttribute)
        if case .stalled = origin { return .stalled }
        if case .stalled = extent { return .stalled }
        guard case .value(let position) = origin, case .value(let dimensions) = extent,
              [position.x, position.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite) else {
            return .missing
        }
        return .value(CGRect(origin: position, size: dimensions))
    }

    package func press() -> Bool {
        AXUIElementPerformAction(self, kAXPressAction as CFString) == .success
    }

    private func readPoint(_ attribute: String) -> AXRead<CGPoint> {
        cast(read(attribute)) { raw in
            guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var point = CGPoint.zero
            return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgPoint, &point) ? point : nil
        }
    }

    private func readSize(_ attribute: String) -> AXRead<CGSize> {
        cast(read(attribute)) { raw in
            guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var size = CGSize.zero
            return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgSize, &size) ? size : nil
        }
    }

    private func cast<V>(_ read: AXRead<CFTypeRef>, _ convert: (CFTypeRef) -> V?) -> AXRead<V> {
        switch read {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw): return convert(raw).map { .value($0) } ?? .missing
        }
    }
}
