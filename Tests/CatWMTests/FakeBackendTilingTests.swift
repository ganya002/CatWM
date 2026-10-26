import AppKit
@testable import CatWM
import QuartzCore
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct FakeBackendTilingTests {
    private func expectTiles(_ frames: [CGRect], fill visible: CGRect) {
        for (index, frame) in frames.enumerated() {
            #expect(visible.contains(frame))
            for other in frames[(index + 1)...] {
                let overlap = frame.intersection(other)
                #expect(overlap.isEmpty)
            }
        }
        #expect(frames.reduce(0) { $0 + $1.width * $1.height } == visible.width * visible.height)
    }

    @Test func twoWindowsSplitTheScreen() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let first = fake.addWindow(), second = fake.addWindow()
        await fake.settle(manager)
        let frames = [fake.frame(of: first), fake.frame(of: second)]
        expectTiles(frames, fill: screen.visible)
        #expect(frames[0].width == screen.visible.width / 2)
        #expect(await fake.wait(manager) { fake.cursorRefreshes > 0 })
    }

    @Test func closingAWindowCentersTheOneLeft() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let kept = fake.addWindow(), closed = fake.addWindow(pid: -101)
        await fake.settle(manager)
        #expect(fake.frame(of: kept).width == screen.visible.width / 2)
        fake.close(closed)
        await fake.settle(manager)
        #expect(manager.windows[closed] == nil)
        #expect(fake.frame(of: kept).width == screen.visible.width / 2)
        #expect(fake.frame(of: kept).midX == screen.visible.midX)
    }

    @Test func aColumnOffTheScreenParksAndComesBackWhenFocused() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let ids = [fake.addWindow(), fake.addWindow(pid: -101), fake.addWindow(pid: -102)]
        await fake.settle(manager)
        let strip = manager.state(for: screen).strip
        #expect(strip.columns.count == 3)
        let shown = ids.filter { screen.visible.intersection(fake.frame(of: $0)).width > 2 }
        let parked = try #require(ids.first { !shown.contains($0) })
        #expect(shown.count == 2)
        #expect(screen.frame.intersection(fake.frame(of: parked)).width <= 1)
        let clamped = fake.frame(of: parked).offsetBy(dx: 0, dy: -30)
        fake.clearWrites()
        for _ in 0..<3 {
            fake.userMoves(parked, to: clamped)
            manager.refresh()
            await fake.settle(manager)
        }
        let moved = fake.writes.filter {
            if case .position(parked, _) = $0 { return true }
            return false
        }
        #expect(moved.count <= 1)
        let window = try #require(manager.windows[parked])
        fake.userFocuses(parked)
        manager.focus(window, warp: false)
        await fake.settle(manager)
        #expect(screen.visible.contains(fake.frame(of: parked)))
        let corner = CGPoint(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1)
        let exited = try #require(strip.columns.first?.ids.first)
        #expect(await fake.wait(manager) { fake.frame(of: exited).origin == corner })
        let first = try #require(manager.windows[exited])
        fake.userFocuses(exited)
        manager.focus(first, warp: false)
        #expect(await fake.wait(manager) { fake.frame(of: parked).origin == corner })
    }

    @Test func aNewWindowThatTakesTheFocusScrollsIntoView() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        _ = fake.addWindow()
        _ = fake.addWindow(pid: -101)
        await fake.settle(manager)
        let new = fake.addWindow(pid: -102)
        fake.userFocuses(new)
        manager.acceptFocus(pid: -102, id: new)
        await fake.settle(manager)
        #expect(manager.state(for: screen).strip.ids.last == new)
        #expect(screen.visible.contains(fake.frame(of: new)))
    }

    @Test func columnWidthCycleWidensTheFocusedColumn() async throws {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let id = fake.addWindow()
        await fake.settle(manager)
        let window = try #require(manager.windows[id])
        fake.userFocuses(id)
        manager.focus(window, warp: false)
        #expect(await fake.wait(manager) { manager.focusedWindow()?.id == id })
        manager.dispatch("columnwidth", "cycle")
        await fake.settle(manager)
        let wide = try #require(manager.config.columnWidths.last)
        #expect(manager.state(for: screen).strip.columns.map(\.width) == [wide])
        #expect(abs(fake.frame(of: id).width - screen.visible.width * wide) <= 1)
    }

    @Test func moveFocusRightFocusesTheNeighbourAndWritesNoFrame() async {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        let pid: pid_t = -100
        let ids = [fake.addWindow(pid: pid), fake.addWindow(pid: pid)]
        await fake.settle(manager)
        let sorted = ids.sorted { fake.frame(of: $0).minX < fake.frame(of: $1).minX }
        let (left, right) = (sorted[0], sorted[1])
        fake.userFocuses(left)
        if let element = fake.element(left) { manager.handle(kAXFocusedWindowChangedNotification, element) }
        #expect(await fake.wait(manager) { manager.focusRequests.reportedFocus?.id == left })
        fake.clearWrites()
        let cursorRefreshes = fake.cursorRefreshes
        manager.dispatch("movefocus", "r")
        #expect(await fake.wait(manager) { manager.focusRequests.reportedFocus?.id == right })
        #expect(fake.focused(in: pid) == right)
        #expect(fake.frontmost == pid)
        #expect(fake.writes.isEmpty)
        #expect(await fake.wait(manager) { fake.cursorRefreshes > cursorRefreshes })
    }

    @Test func aWaitForAnEventThatNeverComesEnds() async {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        #expect(await !fake.wait(manager, timeout: 0.05) { false })
        #expect(manager.onChange == nil)
        let waiting = Task { @MainActor in await fake.wait(manager, timeout: 600) { false } }
        waiting.cancel()
        #expect(await !waiting.value)
        #expect(manager.onChange == nil)
    }

    @Test func aSettleOnAReadThatNeverReturnsEnds() async {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        _ = fake.addWindow()
        let gate = fake.holdScans()
        defer { gate.signal() }
        #expect(await !fake.settle(manager, timeout: 0.2))
        #expect(manager.scanWaiters.isEmpty)
        let settling = Task { @MainActor in await fake.settle(manager, timeout: 600) }
        settling.cancel()
        #expect(await !settling.value)
        #expect(manager.scanWaiters.isEmpty)
    }

    @Test func aMinimumSizePushesTheNeighbour() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let wide = fake.addWindow(minSize: CGSize(width: 1000, height: 0)), other = fake.addWindow(pid: -101)
        await fake.settle(manager)
        #expect(await fake.wait(manager) { manager.minSizes[wide] != nil })
        await fake.settle(manager)
        #expect(manager.minSizes[wide]?.width == 1000)
        #expect(fake.frame(of: wide).width == 1000)
        #expect(!fake.frame(of: wide).intersects(fake.frame(of: other)))
    }

    @Test func aUserDragIsTiledAgain() async {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        let dragged = fake.addWindow(), other = fake.addWindow(pid: -101)
        await fake.settle(manager)
        let slot = fake.frame(of: dragged), otherSlot = fake.frame(of: other)
        fake.clearWrites()
        fake.userMoves(dragged, to: slot.offsetBy(dx: 140, dy: 90))
        await fake.settle(manager)
        #expect(fake.frame(of: dragged) == slot)
        #expect(fake.frame(of: other) == otherSlot)
        #expect(fake.writes.contains { $0.id == dragged })
        #expect(!fake.writes.contains { $0.id == other })
    }

    @Test func twoHundredWindowsRetileInLessThan50Milliseconds() async {
        let fake = FakeBackend()
        let screen = fake.addScreen(frame: CGRect(x: 0, y: 0, width: 6000, height: 4000))
        let manager = fake.makeManager()
        let ids = (0..<200).map { fake.addWindow(pid: -100 - pid_t($0 % 20)) }
        await fake.settle(manager)
        #expect(Set(manager.windows.keys) == Set(ids))
        let before = ids.map(fake.frame(of:))
        let state = manager.state(for: screen)
        for index in state.strip.columns.indices { state.strip.columns[index].width = 1.0 / 3 }
        let start = CACurrentMediaTime()
        manager.refresh()
        let elapsed = CACurrentMediaTime() - start
        await fake.settle(manager)
        #expect(ids.map(fake.frame(of:)) != before)
        let shown = ids.map(fake.frame(of:)).filter { screen.visible.intersection($0).width > 2 }
        expectTiles(shown, fill: screen.visible)
        #expect(elapsed < 0.05, "The main thread took \(elapsed) s to tile 200 windows again")
    }
}
