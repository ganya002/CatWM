import AppKit

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
