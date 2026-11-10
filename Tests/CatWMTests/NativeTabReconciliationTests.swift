import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct NativeTabReconciliationTests {
    @Test @MainActor func renumberingADesktopPreservesItsTabGroups() async throws {
        let screen = try #require(Screen.all().first)
        let desktop = try #require(Spaces.list(display: screen.uuid))
        let space = desktop.ids[try #require(desktop.desktops.first)]
        let scanner = WindowScanner(readDesktop: { _ in
            WindowServerObservation(spaces: [1: [space], 2: [space], 3: [space]])
        }, readApplications: { [] })
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: [1, 2, 3]) { continuation.resume() }
        }
        let manager = WindowManager(config: .parse(defaultText), scanner: scanner)
        manager.config.virtualWorkspaces = true
        manager.config.workspacesPerDisplay = true
        manager.config.removesEmptyWorkspaces = false
        for id: CGWindowID in [1, 2, 3] {
            manager.windows[id] = Window(id: id, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
            manager.model.assign(id, to: WorkspaceKey.make("2", on: screen.uuid, perDisplay: true))
        }
        manager.order = [1, 2, 3]
        manager.model.joinTab(2, onto: 1)
        manager.model.joinTab(3, onto: 2)
        let group = manager.tabs.group(of: 1)
        let order = manager.order
        let result = manager.syncNativeWorkspaces(screens: [screen], present: [1, 2, 3])
        let workspace = try #require(manager.desktops.nativeCatalog.entry(space: space)?.name)
        #expect(result.model.workspaceOf == [1: workspace, 2: workspace, 3: workspace])
        #expect(result.model.tabs.group(of: 1) == group)
        #expect(result.model.order == order)
    }
}
