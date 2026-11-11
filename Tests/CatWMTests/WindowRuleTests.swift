import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct WindowRuleTests {
    private let visible = CGRect(x: 10, y: 40, width: 1400, height: 850)
    private let app = "test.rule.app"

    private struct World {
        let fake: FakeBackend
        let manager: WindowManager
        let folder: ConfigFolder
        let store: ConfigStore
    }

    private func script(_ lines: String...) -> String {
        catwmConfig([
            "catwm.workspaces.virtual = false", "catwm.motion.enabled = false",
            "catwm.focus.mouseFollowsFocus = false", "catwm.focus.followsMouse = false",
            "catwm.gaps.enabled = false", "catwm.padding = 0"
        ].joined(separator: "\n") + "\n" + lines.joined(separator: "\n"))
    }

    private func makeWorld(_ lines: String...) throws -> World {
        let fake = FakeBackend()
        fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: visible)
        let folder = try ConfigFolder(["catwm.config.ts": script(lines.joined(separator: "\n"))])
        let defaults = try #require(UserDefaults(suiteName: "catwm-rules-" + UUID().uuidString))
        let store = ConfigStore(folder: folder.url, defaults: defaults)
        let config = store.load()
        #expect(store.failures.isEmpty)
        let manager = fake.makeManager { $0 = config }
        manager.store = store
        return World(fake: fake, manager: manager, folder: folder, store: store)
    }

    private func save(_ world: World, _ lines: String...) throws {
        try world.folder.write("catwm.config.ts", script(lines.joined(separator: "\n")))
        world.manager.reload()
        #expect(world.store.failures.isEmpty)
    }

    private func focus(_ id: CGWindowID, in world: World) async throws {
        world.fake.userFocuses(id)
        world.manager.handle(kAXFocusedWindowChangedNotification, try #require(world.fake.element(id)))
        #expect(await world.fake.wait(world.manager) { world.manager.focusRequests.reportedFocus?.id == id })
    }

    private func press(_ index: Int, in world: World) throws {
        let functions = world.manager.config.bindings.filter { $0.function != nil }
        world.manager.run(try #require(functions[index]))
    }

    private func centered(_ size: CGSize) -> CGRect {
        CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
               width: size.width, height: size.height)
    }

    @Test func aKeyFunctionRunsItsActionsInOrder() async throws {
        let world = try makeWorld(
            "catwm.bind([\"alt\"], \"c\", () => {",
            "  const win = catwm.window.focused",
            "  win.float()",
            "  win.resize(500, 300)",
            "  win.center()",
            "})")
        let id = world.fake.addWindow(bundleID: app)
        #expect(await world.fake.settle(world.manager))
        try await focus(id, in: world)

        try press(0, in: world)

        let window = try #require(world.manager.windows[id])
        #expect(await world.fake.wait(world.manager) {
            window.isFloating && world.fake.frame(of: id) == self.centered(CGSize(width: 500, height: 300))
        })
    }

    @Test func aRuleAddedByASaveRunsOnWindowsAlreadyOpen() async throws {
        let world = try makeWorld()
        let id = world.fake.addWindow(bundleID: app)
        #expect(await world.fake.settle(world.manager))

        try save(world, "catwm.windows({ app: \"\(app)\" }, (win) => {",
                 "  win.float()", "  win.size = { width: 600, height: 400 }", "  win.position = \"center\"", "})")

        #expect(await world.fake.wait(world.manager) {
            world.fake.frame(of: id) == self.centered(CGSize(width: 600, height: 400))
        })
    }

    @Test func aKeyFunctionActsOnTheWindowFocusedAtThePress() async throws {
        let world = try makeWorld("catwm.bind([\"alt\"], \"c\", () => { catwm.window.focused.float() })")
        let pressed = world.fake.addWindow(bundleID: app)
        let other = world.fake.addWindow(pid: -101, bundleID: "test.other.app")
        #expect(await world.fake.settle(world.manager))
        try await focus(pressed, in: world)

        try press(0, in: world)
        try await focus(other, in: world)

        #expect(await world.fake.wait(world.manager) { world.manager.windows[pressed]?.isFloating == true })
        #expect(world.manager.windows[other]?.isFloating == false)
    }

    @Test func aThrowingKeyFunctionRunsNoActions() async throws {
        let world = try makeWorld(
            "catwm.bind([\"alt\"], \"c\", () => {",
            "  catwm.window.focused.float()",
            "  throw new Error(\"boom\")",
            "})",
            "catwm.bind([\"alt\"], \"d\", () => {})")
        let id = world.fake.addWindow(bundleID: app)
        #expect(await world.fake.settle(world.manager))
        try await focus(id, in: world)
        let window = try #require(world.manager.windows[id])

        try press(0, in: world)
        await withCheckedContinuation { done in
            let window = ConfigEngine.WindowSnapshot(title: "", app: "", pid: 0, frame: .zero)
            world.store.call(function: 1, window: window) { _ in done.resume() }
        }
        #expect(await world.fake.settle(world.manager))

        #expect(!window.isFloating)
        #expect(window.userFloating == .automatic)
    }

    @Test func aRuleFloatsSizesAndCentersANewWindow() async throws {
        let world = try makeWorld(
            "catwm.windows({ app: \"\(app)\" }, (win) => {",
            "  win.float()",
            "  win.size = { width: 500, height: 300 }",
            "  win.position = \"center\"",
            "})")
        let other = world.fake.addWindow(pid: -101, bundleID: "test.other.app")
        #expect(await world.fake.settle(world.manager))
        let id = world.fake.addWindow(bundleID: app)
        #expect(await world.fake.settle(world.manager))

        let window = try #require(world.manager.windows[id])
        #expect(window.isFloating)
        #expect(world.fake.frame(of: id) == centered(CGSize(width: 500, height: 300)))
        #expect(try #require(world.manager.windows[other]).isFloating == false)
    }

    @Test func aRuleAppliesToItsWindowNotTheFocusedOne() async throws {
        let world = try makeWorld("catwm.windows({ app: \"\(app)\" }, (win) => { win.float() })")
        let focused = world.fake.addWindow(pid: -101, bundleID: "test.other.app")
        #expect(await world.fake.settle(world.manager))
        try await focus(focused, in: world)
        let id = world.fake.addWindow(bundleID: app)
        world.fake.userFocuses(focused)
        #expect(await world.fake.settle(world.manager))

        #expect(try #require(world.manager.windows[id]).isFloating)
        #expect(!(try #require(world.manager.windows[focused]).isFloating))
    }

    @Test func aTitleChangeStartsARuleAndTheLaterRuleWins() async throws {
        let world = try makeWorld(
            "catwm.windows({ app: \"\(app)\", title: /Settings/ }, (win) => { win.float() })",
            "catwm.windows({ app: \"\(app)\", title: /Settings/ }, (win) => { win.tile() })",
            "catwm.windows({ app: \"\(app)\", title: /Prefs/ }, (win) => { win.float() })")
        let id = world.fake.addWindow(bundleID: app, title: "Plain")
        #expect(await world.fake.settle(world.manager))
        let window = try #require(world.manager.windows[id])
        #expect(!window.isFloating)

        world.fake.setTitle(id, "Settings")
        #expect(await world.fake.settle(world.manager))
        #expect(!window.isFloating)
        #expect(window.userFloating == .chosen(false))

        world.fake.setTitle(id, "Prefs")
        #expect(await world.fake.settle(world.manager))
        #expect(window.isFloating)
    }

    @Test func aRuleDoesNotSnapTheWindowBack() async throws {
        let world = try makeWorld(
            "catwm.windows({ app: \"\(app)\", title: /Settings/ }, (win) => {",
            "  win.float()",
            "  win.position = \"center\"",
            "})")
        let id = world.fake.addWindow(bundleID: app, title: "Settings")
        #expect(await world.fake.settle(world.manager))
        let size = world.fake.frame(of: id).size
        let ruled = centered(size)
        #expect(world.fake.frame(of: id) == ruled)
        try await Task.sleep(for: .milliseconds(250)) // style-ok: outlast Animator.verify, which no event reports

        let moved = CGRect(x: 100, y: 120, width: size.width, height: size.height)
        world.fake.userMoves(id, to: moved)
        world.fake.setTitle(id, "Settings 2")
        #expect(await world.fake.settle(world.manager))
        #expect(world.fake.frame(of: id) == moved)

        world.fake.setTitle(id, "Other")
        #expect(await world.fake.settle(world.manager))
        world.fake.setTitle(id, "Settings")
        #expect(await world.fake.settle(world.manager))
        #expect(world.fake.frame(of: id) == ruled)
    }

    @Test func theLatestOfToggleRuleAndSaveDecidesFloating() async throws {
        let world = try makeWorld(
            "catwm.floating.apps.push(\"\(app)\")",
            "catwm.windows({ app: \"\(app)\", title: /Pinned/ }, (win) => { win.float() })")
        let id = world.fake.addWindow(bundleID: app, title: "Plain")
        #expect(await world.fake.settle(world.manager))
        let window = try #require(world.manager.windows[id])
        #expect(window.isFloating)

        try await focus(id, in: world)
        world.manager.dispatch("togglefloating", "")
        #expect(await world.fake.settle(world.manager))
        #expect(!window.isFloating)

        try save(world, "catwm.floating.apps.push(\"\(app)\")", "catwm.gaps.size = 7",
                 "catwm.windows({ app: \"\(app)\", title: /Pinned/ }, (win) => { win.float() })")
        #expect(await world.fake.settle(world.manager))
        #expect(!window.isFloating)

        try save(world, "catwm.windows({ app: \"\(app)\", title: /Pinned/ }, (win) => { win.float() })")
        #expect(await world.fake.settle(world.manager))
        #expect(!window.isFloating)

        try save(world, "catwm.floating.apps.push(\"\(app)\")",
                 "catwm.windows({ app: \"\(app)\", title: /Pinned/ }, (win) => { win.float() })")
        #expect(await world.fake.settle(world.manager))
        #expect(window.isFloating)

        world.manager.dispatch("togglefloating", "")
        #expect(await world.fake.settle(world.manager))
        #expect(!window.isFloating)
        world.fake.setTitle(id, "Pinned")
        #expect(await world.fake.settle(world.manager))
        #expect(window.isFloating)
    }

    @Test func aSaveThatChangesARuleResultSetsFloating() async throws {
        let world = try makeWorld()
        let id = world.fake.addWindow(bundleID: app)
        #expect(await world.fake.settle(world.manager))
        let window = try #require(world.manager.windows[id])
        try await focus(id, in: world)
        world.manager.dispatch("togglefloating", "")
        world.manager.dispatch("togglefloating", "")
        #expect(await world.fake.settle(world.manager))
        #expect(!window.isFloating)

        try save(world, "catwm.windows({ app: \"\(app)\" }, (win) => { win.float() })")
        #expect(await world.fake.settle(world.manager))
        #expect(window.isFloating)

        try save(world, "catwm.windows({ app: \"\(app)\" }, (win) => { win.size = { width: 400, height: 300 } })")
        #expect(await world.fake.settle(world.manager))
        #expect(!window.isFloating)
    }
}
