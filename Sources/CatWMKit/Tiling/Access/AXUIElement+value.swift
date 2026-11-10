import AppKit
import ApplicationServices
import QuartzCore

extension AXUIElement {
    package func value(_ attr: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return noted { AXUIElementCopyAttributeValue(self, attr as CFString, &result) } == .success ? result : nil
    }
    package func string(_ attr: String) -> String? { value(attr) as? String }
    package func flag(_ attr: String, default fallback: Bool = false) -> Bool { (value(attr) as? Bool) ?? fallback }
    package func element(_ attr: String) -> AXUIElement? {
        guard let result = value(attr), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(result, to: AXUIElement.self)
    }
    package func elements(_ attr: String) -> [AXUIElement] { (value(attr) as? [AXUIElement]) ?? [] }

    package func point(_ attr: String) -> CGPoint? {
        guard let result = value(attr), CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(unsafeDowncast(result, to: AXValue.self), .cgPoint, &point) ? point : nil
    }
    package func size(_ attr: String) -> CGSize? {
        guard let result = value(attr), CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(unsafeDowncast(result, to: AXValue.self), .cgSize, &size) ? size : nil
    }
    package var frame: CGRect {
        guard let point = point(kAXPositionAttribute), let size = size(kAXSizeAttribute),
              [point.x, point.y, size.width, size.height].allSatisfy(\.isFinite) else { return .null }
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    package func set(_ attr: String, _ newValue: CFTypeRef) -> Bool {
        noted { AXUIElementSetAttributeValue(self, attr as CFString, newValue) } == .success
    }
    package func isSettable(_ attr: String) -> Bool {
        var settable = DarwinBoolean(false)
        return noted { AXUIElementIsAttributeSettable(self, attr as CFString, &settable) } == .success
            && settable.boolValue
    }
    package func perform(_ action: String) { noted { AXUIElementPerformAction(self, action as CFString) } }

    @discardableResult
    package func noted(_ call: () -> AXError) -> AXError {
        let start = CACurrentMediaTime()
        let error = call()
        AXStalls.shared.note(self, error, since: start)
        return error
    }

    package var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard let axGetWindow, axGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }
}
