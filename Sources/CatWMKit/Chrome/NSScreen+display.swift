import AppKit

extension NSScreen {
    package var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
    }

    package var displayUUID: String? {
        displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }
}
