import AppKit

package struct WindowAttributes {
    package let fullscreen: Bool
    package let minimized: Bool
    package let subrole: String?
    package let frame: CGRect
    package let title: String?

    private static let names = ["AXFullScreen", kAXMinimizedAttribute, kAXSubroleAttribute,
                                kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute]

    package static func read(_ element: AXUIElement) -> Self {
        var values: CFArray?
        if AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
           let values = values as? [Any], let attributes = decode(values) { return attributes }
        return Self(values: names.map { element.value($0) as Any? ?? NSNull() })
    }

    package static func decode(_ values: [Any]) -> Self? {
        guard values.count == names.count else { return nil }
        return Self(values: values)
    }

    private init(values: [Any]) {
        fullscreen = values[0] as? Bool ?? false
        minimized = values[1] as? Bool ?? false
        subrole = values[2] as? String
        frame = Self.frame(position: values[3], size: values[4])
        title = values[5] as? String
    }

    private static func frame(position: Any, size: Any) -> CGRect {
        guard CFGetTypeID(position as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(size as CFTypeRef) == AXValueGetTypeID() else { return .null }
        let position = unsafeDowncast(position as CFTypeRef, to: AXValue.self)
        let size = unsafeDowncast(size as CFTypeRef, to: AXValue.self)
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
              [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite) else { return .null }
        return CGRect(origin: point, size: dimensions)
    }
}
