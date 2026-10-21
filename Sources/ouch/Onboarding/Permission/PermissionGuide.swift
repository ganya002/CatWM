import AppKit
import PermissionFlow

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
