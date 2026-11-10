import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite @MainActor struct WindowResizabilityTests {
    @Test func aWindowThatBecomesResizableJoinsTheLayout() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let changing = fake.addWindow(resizable: false)
        let other = fake.addWindow(pid: -101)
        #expect(await fake.settle(manager))
        #expect(try #require(manager.windows[changing]).isFloating)
        #expect(fake.frame(of: other) == screen.visible)

        fake.setResizable(changing, true)
        #expect(await fake.settle(manager))
        #expect(try !#require(manager.windows[changing]).isFloating)
        #expect(fake.frame(of: changing).width == screen.visible.width / 2)
        #expect(fake.frame(of: other).width == screen.visible.width / 2)
        #expect(!fake.frame(of: changing).intersects(fake.frame(of: other)))

        fake.setResizable(changing, false)
        #expect(await fake.settle(manager))
        #expect(try #require(manager.windows[changing]).isFloating)
        #expect(fake.frame(of: other) == screen.visible)
    }

    @Test func aResizabilityChangePreservesTheUsersFloatingChoice() async throws {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        let id = fake.addWindow(resizable: false)
        #expect(await fake.settle(manager))
        let window = try #require(manager.windows[id])
        window.userFloating = .chosen(true)
        fake.setResizable(id, true)
        #expect(await fake.settle(manager))
        #expect(!window.autoFloating)
        #expect(window.isFloating)
    }
}
