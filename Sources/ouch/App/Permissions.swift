import AppKit
import SwiftUI


enum Permissions {
    static var inputMonitoringGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    static func requestInputMonitoring() {
        guard !inputMonitoringGranted else { return }
        let first = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown
        if first { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        PermissionGuide.shared.show(.inputMonitoring)
        DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 0.8 : 0)) {
            if !inputMonitoringGranted { openInputMonitoringPane() }
        }
    }

    private static func openInputMonitoringPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    static func resetInputMonitoring() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "ListenEvent", Bundle.main.bundleIdentifier ?? "local.ouch"]
        try? p.run()
        p.waitUntilExit()
        requestInputMonitoring()
    }

    private static var prompted = false

    static func openSettings() {
        openPane()
        PermissionGuide.shared.show()
    }

    private static func openPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func clearStaleEntry() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "local.ouch"]
        try? p.run()
        p.waitUntilExit()
    }

    static func request() {
        guard !AXIsProcessTrusted() else { return }
        if prompted { openSettings() } else { promptThenSettings() }
    }

    static func reset() { promptThenSettings() }

    private static func promptThenSettings() {
        prompt()
        PermissionGuide.shared.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if PermissionGuide.alertFrame() == nil, !AXIsProcessTrusted() { openPane() }
        }
    }

    private static func prompt() {
        prompted = true
        clearStaleEntry()
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func closeSettingsWindows() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return }
        for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
            window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        }
    }

    static func dismissSystemAlert() {
        guard AXIsProcessTrusted() else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn") {
            for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
                window.element(kAXDefaultButtonAttribute)?.perform(kAXPressAction)
            }
        }
    }
}
