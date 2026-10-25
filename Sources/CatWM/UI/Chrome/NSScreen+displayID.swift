import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
    }

    var displayUUID: String? {
        displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }

    var notchSides: (left: NSRect, right: NSRect)? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return (left, right)
    }
}
