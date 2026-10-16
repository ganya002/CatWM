// App: Accessibility and Input Monitoring: checks, grant flows, and the watcher that sees them change.
import AppKit
import SwiftUI

// MARK: - Permission

enum Permission: CaseIterable {
    /// Needed for everything: window control and the key tap.
    case accessibility
    /// Lets Caps Lock shortcuts fire at the real key press (see CapsLockChord).
    /// Optional: without it they still work, after macOS's own Caps Lock delay.
    case inputMonitoring

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }

    var title: String { self == .accessibility ? "Accessibility" : "Input Monitoring" }

    /// Starts the grant flow; does nothing when already granted.
    func request() {
        guard !isGranted else { return }
        switch self {
        case .accessibility:
            // The first time from a clean slate (clear stale entry, prompt so we're listed); after that
            // just Settings + guide again.
            if Self.prompted {
                openPane()
                PermissionGuide.shared.show()
            } else {
                Self.promptThenSettings()
            }
        case .inputMonitoring:
            // The first request shows macOS's prompt (and lists us), later ones go straight to the list.
            // Either way the guide walks through it.
            let first = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown
            if first { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            PermissionGuide.shared.show(.inputMonitoring)
            DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 0.8 : 0)) {
                if !isGranted { openPane() }
            }
        }
    }

    /// Drops our entry and asks again. A rebuild changes the signature, so the list can show an old
    /// entry as "on" while macOS rejects this binary.
    func reset() {
        switch self {
        case .accessibility: Self.promptThenSettings()
        case .inputMonitoring:
            clearStaleEntry()
            request()
        }
    }

    /// Opens this permission's list in System Settings.
    func openPane() {
        let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Drops any entry left by an older build or moved copy; it would show as "on" in System Settings
    /// while macOS rejects this binary.
    private func clearStaleEntry() {
        Process.runTool("/usr/bin/tccutil", ["reset", self == .accessibility ? "Accessibility" : "ListenEvent",
                                             Bundle.main.bundleIdentifier ?? "local.ouch"])
    }

    /// Whether this launch already asked macOS to list us (which also shows its own alert). Asking again
    /// would clear the entry it just added and stack another alert, so later requests only reopen Settings.
    private static var prompted = false

    /// macOS only adds us to the list when its alert's "Open System Settings" is clicked, so while that
    /// alert is up the guide points at it instead of opening a list we aren't in yet. If no alert comes
    /// (macOS shows it once per entry), open Settings ourselves.
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
        guard accessibility.isGranted else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn") {
            for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
                window.element(kAXDefaultButtonAttribute)?.perform(kAXPressAction)
            }
        }
    }
}

/// Shorthands Settings › General still calls; new code uses `Permission` directly.
enum Permissions {
    static func request() { Permission.accessibility.request() }
    static func reset() { Permission.accessibility.reset() }
    static func requestInputMonitoring() { Permission.inputMonitoring.request() }
}

// MARK: - Watcher

/// Checks both permissions every 1.5 s. Permission can be granted later, or silently revoked (a rebuild
/// changes the signature), and macOS sends no notice of either.
final class PermissionWatcher {
    static let shared = PermissionWatcher()
    /// What was granted when the app started (Input Monitoring decides if a relaunch could help).
    let atLaunch = PermissionWatcher.check()
    /// What the last check saw.
    private(set) var granted: Set<Permission> = []
    private var timer: Timer?
    private var subscribers: [(_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void] = []

    private static func check() -> Set<Permission> { Set(Permission.allCases.filter(\.isGranted)) }

    /// Takes the state to compare against and starts checking. Safe to call again.
    func start() {
        guard timer == nil else { return }
        granted = Self.check()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// `f` runs after every check with what is granted now and what changed since the check before.
    func subscribe(_ f: @escaping (_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void) {
        subscribers.append(f)
    }

    private func tick() {
        let now = Self.check()
        let changed = now.symmetricDifference(granted)
        granted = now
        subscribers.forEach { $0(now, changed) }
    }
}

// MARK: - Helper tools

extension Process {
    /// Runs a command-line tool with its output dropped. With `wait` it blocks until the tool exits.
    static func runTool(_ path: String, _ args: [String], wait: Bool = true) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        if wait { p.waitUntilExit() }
    }
}
