import AppKit
@testable import ouch
import Testing

@Suite struct NativeLayoutPreparationTests {
    @Test @MainActor func windowsOfHiddenAppsGetNoSlotBeforeTheSwitch() async throws {
        guard let screen = Screen.all().first else { return }
        let manager = WindowManager()
        manager.config.windowMargins = false
        let shown = Window(id: 1, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        let hidden = Window(id: 2, element: AXUIElementCreateApplication(-2), pid: -2, bundleID: nil)
        for window in [shown, hidden] {
            manager.windows[window.id] = window
            manager.order.append(window.id)
            manager.model.assign(window.id, to: "1")
        }
        manager.observedApps = [(pid: shown.pid, bundleID: nil)]
        try await manager.prepareNativeLayout(.init(workspace: "1", display: screen.uuid, space: 1))
        #expect(manager.targets[hidden.id] == nil)
        let alone = try #require(manager.layoutTargets([shown.id], manager.state(workspace: "1"), on: screen))
        #expect(manager.targets[shown.id] == alone[shown.id])
    }
}
