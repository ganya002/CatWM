import AppKit
import PermissionFlow
import SwiftUI

enum Permission: CaseIterable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case fullDiskAccess

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .screenRecording: ScreenRecording.isGranted
        case .fullDiskAccess: NotificationDatabase.isReadable
        }
    }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen & System Audio Recording"
        case .fullDiskAccess: "Full Disk Access"
        }
    }

    var pane: PermissionFlowPane {
        switch self {
        case .accessibility: .accessibility
        case .inputMonitoring: .inputMonitoring
        case .screenRecording: .screenRecording
        case .fullDiskAccess: .fullDiskAccess
        }
    }

    private var tccService: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "ListenEvent"
        case .screenRecording: "ScreenCapture"
        case .fullDiskAccess: "SystemPolicyAllFiles"
        }
    }

    func request() {
        guard !isGranted else { return }
        if self == .screenRecording { ScreenRecording.watching = true }
        PermissionGuide.shared.show(self)
    }

    func reset() {
        Process.runTool("/usr/bin/tccutil", ["reset", tccService, Bundle.main.bundleIdentifier ?? "local.catwm"])
        PermissionGuide.shared.show(self)
    }

    static func closeSettingsWindows() {
        let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        guard let app = settings.first else { return }
        for window in axApp(app.processIdentifier).elements(kAXWindowsAttribute) {
            window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        }
    }
}

enum Permissions {
    static func request() { Permission.accessibility.request() }
    static func reset() { Permission.accessibility.reset() }
    static func requestInputMonitoring() { Permission.inputMonitoring.request() }
}

extension Process {
    static func runTool(_ path: String, _ args: [String], wait: Bool = true) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.info("run \(path) failed: \(error)")
            return
        }
        if wait { process.waitUntilExit() }
    }
}

final class PermissionGuide {
    static let shared = PermissionGuide()
    private let flow = MainActor.assumeIsolated { PermissionFlow.makeController() }
    private var kind: Permission?
    var onGranted: (() -> Void)?

    func show(_ kind: Permission) {
        self.kind = kind
        MainActor.assumeIsolated {
            flow.authorize(pane: kind.pane, suggestedAppURLs: [Bundle.main.bundleURL])
        }
    }

    func granted(_ granted: Permission) {
        guard kind == granted else { return }
        kind = nil
        MainActor.assumeIsolated { flow.closePanel() }
        Permission.closeSettingsWindows()
        onGranted?()
    }
}
