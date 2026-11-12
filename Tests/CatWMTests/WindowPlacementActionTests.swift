import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct WindowPlacementActionTests {
    private let visible = CGRect(x: 10, y: 40, width: 1400, height: 850)

    private struct World {
        let fake: FakeBackend
        let manager: WindowManager
        let ids: [CGWindowID]
    }

    private func makeWorld() async -> World {
        let fake = FakeBackend()
        fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: visible)
        let manager = fake.makeManager()
        let ids = (0..<2).map { _ in fake.addWindow() }
        #expect(await fake.settle(manager))
        return World(fake: fake, manager: manager, ids: ids)
    }

    private func focus(_ id: CGWindowID, in fake: FakeBackend, manager: WindowManager) async throws {
        fake.userFocuses(id)
        manager.handle(kAXFocusedWindowChangedNotification, try #require(fake.element(id)))
        #expect(await fake.wait(manager) { manager.focusRequests.reportedFocus?.id == id })
    }

    private func floatFocused(_ id: CGWindowID, in fake: FakeBackend, manager: WindowManager) async throws {
        try await focus(id, in: fake, manager: manager)
        manager.dispatch("setfloating", "")
        #expect(await fake.settle(manager))
    }

    @Test func setFloatingFloatsOnceAndSticks() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        let id = ids[0]
        try await focus(id, in: fake, manager: manager)
        let window = try #require(manager.windows[id])
        manager.dispatch("setfloating", "")
        #expect(await fake.settle(manager))
        #expect(window.isFloating)
        #expect(window.userFloating == .chosen(true))

        fake.clearWrites()
        manager.dispatch("setfloating", "")
        #expect(await fake.settle(manager))
        #expect(window.isFloating)
        #expect(fake.writes.isEmpty)
    }

    @Test func setTiledTilesOnceAndSticks() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        let id = ids[0]
        try await focus(id, in: fake, manager: manager)
        let window = try #require(manager.windows[id])
        manager.dispatch("settiled", "")
        #expect(await fake.settle(manager))
        #expect(!window.isFloating)
        #expect(window.userFloating == .automatic)

        manager.dispatch("setfloating", "")
        #expect(await fake.settle(manager))
        manager.dispatch("settiled", "")
        #expect(await fake.settle(manager))
        #expect(!window.isFloating)
        #expect(window.userFloating == .chosen(false))
        #expect(manager.tiled(on: try #require(fake.screens().first)).contains(id))

        fake.clearWrites()
        manager.dispatch("settiled", "")
        #expect(await fake.settle(manager))
        #expect(fake.writes.isEmpty)
    }

    @Test func resizeKeepsTopLeftOfFloatingWindow() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        let id = ids[0]
        try await floatFocused(id, in: fake, manager: manager)
        let origin = fake.frame(of: id).origin
        manager.dispatch("resizeactive", "exact 500 300")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: id) == CGRect(origin: origin, size: CGSize(width: 500, height: 300)))
    }

    @Test func resizeIgnoresTiledWindowsAndBadArguments() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        try await focus(ids[0], in: fake, manager: manager)
        let tiled = ids.map(fake.frame(of:))
        manager.dispatch("resizeactive", "exact 500 300")
        #expect(await fake.settle(manager))
        #expect(ids.map(fake.frame(of:)) == tiled)

        try await floatFocused(ids[0], in: fake, manager: manager)
        let floated = fake.frame(of: ids[0])
        for argument in ["", "exact", "exact 500", "exact 0 300", "exact -5 300", "exact a b", "exact 1 2 3", "10"] {
            manager.dispatch("resizeactive", argument)
            #expect(await fake.settle(manager))
            #expect(fake.frame(of: ids[0]) == floated, "argument: \(argument)")
        }
        manager.dispatch("resizeactive", "10 -20")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: ids[0]).size == CGSize(width: floated.width + 10, height: floated.height - 20))
    }

    @Test func resizeIgnoresWindowThatCannotResize() async throws {
        let fake = FakeBackend()
        fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: visible)
        let manager = fake.makeManager()
        let id = fake.addWindow(resizable: false)
        #expect(await fake.settle(manager))
        try await focus(id, in: fake, manager: manager)
        let before = fake.frame(of: id)
        manager.dispatch("resizeactive", "exact 500 300")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: id) == before)
    }

    @Test func moveIsRelativeToVisibleFrame() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        let id = ids[0]
        try await floatFocused(id, in: fake, manager: manager)
        manager.dispatch("resizeactive", "exact 400 300")
        manager.dispatch("moveactive", "exact 100 50")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: id) == CGRect(x: visible.minX + 100, y: visible.minY + 50, width: 400, height: 300))
    }

    @Test func moveKeepsWindowOnItsScreen() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        let id = ids[0]
        try await floatFocused(id, in: fake, manager: manager)
        let size = fake.frame(of: id).size
        manager.dispatch("moveactive", "exact 9000 -300")
        #expect(await fake.settle(manager))
        let corner = CGPoint(x: visible.maxX - size.width, y: visible.minY)
        #expect(fake.frame(of: id) == CGRect(origin: corner, size: size))
    }

    @Test func moveIgnoresTiledWindowsAndBadArguments() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        try await focus(ids[0], in: fake, manager: manager)
        let tiled = ids.map(fake.frame(of:))
        manager.dispatch("moveactive", "exact 100 50")
        manager.dispatch("centerwindow", "")
        #expect(await fake.settle(manager))
        #expect(ids.map(fake.frame(of:)) == tiled)

        try await floatFocused(ids[0], in: fake, manager: manager)
        let floated = fake.frame(of: ids[0])
        for argument in ["", "exact 100", "exact x y", "100 50", "exact 1 2 3"] {
            manager.dispatch("moveactive", argument)
            #expect(await fake.settle(manager))
            #expect(fake.frame(of: ids[0]) == floated, "argument: \(argument)")
        }
    }

    @Test func centerUsesVisibleFrame() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        let id = ids[0]
        try await floatFocused(id, in: fake, manager: manager)
        let size = fake.frame(of: id).size
        manager.dispatch("centerwindow", "")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: id) == CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                              width: size.width, height: size.height))
    }

    @Test func methodsActOnTheGivenWindowNotTheFocusedOne() async throws {
        let world = await makeWorld()
        let (fake, manager, ids) = (world.fake, world.manager, world.ids)
        try await focus(ids[1], in: fake, manager: manager)
        let other = try #require(manager.windows[ids[0]])
        manager.setFloating(true, for: other)
        manager.resizeWindow(other, to: CGSize(width: 400, height: 300))
        manager.moveWindow(other, toOffset: CGPoint(x: 20, y: 30))
        #expect(await fake.settle(manager))
        #expect(other.isFloating)
        #expect(fake.frame(of: ids[0]) == CGRect(x: visible.minX + 20, y: visible.minY + 30, width: 400, height: 300))
        manager.centerWindow(other)
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: ids[0]).midX == visible.midX)
        #expect(fake.frame(of: ids[0]).midY == visible.midY)
        #expect(manager.windows[ids[1]]?.isFloating == false)
    }

    @Test func floatingLayoutLetsATiledWindowMoveFreely() async throws {
        let fake = FakeBackend()
        fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: visible)
        let manager = fake.makeManager { $0.layouts = [.floating] }
        let id = fake.addWindow()
        #expect(await fake.settle(manager))
        try await focus(id, in: fake, manager: manager)
        manager.dispatch("moveactive", "exact 0 0")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: id).origin == visible.origin)
    }
}
