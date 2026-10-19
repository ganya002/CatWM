import AppKit
import SwiftUI

enum Permission: CaseIterable {
    case accessibility
    case inputMonitoring

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }

    var title: String { self == .accessibility ? "Accessibility" : "Input Monitoring" }

    func request() {
        guard !isGranted else { return }
        switch self {
        case .accessibility:
            if Self.prompted {
                openPane()
                PermissionGuide.shared.show()
            } else {
                Self.promptThenSettings()
            }
        case .inputMonitoring:
            let first = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown
            if first { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            PermissionGuide.shared.show(.inputMonitoring)
            DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 0.8 : 0)) {
                if !isGranted { openPane() }
            }
        }
    }

    func reset() {
        switch self {
        case .accessibility: Self.promptThenSettings()
        case .inputMonitoring:
            clearStaleEntry()
            request()
        }
    }

    func openPane() {
        let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func clearStaleEntry() {
        Process.runTool("/usr/bin/tccutil", ["reset", self == .accessibility ? "Accessibility" : "ListenEvent",
                                             Bundle.main.bundleIdentifier ?? "local.ouch"])
    }

    private static var prompted = false

    private static func promptThenSettings() {
        prompt()
        PermissionGuide.shared.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if PermissionGuide.alertFrame() == nil, !accessibility.isGranted { accessibility.openPane() }
        }
    }

    private static func prompt() {
        prompted = true
        accessibility.clearStaleEntry()
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func closeSettingsWindows() {
        let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        guard let app = settings.first else { return }
        for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
            window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        }
    }

    static func dismissSystemAlert() {
        guard accessibility.isGranted else { return }
        let alerts = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn")
        for app in alerts {
            for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
                window.element(kAXDefaultButtonAttribute)?.perform(kAXPressAction)
            }
        }
    }
}
