import AppKit
@testable import CatWM
import Testing

@Suite struct ForgetWindowStateTests {
    @Test @MainActor func forgettingAWindowReleasesItsNativeMove() {
        let manager = WindowManager()
        manager.config.virtualWorkspaces = false
        let window = Window(id: 41, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        manager.windows[window.id] = window
        manager.desktops.nativeMoveTargets[window.id] = "2"
        manager.desktops.nativeMembership[window.id] = 9
        manager.forget(window.id)
        #expect(manager.desktops.nativeMoveTargets.isEmpty)
        #expect(manager.desktops.nativeMembership.isEmpty)
    }
}
