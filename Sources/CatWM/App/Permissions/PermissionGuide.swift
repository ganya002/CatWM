import AppKit
import CatWMKit
import PermissionFlow

extension Permission {
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
        if self == .screenRecording { ScreenRecording.shared.watching = true }
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

final class PermissionGuide {
    static let shared = PermissionGuide()
    @MainActor private lazy var flow = PermissionFlow.makeController()
    private var kind: Permission?
    var onGranted: (() -> Void)?

    func show(_ kind: Permission) {
        self.kind = kind
        Task { @MainActor in flow.authorize(pane: kind.pane, suggestedAppURLs: [Bundle.main.bundleURL]) }
    }

    func granted(_ granted: Permission) {
        guard kind == granted else { return }
        kind = nil
        Task { @MainActor in flow.closePanel() }
        Permission.closeSettingsWindows()
        onGranted?()
    }
}
