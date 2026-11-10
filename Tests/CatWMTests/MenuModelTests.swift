import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct MenuModelTests {
    @Test @MainActor func keyboardMoveCancelsPendingHoverSubmenu() throws {
        let model = MenuModel()
        let layout = MenuItem(id: "layout", kind: .sub, label: "Layout", children: [
            MenuItem(id: "next-layout", label: "Next Layout")
        ])
        model.items = [layout, MenuItem(id: "settings", label: "Settings…")]

        model.hover(layout, level: 0)
        let pendingOpen = try #require(model.openWork)
        defer { pendingOpen.cancel() }
        model.move(1)
        pendingOpen.perform()

        #expect(model.highlight[0] == "settings")
        #expect(model.path.isEmpty)
    }

    @Test @MainActor func hoverStillOpensSubmenuWithoutKeyboardInput() throws {
        let model = MenuModel()
        let layout = MenuItem(id: "layout", kind: .sub, label: "Layout", children: [
            MenuItem(id: "next-layout", label: "Next Layout")
        ])
        model.items = [layout]

        model.hover(layout, level: 0)
        let pendingOpen = try #require(model.openWork)
        defer { pendingOpen.cancel() }
        pendingOpen.perform()

        #expect(model.path == ["layout"])
    }

    @Test @MainActor func keyboardReopenCancelsPendingHoverTrim() throws {
        let model = MenuModel()
        let layout = MenuItem(id: "layout", kind: .sub, label: "Layout", children: [
            MenuItem(id: "next-layout", label: "Next Layout")
        ])
        let settings = MenuItem(id: "settings", label: "Settings…")
        model.items = [layout, settings]
        model.path = ["layout"]

        model.hover(settings, level: 0)
        let pendingTrim = try #require(model.trimWork)
        defer { pendingTrim.cancel() }
        model.move(-1)
        model.openHighlighted()
        pendingTrim.perform()

        #expect(model.path == ["layout"])
        #expect(model.highlight[1] == "next-layout")
    }
}
