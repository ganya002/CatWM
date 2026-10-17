import AppKit
import ApplicationServices

extension AXUIElement {
    func value(_ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success ? v : nil
    }
    func string(_ attr: String) -> String? { value(attr) as? String }
    func bool(_ attr: String) -> Bool? { (value(attr) as? NSNumber)?.boolValue }
    func element(_ attr: String) -> AXUIElement? {
        guard let v = value(attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    func elements(_ attr: String) -> [AXUIElement] { (value(attr) as? [AXUIElement]) ?? [] }

    func point(_ attr: String) -> CGPoint? {
        guard let v = value(attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }
    func size(_ attr: String) -> CGSize? {
        guard let v = value(attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
    var frame: CGRect {
        guard let p = point(kAXPositionAttribute), let s = size(kAXSizeAttribute),
              [p.x, p.y, s.width, s.height].allSatisfy(\.isFinite) else { return .null }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    func set(_ attr: String, _ v: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attr as CFString, v) == .success
    }
    func isSettable(_ attr: String) -> Bool {
        var b = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, attr as CFString, &b) == .success && b.boolValue
    }
    func perform(_ action: String) { AXUIElementPerformAction(self, action as CFString) }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard let axGetWindow, axGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }
}
