import AppKit
import PermissionFlow

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
        for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
            window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        }
    }
}
