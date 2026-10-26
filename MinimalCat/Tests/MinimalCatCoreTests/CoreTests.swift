import CoreGraphics
import Foundation
import Testing
@testable import MinimalCatCore

struct CatKeyTests {
    @Test func aQuickTapGoesBack() {
        var key = CatKey()
        #expect(key.handle(.down(at: 0)) == [])
        #expect(key.handle(.up(at: 0.1)) == [.previousWindow])
    }

    @Test func aHoldShowsTheOverlayAndReleaseHidesIt() {
        var key = CatKey()
        _ = key.handle(.down(at: 0))
        #expect(key.handle(.tick(at: 0.1)) == [])
        #expect(key.handle(.tick(at: 0.25)) == [.showOverlay])
        #expect(key.handle(.up(at: 0.4)) == [.hideOverlay])
    }

    @Test func aChordActsAtOnceAndIsNotATap() {
        var key = CatKey()
        _ = key.handle(.down(at: 0))
        #expect(key.handle(.key(123)) == [.act(123)])
        #expect(key.handle(.key(124)) == [.act(124)])
        #expect(key.handle(.tick(at: 0.5)) == [])
        #expect(key.handle(.up(at: 0.6)) == [])
    }

    @Test func keysPassThroughWhenTheCatKeyIsUp() {
        var key = CatKey()
        #expect(key.handle(.key(0)) == nil)
        _ = key.handle(.down(at: 0))
        _ = key.handle(.up(at: 0.1))
        #expect(key.handle(.key(6)) == nil)
    }

    @Test func aSlowReleaseWithNoTickDoesNothing() {
        var key = CatKey()
        _ = key.handle(.down(at: 0))
        #expect(key.handle(.up(at: 0.3)) == [])
    }
}

struct GeometryTests {
    @Test func halvesShareTheGap() {
        let left = Geometry.frame(for: .left, on: FakeSystem.laptop)
        let right = Geometry.frame(for: .right, on: FakeSystem.laptop)
        #expect(right.minX - left.maxX == Geometry.gap)
        #expect(left.width == right.width)
        #expect(left.minY == FakeSystem.laptop.visible.minY + Geometry.gap)
    }

    @Test func bigIsCentredOnAnUltrawide() {
        let big = Geometry.frame(for: .big, on: FakeSystem.ultrawide)
        #expect(abs(big.midX - FakeSystem.ultrawide.visible.midX) < 1)
        #expect(big.width < FakeSystem.ultrawide.visible.width * 0.6)
        #expect(Geometry.frame(for: .big, on: FakeSystem.laptop).width > FakeSystem.laptop.visible.width * 0.9)
    }

    @Test func fractionsSurviveAResolutionChange() {
        let frame = CGRect(x: 100, y: 133, width: 700, height: 500)
        let fraction = Geometry.fraction(of: frame, in: FakeSystem.laptop)
        #expect(Geometry.absolute(fraction, in: FakeSystem.laptop) == frame)
    }
}

struct HistoryTests {
    let displays = DisplaySet([FakeSystem.laptop])

    func step(_ id: UInt32) -> Step {
        Step(label: "Move", cause: .key, displays: displays,
             moves: [Move(window: WindowID(id), from: .zero, to: CGRect(x: 1, y: 1, width: 1, height: 1))])
    }

    @Test func keepsTheLastThirtySteps() {
        var history = History()
        for id in 1...40 { history.record(step(UInt32(id))) }
        #expect(history.undoSteps.count == 30)
        #expect(history.undoSteps.first?.moves.first?.window == WindowID(11))
    }

    @Test func aNewStepClearsRedo() {
        var history = History()
        history.record(step(1))
        _ = history.undo(on: displays)
        history.record(step(2))
        #expect(history.redo(on: displays) == .empty)
    }
}

struct DisplayMemoryTests {
    @Test func matchesByTitleWhenTheWindowIsNew() {
        var memory = DisplayMemory()
        let saved = FakeSystem.window(1, "Notes", CGRect(x: 10, y: 50, width: 400, height: 300), title: "Plan")
        memory.save([saved], on: [FakeSystem.laptop])
        let reopened = FakeSystem.window(9, "Notes", CGRect(x: 300, y: 300, width: 400, height: 300), title: "Plan")
        let moves = memory.restore([reopened], on: [FakeSystem.laptop])
        #expect(moves == [Move(window: WindowID(9), from: reopened.frame, to: saved.frame)])
    }

    @Test func doesNotMatchAReusedIDFromAnotherApp() {
        var memory = DisplayMemory()
        memory.save([FakeSystem.window(1, "Notes", CGRect(x: 10, y: 50, width: 400, height: 300))],
                    on: [FakeSystem.laptop])
        let other = WindowInfo(id: WindowID(1), pid: 3, app: "Mail", bundleID: "test.Mail", title: "",
                               frame: CGRect(x: 300, y: 300, width: 400, height: 300))
        #expect(memory.restore([other], on: [FakeSystem.laptop]).isEmpty)
    }

    @Test func eachSetupHasItsOwnLayout() {
        var memory = DisplayMemory()
        let window = FakeSystem.window(1, "Notes", CGRect(x: 10, y: 50, width: 400, height: 300))
        memory.save([window], on: [FakeSystem.laptop])
        #expect(memory.restore([window], on: [FakeSystem.laptop, FakeSystem.monitor]).isEmpty)
    }

    @Test func survivesEncoding() throws {
        var memory = DisplayMemory()
        memory.save([FakeSystem.window(1, "Notes", CGRect(x: 10, y: 50, width: 400, height: 300))],
                    on: [FakeSystem.laptop])
        let decoded = try JSONDecoder().decode(DisplayMemory.self, from: JSONEncoder().encode(memory))
        #expect(decoded == memory)
    }
}

struct FindTests {
    let windows = [
        FakeSystem.window(1, "Safari", .zero, title: "Apple Developer"),
        FakeSystem.window(2, "Notes", .zero, title: "Grocery list"),
        FakeSystem.window(3, "Visual Studio Code", .zero, title: "main.swift"),
        FakeSystem.window(4, "Mail", .zero, title: "Inbox – Përsonal")
    ]

    @Test func prefixBeatsSubstring() {
        #expect(Find.rank("no", windows).first?.id.raw == 2)
        #expect(Find.rank("s", windows).first?.id.raw == 1)
    }

    @Test func acronymAndFuzzyAndDiacritics() {
        #expect(Find.rank("vsc", windows).first?.id.raw == 3)
        #expect(Find.rank("grlst", windows).map(\.id.raw) == [2])
        #expect(Find.rank("personal", windows).map(\.id.raw) == [4])
    }

    @Test func emptyQueryKeepsTheOrder() {
        #expect(Find.rank("", windows).map(\.id.raw) == [1, 2, 3, 4])
    }
}
