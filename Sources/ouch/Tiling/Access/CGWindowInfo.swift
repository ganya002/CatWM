import AppKit
import ApplicationServices

struct CGWindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect

    static func onScreen() -> [CGWindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let n = d[kCGWindowNumber as String] as? Int,
                  let pid = d[kCGWindowOwnerPID as String] as? Int,
                  let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { return nil }
            return CGWindowInfo(id: CGWindowID(n), pid: pid_t(pid), bounds: bounds)
        }
    }
}
