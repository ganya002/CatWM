import AppKit
import ApplicationServices

struct CGWindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect

    static func onScreen() -> [CGWindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let rawBounds = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else { return nil }
            return CGWindowInfo(id: CGWindowID(number), pid: pid_t(pid), bounds: bounds)
        }
    }
}
