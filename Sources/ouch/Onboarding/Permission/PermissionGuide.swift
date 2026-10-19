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
            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            guard let primary = NSScreen.screens.first,
                  let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
            else { return }
            let agent = Self.pid(of: "com.apple.accessibility.universalAccessAuthWarn")
            let settingsPID = Self.pid(of: "com.apple.systempreferences")
            for info in list {
                guard let pid = (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init),
                      pid == agent || pid == settingsPID,
                      let dict = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
                let frame = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
                if pid == agent, alert == nil, rect.width > 150, rect.height > 80 { alert = frame }
                let layer = info[kCGWindowLayer as String] as? Int
                if pid == settingsPID, settings == nil, layer == 0, rect.width > 200 { settings = frame }
            }
        }

        private static func pid(of bundleID: String) -> pid_t? {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        }
    }
}
