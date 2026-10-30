@testable import CatWM
import CoreGraphics
import Testing

typealias Item = MotionResolver.Item
typealias Display = MotionResolver.Display

private func tiled(
    _ layout: Layout,
    _ count: Int,
    screen: String = "A",
    in bounds: CGRect = CGRect(x: 0, y: 0, width: 1600, height: 1000),
    first: CGWindowID = 1
) -> [Item] {
    let frames = layout.frames(count: count, in: bounds.insetBy(dx: -5, dy: -5), ratio: 0.5, mainCount: 1) ?? []
    return frames.enumerated().map { i, frame in
        Item(id: first + CGWindowID(i), frame: frame.insetBy(dx: 5, dy: 5).pixelAligned, screen: screen)
    }
}

private func go(
    _ from: CGWindowID,
    _ dir: Direction,
    _ items: [Item],
    displays: [Display] = [],
    stamps: [CGWindowID: Int] = [:]
) throws -> MotionResolver.Hit? {
    let origin = try #require(items.first { $0.id == from })
    return MotionResolver.resolve(from: origin, dir, among: items, displays: displays, stamps: stamps)
}

@Suite struct MotionResolverTests {
    let tall = tiled(.tall, 3)
    let sideBySide = [Display(id: "A", frame: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
                      Display(id: "B", frame: CGRect(x: 1600, y: 0, width: 1600, height: 1000))]
    let stacked = [Display(id: "A", frame: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
                   Display(id: "B", frame: CGRect(x: 0, y: 1000, width: 1600, height: 1000))]

    @Test func downAndUpMoveInsideTheStack() throws {
        #expect(try go(2, .down, tall) == .window(3))
        #expect(try go(3, .upward, tall) == .window(2))
    }

    @Test func upFromTheTopOfTheStackWrapsToItsBottom() throws {
        #expect(try go(2, .upward, tall) == .window(3))
    }

    @Test func downFromTheBottomOfTheStackWrapsToItsTop() throws {
        #expect(try go(3, .down, tall) == .window(2))
    }

    @Test func upAndDownWrapInsideALongStack() throws {
        let five = tiled(.tall, 5)
        #expect(try go(2, .upward, five) == .window(5))
        #expect(try go(5, .down, five) == .window(2))
        #expect(try go(3, .upward, five) == .window(2))
        #expect(try go(4, .down, five) == .window(5))
    }

    @Test func upAndDownNeverJumpToMainOrSideways() throws {
        for id: CGWindowID in [2, 3] {
            for dir in [Direction.upward, .down] { #expect(try go(id, dir, tall) != .window(1)) }
        }
        #expect(try go(1, .upward, tall) == nil)
        #expect(try go(1, .down, tall) == nil)
    }

    @Test func leftFromTheStackGoesToMain() throws {
        #expect(try go(2, .left, tall) == .window(1))
        #expect(try go(3, .left, tall) == .window(1))
    }

    @Test func rightFromMainReturnsToTheWindowYouCameFrom() throws {
        #expect(try go(1, .right, tall, stamps: [2: 1, 3: 2, 1: 3]) == .window(3))
        #expect(try go(1, .right, tall, stamps: [3: 1, 2: 2, 1: 3]) == .window(2))
    }

    @Test func leftThenRightIsARoundTrip() throws {
        var stamps: [CGWindowID: Int] = [:]
        var clock = 0
        func note(_ id: CGWindowID) { clock += 1; stamps[id] = clock }
        for start: CGWindowID in [2, 3] {
            note(start)
            let left = try go(start, .left, tall, stamps: stamps)
            #expect(left == .window(1))
            note(1)
            #expect(try go(1, .right, tall, stamps: stamps) == .window(start))
        }
    }

    @Test func rightFromMainWithoutHistoryPicksTheNearestCentre() throws {
        let four = tiled(.tall, 4)
        #expect(try go(1, .right, four) == .window(3))
    }

    @Test func leftAndRightWrapInARow() throws {
        let row = tiled(.column, 3)
        #expect(try go(1, .right, row) == .window(2))
        #expect(try go(3, .right, row) == .window(1))
        #expect(try go(1, .left, row) == .window(3))
    }

    @Test func aStackInOneSlotCyclesInTilingOrder() throws {
        let full = tiled(.fullscreen, 3)
        #expect(try go(1, .right, full) == .window(2))
        #expect(try go(3, .down, full) == .window(1))
        #expect(try go(1, .left, full) == .window(3))
    }

    @Test func goingOffTheEdgeCrossesToTheNextDisplay() throws {
        let left = tiled(.tall, 2, screen: "A")
        let right = tiled(.tall, 1, screen: "B", in: CGRect(x: 1600, y: 300, width: 1000, height: 700), first: 10)
        let all = left + right
        let displays = [Display(id: "A", frame: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
                        Display(id: "B", frame: CGRect(x: 1600, y: 300, width: 1000, height: 700))]
        #expect(try go(2, .right, all, displays: displays) == .window(10))
        #expect(try go(10, .left, all, displays: displays) == .window(2))
    }

    @Test func wrappingStaysOnItsOwnDisplay() throws {
        let left = tiled(.column, 2, screen: "A")
        let right = tiled(.column, 2, screen: "B", in: CGRect(x: 1600, y: 0, width: 1600, height: 1000), first: 10)
        let all = left + right
        #expect(try go(1, .left, all, displays: sideBySide) == .window(2))
        #expect(try go(11, .right, all, displays: sideBySide) == .window(10))
    }

    @Test func goingOffTheBottomReachesTheEmptyDisplayBelowBeforeItWraps() throws {
        #expect(try go(3, .down, tall, displays: stacked) == .monitor("B"))
        #expect(try go(2, .upward, tiled(.tall, 3, screen: "B", in: stacked[1].frame), displays: stacked)
            == .monitor("A"))
    }

    @Test func aWindowOnTheDisplayBelowIsANeighbor() throws {
        let below = tiled(.tall, 1, screen: "B", in: stacked[1].frame, first: 10)
        #expect(try go(3, .down, tall + below, displays: stacked) == .window(10))
    }

    @Test func emptyDisplayIsNotSkippedForAWindowFartherAway() throws {
        let third = Display(id: "C", frame: CGRect(x: 3200, y: 0, width: 1600, height: 1000))
        let items = tiled(.column, 1) + tiled(.column, 1, screen: "C", in: third.frame, first: 10)
        #expect(try go(1, .right, items, displays: sideBySide + [third]) == .monitor("B"))
    }

    @Test func anOffsetDisplayBesideIsNotBelow() throws {
        let offset = [sideBySide[0], Display(id: "B", frame: CGRect(x: 1600, y: 300, width: 1000, height: 700))]
        #expect(try go(3, .down, tall, displays: offset) == .window(2))
        #expect(try go(2, .upward, tall, displays: offset) == .window(3))
    }

    @Test func eachDirectionWrapsWhenNoDisplayIsThere() throws {
        let row = tiled(.column, 3)
        #expect(try go(3, .right, row, displays: [sideBySide[0]]) == .window(1))
        #expect(try go(1, .left, row, displays: [sideBySide[0]]) == .window(3))
        #expect(try go(3, .down, tall, displays: [sideBySide[0]]) == .window(2))
        #expect(try go(2, .upward, tall, displays: [sideBySide[0]]) == .window(3))
    }

    @Test func cycleStepsBothWaysAndNeedsTwoWindows() {
        #expect(MotionResolver.cycle(1, in: [1, 2, 3], .right) == 2)
        #expect(MotionResolver.cycle(1, in: [1, 2, 3], .upward) == 3)
        #expect(MotionResolver.cycle(3, in: [1, 2, 3], .down) == 1)
        #expect(MotionResolver.cycle(1, in: [1], .down) == nil)
    }
}
