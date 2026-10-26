import CoreGraphics
@testable import MinimalCatCore
import Testing

@MainActor
struct EngineTests {
    let start = CGRect(x: 200, y: 200, width: 600, height: 400)

    @Test func movesTheFocusedWindowToAPlace() {
        let system = FakeSystem(windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.left))
        #expect(system.frame(1) == Geometry.frame(for: .left, on: FakeSystem.laptop))
    }

    @Test func leftAgainMovesToTheNeighbouringDisplay() {
        let system = FakeSystem(screens: [FakeSystem.laptop, FakeSystem.monitor],
                                windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.right))
        _ = engine.perform(.place(.right))
        #expect(system.frame(1) == Geometry.frame(for: .left, on: FakeSystem.monitor))
        _ = engine.perform(.place(.left))
        #expect(system.frame(1) == Geometry.frame(for: .right, on: FakeSystem.laptop))
    }

    @Test func leftAtTheLastDisplayDoesNothing() {
        let system = FakeSystem(windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.left))
        #expect(engine.perform(.place(.left)) == .none)
        #expect(engine.history.undoSteps.count == 1)
    }

    @Test func bigAgainPutsTheWindowBack() {
        let system = FakeSystem(windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.big))
        #expect(system.frame(1) == Geometry.frame(for: .big, on: FakeSystem.laptop))
        _ = engine.perform(.place(.big))
        #expect(system.frame(1) == start)
    }

    @Test func undoAndRedoWalkTheSteps() {
        let system = FakeSystem(windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.left))
        _ = engine.perform(.place(.top))
        #expect(engine.perform(.undo) == .notice("Undid Move Up", visible: true))
        #expect(system.frame(1) == Geometry.frame(for: .left, on: FakeSystem.laptop))
        _ = engine.perform(.undo)
        #expect(system.frame(1) == start)
        #expect(engine.perform(.undo) == .notice("Nothing to undo", visible: true))
        _ = engine.perform(.redo)
        #expect(system.frame(1) == Geometry.frame(for: .left, on: FakeSystem.laptop))
    }

    @Test func undoWaitsForTheSameMonitors() {
        let system = FakeSystem(screens: [FakeSystem.laptop, FakeSystem.monitor],
                                windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.left))
        system.screens = [FakeSystem.laptop]
        #expect(engine.perform(.undo) == .notice("That change was on other monitors", visible: true))
        system.screens = [FakeSystem.laptop, FakeSystem.monitor]
        _ = engine.perform(.undo)
        #expect(system.frame(1) == start)
    }

    @Test func focusMovesToTheWindowOnThatSide() {
        let system = FakeSystem(windows: [
            FakeSystem.window(1, "Safari", CGRect(x: 800, y: 100, width: 500, height: 500)),
            FakeSystem.window(2, "Notes", CGRect(x: 10, y: 100, width: 500, height: 500))
        ])
        let engine = Engine(system: system)
        _ = engine.perform(.focus(.left))
        #expect(system.focus == WindowID(2))
        #expect(engine.perform(.focus(.left)) == .none)
    }

    @Test func tapGoesBackToTheLastWindow() {
        let system = FakeSystem(windows: [FakeSystem.window(1, "Safari", start), FakeSystem.window(2, "Mail", start)])
        let engine = Engine(system: system)
        engine.focused(WindowID(1))
        engine.focused(WindowID(2))
        system.focus = WindowID(2)
        _ = engine.previousWindow()
        #expect(system.focus == WindowID(1))
    }

    @Test func numbersStayWhenAWindowCloses() {
        let system = FakeSystem(windows: [FakeSystem.window(1, "A", start), FakeSystem.window(2, "B", start),
                                          FakeSystem.window(3, "C", start)])
        let engine = Engine(system: system)
        engine.windows()
        system.list.remove(at: 0)
        engine.windows()
        #expect(engine.slots.window(1) == nil)
        #expect(engine.slots.window(3) == WindowID(3))
        system.list.append(FakeSystem.window(4, "D", start))
        engine.windows()
        #expect(engine.slots.window(1) == WindowID(4))
        _ = engine.perform(.jump(3))
        #expect(system.focus == WindowID(3))
    }

    @Test func restorePutsWindowsBackAfterAMonitorReturns() {
        let system = FakeSystem(screens: [FakeSystem.laptop, FakeSystem.monitor],
                                windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.right))
        _ = engine.perform(.place(.right))
        let onMonitor = Geometry.frame(for: .left, on: FakeSystem.monitor)
        system.screens = [FakeSystem.laptop]
        system.list[0].frame = start
        engine.saveLayout()
        system.screens = [FakeSystem.laptop, FakeSystem.monitor]
        #expect(engine.restoreLayout() == .notice("Put 1 window back · ⇪ Z undoes", visible: true))
        #expect(system.frame(1) == onMonitor)
        _ = engine.perform(.undo)
        #expect(system.frame(1) == start)
    }

    @Test func closedWindowsLeaveTheHistory() {
        let system = FakeSystem(windows: [FakeSystem.window(1, "Safari", start)])
        let engine = Engine(system: system)
        _ = engine.perform(.place(.left))
        engine.windowClosed(WindowID(1))
        #expect(engine.perform(.undo) == .notice("Nothing to undo", visible: true))
    }
}
