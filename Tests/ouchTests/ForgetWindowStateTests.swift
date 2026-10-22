import AppKit
@testable import ouch
import Testing

@Suite struct ForgetWindowStateTests {
    @Test @MainActor func forgettingAWindowReleasesItsNativeMove() {
        let manager = WindowManager()
        manager.config.virtualWorkspaces = false
        let window = Window(id: 41, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        manager.windows[window.id] = window
        manager.nativeMoveTargets[window.id] = "2"
        manager.nativeMembership[window.id] = 9
        manager.forget(window.id)
        #expect(manager.nativeMoveTargets.isEmpty)
        #expect(manager.nativeMembership.isEmpty)
    }
}
