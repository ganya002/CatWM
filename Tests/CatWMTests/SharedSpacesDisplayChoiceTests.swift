import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct SharedSpacesDisplayChoiceTests {
    private let screens: [(id: String, frame: CGRect)] = [
        (id: "left", frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
        (id: "right", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
    ]
    private let leftSlot = CGRect(x: 10, y: 10, width: 480, height: 780)
    private let rightSlot = CGRect(x: 1010, y: 10, width: 480, height: 780)

    @Test func showsTheSharedWorkspaceOnEveryDisplay() {
        var catalog = NativeWorkspaceCatalog()
        catalog.sharedSpaces = true
        catalog.synchronize([.init(id: "left", spaces: [11, 12]), .init(id: "right", spaces: [11, 12])])
        let shown = catalog.shown([(display: "left", space: 11), (display: "right", space: 11)])
        #expect(shown == ["left": "1", "right": "1"])
    }

    @Test func picksTheDisplayUnderTheFrameCentre() {
        let frame = CGRect(x: 900, y: 100, width: 400, height: 300)
        #expect(SharedSpaces.display(of: frame, kept: nil, target: nil, settling: false, in: screens) == "right")
        #expect(SharedSpaces.display(of: leftSlot, kept: "right", target: nil, settling: false, in: screens) == "left")
    }

    @Test func keepsTheDisplayWhileTheWindowSettles() {
        let dragged = CGRect(x: 1200, y: 100, width: 400, height: 300)
        #expect(SharedSpaces.display(of: dragged, kept: "left", target: leftSlot, settling: true, in: screens)
            == "left")
    }

    @Test func keepsAChosenDisplayWhileTheWindowIsStillAtItsOldSlot() {
        #expect(SharedSpaces.display(of: leftSlot, kept: "right", target: leftSlot, settling: false, in: screens)
            == "right")
    }

    @Test func aWindowThatRefusesItsSlotFlipsAtMostOnce() {
        let refusedOnLeft = CGRect(x: 600, y: 10, width: 900, height: 780)
        let first = SharedSpaces.display(of: refusedOnLeft, kept: "left", target: leftSlot, settling: false,
                                         in: screens)
        #expect(first == "right")
        let refusedOnRight = CGRect(x: 400, y: 10, width: 900, height: 780)
        let second = SharedSpaces.display(of: refusedOnRight, kept: first, target: rightSlot, settling: true,
                                          in: screens)
        #expect(second == "right")
    }

    @Test func fallsBackToOverlapThenToTheKeptDisplay() {
        let partly = CGRect(x: 1800, y: -500, width: 400, height: 600)
        #expect(SharedSpaces.display(of: partly, kept: "left", target: nil, settling: false, in: screens) == "right")
        let away = CGRect(x: 5000, y: 5000, width: 10, height: 10)
        #expect(SharedSpaces.display(of: away, kept: "left", target: nil, settling: false, in: screens) == "left")
        #expect(SharedSpaces.display(of: .null, kept: "gone", target: nil, settling: false, in: screens) == "left")
    }

    @Test func tilesOnlyTheWindowsOnTheDisplay() throws {
        let nsScreen = try #require(NSScreen.screens.first)
        func screen(_ uuid: String) -> Screen {
            Screen(id: 0, uuid: uuid, frame: .zero, visible: .zero, isBuiltin: false, nsScreen: nsScreen)
        }
        let manager = WindowManager(config: .parse(defaultText))
        manager.desktops.nativeCatalog.sharedSpaces = true
        for id: CGWindowID in [1, 2] {
            let window = Window(id: id, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
            manager.windows[id] = window
            manager.order.append(id)
            manager.model.assign(id, to: "1")
        }
        manager.visible = [1, 2]
        manager.shown = ["left": "1", "right": "1"]
        manager.displayOf = [1: "left", 2: "right"]
        #expect(manager.tiled(on: screen("left")) == [1])
        #expect(manager.tiled(on: screen("right")) == [2])
        manager.desktops.nativeCatalog.sharedSpaces = false
        #expect(manager.tiled(on: screen("left")) == [1, 2])
    }
}
