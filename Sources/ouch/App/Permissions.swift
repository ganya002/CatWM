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
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return }
        for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
            window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        }
    }

    static func dismissSystemAlert() {
        guard accessibility.isGranted else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn") {
            for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
                window.element(kAXDefaultButtonAttribute)?.perform(kAXPressAction)
            }
        }
    }
}

enum Permissions {
    static func request() { Permission.accessibility.request() }
    static func reset() { Permission.accessibility.reset() }
    static func requestInputMonitoring() { Permission.inputMonitoring.request() }
}

final class PermissionWatcher {
    static let shared = PermissionWatcher()
    let atLaunch = PermissionWatcher.check()
    private(set) var granted: Set<Permission> = []
    private var timer: Timer?
    private var subscribers: [(_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void] = []

    private static func check() -> Set<Permission> { Set(Permission.allCases.filter(\.isGranted)) }

    func start() {
        guard timer == nil else { return }
        granted = Self.check()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
    }

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

extension Process {
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
