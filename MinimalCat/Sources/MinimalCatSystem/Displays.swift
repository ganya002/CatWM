import AppKit
import MinimalCatCore

public enum Displays {
    /// The connected displays in top-left coordinates. Each one is named by a key that survives a restart:
    /// the system UUID, then vendor, model and serial, then the name and position.
    public static func current() -> [Display] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        var seen: Set<String> = []
        return NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            var key = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
            } ?? ""
            if key.isEmpty || seen.contains(key) {
                let serial = CGDisplaySerialNumber(id)
                key = serial != 0 ? "\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(serial)"
                                  : "\(screen.localizedName)#\(index)"
            }
            seen.insert(key)
            return Display(id: DisplayID(key), frame: flip(screen.frame), visible: flip(screen.visibleFrame))
        }
    }
}
