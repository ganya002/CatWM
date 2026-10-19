import AppKit
import ApplicationServices

extension CGWindowInfo {
    static func normalWindow(at point: CGPoint) -> CGWindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let blocking: Set<Int> = [Int(CGWindowLevelForKey(.dockWindow)), Int(CGWindowLevelForKey(.mainMenuWindow)),
                                  Int(CGWindowLevelForKey(.statusWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))]
        for info in list {
            guard let rawBounds = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
                  bounds.contains(point), let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let number = info[kCGWindowNumber as String] as? Int
            else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.01 || FocusDim.shared.owns(number) { continue }
            if pid == Int(getpid()) {
                if NSApp.window(withWindowNumber: number)?.ignoresMouseEvents == false { return nil }
                continue
            }
            if layer == 0 { return CGWindowInfo(id: CGWindowID(number), pid: pid_t(pid), bounds: bounds) }
            if blocking.contains(layer) { return nil }
        }
        return nil
    }
}
