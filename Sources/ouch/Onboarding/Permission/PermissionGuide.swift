import AppKit
import SwiftUI

final class PermissionGuide {

    static let shared = PermissionGuide()
    var panel: NSPanel?
    var host: NSView?
    var follow: Timer?
    let model = GuideModel()
    var kind = Permission.accessibility
    let gap: CGFloat = 12

    var isShowing: Bool { (panel?.isVisible ?? false) && (panel?.alphaValue ?? 0) > 0 }
    var pending = false
    var finishing = false
    var hidden = false
    var sawSettings = false
    var sawAlert = false
    var missingTicks = 0
    var waitTicks = 0
    var target: NSRect?
    var steadyTicks = 0
    var placed: NSRect?
    var userMoved = false
    var movedAt = Date.distantPast

    var onGranted: (() -> Void)?

    struct Snapshot {
        var alert: NSRect?
        var settings: NSRect?

        init() {
            guard let primary = NSScreen.screens.first,
                  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            else { return }
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn").first?.processIdentifier
            let settingsPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier
            for info in list {
                guard let pid = (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init), pid == agent || pid == settingsPID,
                      let dict = info[kCGWindowBounds as String] as? NSDictionary,
                      let r = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
                let frame = NSRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height)
                if pid == agent, alert == nil, r.width > 150, r.height > 80 { alert = frame }
                if pid == settingsPID, settings == nil, (info[kCGWindowLayer as String] as? Int) == 0, r.width > 200 { settings = frame }
            }
        }
    }
}
