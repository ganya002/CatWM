import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    var displayUUID: String? {
        displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }.map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }

    var notchSides: (left: NSRect, right: NSRect)? {
        guard let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return nil }
        return (l, r)
    }
}
