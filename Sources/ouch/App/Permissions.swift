// App: Accessibility and Input Monitoring permission checks and requests.
import AppKit
import SwiftUI

// MARK: - Permissions

enum Permissions {
    /// Input Monitoring lets Caps Lock shortcuts fire at the real key press (see Hotkeys.startRawCaps).
    /// Optional: without it they still work, after macOS's own Caps Lock delay.
    static var inputMonitoringGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    /// Starts the Input Monitoring grant flow: the first request shows macOS's prompt (and lists us),
    /// later ones go straight to the list. Either way the guide walks through it.
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

    /// Drops a stale Input Monitoring entry (same story as `clearStaleEntry`) and starts over.
    static func resetInputMonitoring() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "ListenEvent", Bundle.main.bundleIdentifier ?? "local.ouch"]
        try? p.run()
        p.waitUntilExit()
        requestInputMonitoring()
    }

    /// Whether this launch already asked macOS to list us (which also shows its own alert). Asking again
    /// would clear the entry it just added and stack another alert, so later requests only reopen Settings.
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

    /// Drops any Accessibility entry left by an older build or moved copy; it would show as
    /// "on" in System Settings while macOS rejects this binary.
    static func clearStaleEntry() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "local.ouch"]
        try? p.run()
        p.waitUntilExit()
    }

    /// Starts the grant flow: the first time, from a clean slate (clear stale entry, prompt so we're
    /// listed); after that just Settings + guide again.
    static func request() {
        guard !AXIsProcessTrusted() else { return }
        if prompted { openSettings() } else { promptThenSettings() }
    }

    static func reset() { promptThenSettings() }

    /// macOS only adds us to the list when its alert's "Open System Settings" is clicked, so while that
    /// alert is up the guide points at it instead of opening a list we aren't in yet. If no alert comes
    /// (macOS shows it once per entry), open Settings ourselves.
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

    /// Closes the System Settings window (needs Accessibility, which we have by now).
    static func closeSettingsWindows() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return }
        for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
            window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        }
    }

    /// The prompt shows macOS's own "would like to control this computer" alert, which stays up after
    /// the switch is turned on in Settings. Once we're trusted we can reach it: press its default
    /// button ("Open System Settings", harmless; Settings is closed right after). Never "Deny".
    static func dismissSystemAlert() {
        guard AXIsProcessTrusted() else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn") {
            for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
                window.element(kAXDefaultButtonAttribute)?.perform(kAXPressAction)
            }
        }
    }
}
