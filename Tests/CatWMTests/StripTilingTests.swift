import AppKit
@testable import CatWM
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct StripTilingTests {
    @Test func turningTilingOffBringsParkedColumnsBack() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let ids = [fake.addWindow(), fake.addWindow(pid: -101), fake.addWindow(pid: -102)]
        await fake.settle(manager)
        #expect(ids.contains { screen.frame.intersection(fake.frame(of: $0)).width <= 1 })
        manager.toggleTiling()
        await fake.settle(manager)
        for id in ids { #expect(screen.visible.contains(fake.frame(of: id))) }
    }

    @Test func navigationUsesRealFramesWhenTilingIsOff() async throws {
        let fake = FakeBackend()
        _ = fake.addScreen()
        let manager = fake.makeManager()
        _ = fake.addWindow()
        _ = fake.addWindow(pid: -101)
        await fake.settle(manager)
        let order = manager.state(for: try #require(fake.screens().first)).strip.ids
        let left = try #require(manager.windows[order[0]]), right = try #require(manager.windows[order[1]])
        manager.toggleTiling()
        await fake.settle(manager)
        fake.userMoves(left.id, to: CGRect(x: 900, y: 0, width: 400, height: 400))
        fake.userMoves(right.id, to: CGRect(x: 0, y: 0, width: 400, height: 400))
        _ = left.frame
        _ = right.frame
        guard case let .window(hit)? = manager.resolve(.left, from: left, among: [right]) else {
            Issue.record("no window to the left")
            return
        }
        #expect(hit.id == right.id)
    }

    @Test func aTabJoinKeepsTheHostColumn() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        _ = fake.addWindow()
        _ = fake.addWindow(pid: -101)
        _ = fake.addWindow(pid: -102)
        await fake.settle(manager)
        let state = manager.state(for: screen)
        let order = state.strip.ids
        state.strip.columns[0].width = 1.0 / 3
        manager.joinTab(order[2], onto: order[0])
        await fake.settle(manager)
        #expect(state.strip.columns.map(\.ids).last == [order[1]])
        #expect(state.strip.columns.first?.width == 1.0 / 3)
    }

    @Test func minimumHeightsShareTheColumn() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        _ = fake.addWindow()
        _ = fake.addWindow(pid: -101)
        await fake.settle(manager)
        let state = manager.state(for: screen)
        let ids = state.strip.ids
        state.strip.columns = [Strip.Column(ids, width: 0.5)]
        manager.minSizes[ids[0]] = CGSize(width: 0, height: 600)
        manager.refresh()
        await fake.settle(manager)
        #expect(fake.frame(of: ids[0]).height >= 600)
        #expect(!fake.frame(of: ids[0]).intersects(fake.frame(of: ids[1])))
    }

    @Test func edgeSlidesStayOffTheNextDisplay() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let next = fake.addScreen(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        let manager = fake.makeManager()
        let ids = [fake.addWindow(), fake.addWindow(pid: -101), fake.addWindow(pid: -102)]
        await fake.settle(manager)
        manager.config.animate = true
        let parked = try #require(ids.first { screen.visible.intersection(fake.frame(of: $0)).width <= 2 })
        let window = try #require(manager.windows[parked])
        fake.clearWrites()
        fake.userFocuses(parked)
        manager.focus(window, warp: false)
        #expect(await fake.wait(manager) { screen.visible.contains(fake.frame(of: parked)) })
        await fake.settle(manager)
        let onNext = fake.writes.contains {
            guard case let .position(id, point) = $0 else { return false }
            return next.frame.intersects(CGRect(origin: point, size: fake.frame(of: id).size))
        }
        #expect(!onNext)
    }
}
