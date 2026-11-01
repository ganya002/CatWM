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

    @Test func closingAWindowGivesItsSlotBack() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager()
        let kept = fake.addWindow(), closed = fake.addWindow(pid: -101)
        await fake.settle(manager)
        #expect(fake.frame(of: kept).width < screen.visible.width)
        fake.close(closed)
        await fake.settle(manager)
        #expect(manager.windows[closed] == nil)
        #expect(fake.frame(of: kept) == screen.visible)
    }

    @Test func disconnectingADisplayKeepsItsTabsTogether() async {
        let fake = FakeBackend()
        let remaining = fake.addScreen()
        let removed = fake.addScreen(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        let manager = fake.makeManager()
        let first = fake.addWindow(frame: removed.visible)
        let second = fake.addWindow(frame: removed.visible)
        #expect(await fake.settle(manager))
        manager.joinTab(second, onto: first)
        #expect(await fake.settle(manager))
        #expect(manager.tabs.group(of: first)?.members == [first, second])

        fake.removeScreen(removed)
        #expect(await fake.settle(manager))

        #expect(manager.workspaceOf[first] == manager.shown[remaining.uuid])
        #expect(manager.workspaceOf[second] == manager.shown[remaining.uuid])
        #expect(manager.tabs.group(of: first)?.members == [first, second])
        #expect(manager.tabs.group(of: first)?.active == second)
        #expect(fake.frame(of: second) == manager.belowTabStrip(remaining.visible, for: second))
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
        fake.addWindow()
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
        #expect(fake.frame(of: other).width == screen.visible.width - 1000)
        expectTiles([fake.frame(of: wide), fake.frame(of: other)], fill: screen.visible)
    }

    @Test func aMinimumSizePreservesAsMuchOfTheRequestedSplitAsPossible() async {
        let fake = FakeBackend()
        let screen = fake.addScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let manager = fake.makeManager()
        let stack = fake.addWindow(pid: -101, minSize: CGSize(width: 300, height: 0)), main = fake.addWindow()
        #expect(await fake.settle(manager))
        manager.dispatch("splitratio", "exact 0.8")
        #expect(await fake.wait(manager) { manager.minSizes[stack] != nil })
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: main) == CGRect(x: 0, y: 0, width: 700, height: 600))
        #expect(fake.frame(of: stack) == CGRect(x: 700, y: 0, width: 300, height: 600))
        expectTiles([fake.frame(of: main), fake.frame(of: stack)], fill: screen.visible)
    }

    @Test func aTallMinimumPushesTheOtherRowInTheWideLayout() async {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let manager = fake.makeManager { $0.layouts = [.wide] }
        let tall = fake.addWindow(minSize: CGSize(width: 0, height: 600))
        let ids = [tall, fake.addWindow(pid: -101), fake.addWindow(pid: -102)]
        await fake.settle(manager)
        #expect(await fake.wait(manager) { manager.minSizes[tall] != nil })
        await fake.settle(manager)
        #expect(fake.frame(of: tall).height == 600)
        expectTiles(ids.map(fake.frame(of:)), fill: screen.visible)
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
        expectTiles(ids.map(fake.frame(of:)), fill: screen.visible)
        let before = ids.map(fake.frame(of:))
        let start = CACurrentMediaTime()
        manager.setLayout(.wide, on: screen)
        let elapsed = CACurrentMediaTime() - start
        await fake.settle(manager)
        #expect(ids.map(fake.frame(of:)) != before)
        expectTiles(ids.map(fake.frame(of:)), fill: screen.visible)
        #expect(elapsed < 0.05, "The main thread took \(elapsed) s to tile 200 windows again")
    }
}
