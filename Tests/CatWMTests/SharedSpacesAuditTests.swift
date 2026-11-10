import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct SharedSpacesAuditTests {
    @Test func showsAWorkspaceOnOneDisplayWhenDisplaysShareTheirSpaces() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "left", spaces: [11, 12]), .init(id: "right", spaces: [11, 12])])
        #expect(catalog.entries.filter { $0.name == "1" }.count == 2)
        let shown = catalog.shown([(display: "left", space: 11), (display: "right", space: 11)])
        #expect(shown == ["left": "1"])
    }

    @Test func showsEachDisplayItsOwnWorkspaceWhenSpacesAreSeparate() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "left", spaces: [11]), .init(id: "right", spaces: [21])])
        let shown = catalog.shown([(display: "left", space: 11), (display: "right", space: 21),
                                   (display: "x", space: 9)])
        #expect(shown == ["left": "1", "right": "2"])
    }

    @Test func forgetsTheLearnedMenuBarWhenTheVisibleFrameChanges() {
        let visible = CGRect(x: 0, y: 24, width: 1440, height: 876)
        let floor = WindowManager.MenuBarFloor(height: 37, visible: visible)
        #expect(floor.height(on: visible) == 37)
        #expect(floor.height(on: CGRect(x: 0, y: 0, width: 1440, height: 900)) == nil)
    }
}
