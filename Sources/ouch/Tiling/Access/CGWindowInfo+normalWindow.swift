import AppKit
import ApplicationServices

extension CGWindowInfo {
    static func normalWindow(at p: CGPoint) -> CGWindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let blocking: Set<Int> = [Int(CGWindowLevelForKey(.dockWindow)), Int(CGWindowLevelForKey(.mainMenuWindow)),
                                  Int(CGWindowLevelForKey(.statusWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))]
        for d in list {
            guard let b = d[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: b),
                  bounds.contains(p), let pid = d[kCGWindowOwnerPID as String] as? Int, let n = d[kCGWindowNumber as String] as? Int
            else { continue }
            let layer = d[kCGWindowLayer as String] as? Int ?? 0
            let alpha = d[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.01 || FocusDim.shared.owns(n) { continue }
            if pid == Int(getpid()) {
                if NSApp.window(withWindowNumber: n)?.ignoresMouseEvents == false { return nil }
                continue
            }
            if layer == 0 { return CGWindowInfo(id: CGWindowID(n), pid: pid_t(pid), bounds: bounds) }
            if blocking.contains(layer) { return nil }
        }
        return nil
    }
}
