import CoreGraphics
@testable import ouch
import Testing

typealias Item = FocusNavigation.Item

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
    stamps: [CGWindowID: Int] = [:]
) throws -> CGWindowID? {
    let origin = try #require(items.first { $0.id == from })
    return FocusNavigation.target(from: origin, dir, among: items, stamps: stamps)
}

@Suite struct FocusNavigationTests {
    let tall = tiled(.tall, 3)

    @Test func downAndUpMoveInsideTheStack() throws {
        #expect(try go(2, .down, tall) == 3)
        #expect(try go(3, .upward, tall) == 2)
    }

    @Test func upFromTheTopOfTheStackWrapsToItsBottom() throws {
        #expect(try go(2, .upward, tall) == 3)
    }

    @Test func downFromTheBottomOfTheStackWrapsToItsTop() throws {
        #expect(try go(3, .down, tall) == 2)
    }

    @Test func upAndDownWrapInsideALongStack() throws {
        let five = tiled(.tall, 5)
        #expect(try go(2, .upward, five) == 5)
        #expect(try go(5, .down, five) == 2)
        #expect(try go(3, .upward, five) == 2)
        #expect(try go(4, .down, five) == 5)
    }

    @Test func upAndDownNeverJumpToMainOrSideways() throws {
        for id: CGWindowID in [2, 3] {
            for dir in [Direction.upward, .down] { #expect(try go(id, dir, tall) != 1) }
        }
        #expect(try go(1, .upward, tall) == nil)
        #expect(try go(1, .down, tall) == nil)
    }

    @Test func leftFromTheStackGoesToMain() throws {
        #expect(try go(2, .left, tall) == 1)
        #expect(try go(3, .left, tall) == 1)
    }

    @Test func rightFromMainReturnsToTheWindowYouCameFrom() throws {
        #expect(try go(1, .right, tall, stamps: [2: 1, 3: 2, 1: 3]) == 3)
        #expect(try go(1, .right, tall, stamps: [3: 1, 2: 2, 1: 3]) == 2)
    }

    @Test func leftThenRightIsARoundTrip() throws {
        var stamps: [CGWindowID: Int] = [:]
        var clock = 0
        func note(_ id: CGWindowID) { clock += 1; stamps[id] = clock }
        for start: CGWindowID in [2, 3] {
            note(start)
            let left = try go(start, .left, tall, stamps: stamps)
            #expect(left == 1)
            note(1)
            #expect(try go(1, .right, tall, stamps: stamps) == start)
        }
    }

    @Test func rightFromMainWithoutHistoryPicksTheNearestCentre() throws {
        let four = tiled(.tall, 4)
        #expect(try go(1, .right, four) == 3)
    }

    @Test func leftAndRightWrapInARow() throws {
        let row = tiled(.column, 3)
        #expect(try go(1, .right, row) == 2)
        #expect(try go(3, .right, row) == 1)
        #expect(try go(1, .left, row) == 3)
    }

    @Test func aStackInOneSlotCyclesInTilingOrder() throws {
        let full = tiled(.fullscreen, 3)
        #expect(try go(1, .right, full) == 2)
        #expect(try go(3, .down, full) == 1)
        #expect(try go(1, .left, full) == 3)
    }

    @Test func goingOffTheEdgeCrossesToTheNextDisplay() throws {
        let left = tiled(.tall, 2, screen: "A")
        let right = tiled(.tall, 1, screen: "B", in: CGRect(x: 1600, y: 300, width: 1000, height: 700), first: 10)
        let all = left + right
        #expect(try go(2, .right, all) == 10)
        #expect(try go(10, .left, all) == 2)
    }

    @Test func wrappingStaysOnItsOwnDisplay() throws {
        let left = tiled(.column, 2, screen: "A")
        let right = tiled(.column, 2, screen: "B", in: CGRect(x: 1600, y: 0, width: 1600, height: 1000), first: 10)
        let all = left + right
        #expect(try go(1, .left, all) == 2)
        #expect(try go(11, .right, all) == 10)
    }
}
