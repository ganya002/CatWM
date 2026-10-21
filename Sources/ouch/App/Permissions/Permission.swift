import AppKit
import PermissionFlow

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

    var pane: PermissionFlowPane { self == .accessibility ? .accessibility : .inputMonitoring }

    func request() {
        guard !isGranted else { return }
        PermissionGuide.shared.show(self)
    }

    func reset() {
        Process.runTool("/usr/bin/tccutil", ["reset", self == .accessibility ? "Accessibility" : "ListenEvent",
                                             Bundle.main.bundleIdentifier ?? "local.ouch"])
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
