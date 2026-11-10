import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct ForgetWindowStateTests {
    @Test @MainActor func forgettingAWindowReleasesItsNativeMove() {
        let manager = WindowManager(config: .parse(defaultText))
        manager.config.virtualWorkspaces = false
        let window = Window(id: 41, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        manager.windows[window.id] = window
        manager.nativeMoves.requestWorkspace(window.id, workspace: "2")
        manager.nativeMoves.finish(window.id, on: 9)
        manager.forget(window.id)
        #expect(manager.nativeMoves.isEmpty)
        #expect(manager.nativeMoves.observedMembership(window.id, observed: []).isEmpty)
    }
}
