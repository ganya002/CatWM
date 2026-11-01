import AppKit
@testable import CatWM
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct DailyWindowCommandTests {
    private func focus(_ id: CGWindowID, in fake: FakeBackend, manager: WindowManager) async throws {
        fake.userFocuses(id)
        let element = try #require(fake.element(id))
        manager.handle(kAXFocusedWindowChangedNotification, element)
        #expect(await fake.wait(manager) { manager.focusRequests.reportedFocus?.id == id })
    }

    @Test(arguments: Layout.allCases, [1, 2, 3, 5])
    func dailyCommands(layout: Layout, count: Int) async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { $0.layouts = [layout, .tall == layout ? .wide : .tall] }
        for _ in 0..<count { fake.addWindow() }
        #expect(await fake.settle(manager))
        let ids = manager.tiled(on: screen)
        let first = try #require(ids.first)
        try await focus(first, in: fake, manager: manager)
        let original = ids.map(fake.frame(of:))
        manager.dispatch("splitratio", "exact 0.6")
        #expect(await fake.settle(manager))
        #expect(abs(manager.state(for: screen).ratio - 0.6) < 0.001)
        if layout.hasMainPane, count > 1 {
            let extent = layout == .wide ? fake.frame(of: first).height : fake.frame(of: first).width
            let expected = (layout == .wide ? screen.visible.height : screen.visible.width) * 0.6
            #expect(abs(extent - expected) < 1)
        }
        manager.dispatch("splitratio", "exact 0.5")
        #expect(await fake.settle(manager))
        #expect(ids.map(fake.frame(of:)) == original)

        for direction in Direction.allCases {
            try await focus(first, in: fake, manager: manager)
            manager.dispatch("movefocus", direction.rawValue)
            #expect(await fake.settle(manager))
            let neighbour = try #require(manager.focusedWindow()?.id)
            #expect(ids.contains(neighbour))
            #expect(ids.map(fake.frame(of:)) == original)
            for command in ["movewindow", "swapwindow"] {
                try await focus(first, in: fake, manager: manager)
                let order = manager.order
                manager.dispatch(command, direction.rawValue)
                #expect(await fake.settle(manager))
                var expected = order
                let from = try #require(expected.firstIndex(of: first))
                let into = try #require(expected.firstIndex(of: neighbour))
                expected.swapAt(from, into)
                #expect(manager.order == expected)
                #expect(manager.focusedWindow()?.id == first)
                manager.order = order
                manager.refresh()
                #expect(await fake.settle(manager))
            }
        }
    }

    @Test(arguments: Layout.allCases, [1, 2, 3, 5])
    func layoutAndWindowState(layout: Layout, count: Int) async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { $0.layouts = [layout, .tall == layout ? .wide : .tall] }
        for _ in 0..<count { fake.addWindow() }
        #expect(await fake.settle(manager))
        let ids = manager.tiled(on: screen)
        let first = try #require(ids.first)
        try await focus(first, in: fake, manager: manager)
        manager.dispatch("swapnext", "")
        #expect(await fake.settle(manager))
        manager.dispatch("swapnext", "prev")
        #expect(await fake.settle(manager))
        #expect(manager.tiled(on: screen) == ids)
        manager.dispatch("cyclelayout", "next")
        #expect(await fake.settle(manager))
        #expect(manager.state(for: screen).layout != layout)
        manager.dispatch("cyclelayout", "prev")
        #expect(await fake.settle(manager))
        #expect(manager.state(for: screen).layout == layout)
        manager.dispatch("togglefloating", "")
        #expect(await fake.settle(manager))
        #expect(manager.windows[first]?.isFloating == true)
        manager.dispatch("togglefloating", "")
        #expect(await fake.settle(manager))
        #expect(manager.windows[first]?.isFloating == false)
        let original = ids.map(fake.frame(of:))
        manager.dispatch("fullscreen", "")
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: first) == screen.visible)
        manager.dispatch("fullscreen", "")
        #expect(await fake.settle(manager))
        #expect(ids.map(fake.frame(of:)) == original)
    }

    @Test(arguments: Layout.allCases, [1, 2, 3, 5])
    func closeFocusedWindow(layout: Layout, count: Int) async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { $0.layouts = [layout] }
        let ids = (0..<count).map { _ in fake.addWindow() }
        #expect(await fake.settle(manager))
        let first = try #require(ids.first)
        try await focus(first, in: fake, manager: manager)
        manager.dispatch("killactive", "")
        #expect(await fake.settle(manager))
        #expect(fake.ids == Set(ids.dropFirst()))
        #expect(Set(manager.windows.keys) == fake.ids)
        for id in ids.dropFirst() { #expect(screen.visible.contains(fake.frame(of: id))) }
    }

    @Test(arguments: Layout.allCases.filter { $0 != .floating }, [1, 2, 3, 5])
    func swapWindowAcceptsDocumentedMonitorTarget(layout: Layout, count: Int) async throws {
        let fake = FakeBackend()
        let left = fake.addScreen()
        let right = fake.addScreen(frame: left.frame.offsetBy(dx: left.frame.width, dy: 0))
        let manager = fake.makeManager { $0.layouts = [layout] }
        for _ in 0..<count { fake.addWindow() }
        #expect(await fake.settle(manager))
        let first = try #require(manager.tiled(on: left).first)
        try await focus(first, in: fake, manager: manager)
        for target in ["mon:+1", "mon:r", "mon:1"] {
            manager.dispatch("swapwindow", target)
            #expect(await fake.settle(manager))
            #expect(right.visible.contains(fake.frame(of: first)))
            #expect(manager.tiled(on: right) == [first])
            #expect(manager.focusedWindow()?.id == first)
            manager.dispatch("movewindow", "mon:0")
            #expect(await fake.settle(manager))
            #expect(left.visible.contains(fake.frame(of: first)))
        }
    }
}
