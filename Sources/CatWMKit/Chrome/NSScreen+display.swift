import AppKit

extension NSScreen {
    package static var userScreens: [NSScreen] {
        screens.filter { $0.displayID.map { !AgentDisplay.owns($0) } ?? true }
    }

    package var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
    }

    package var displayUUID: String? {
        displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }
}
