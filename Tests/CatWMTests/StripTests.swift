@testable import CatWM
import CoreGraphics
import Testing

@Suite struct StripTests {
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func strip(_ columns: [[CGWindowID]], width: CGFloat = 0.5) -> Strip {
        Strip(columns: columns.map { Strip.Column($0, width: width) })
    }

    @Test func aNewWindowOpensRightOfTheFocusedColumn() {
        var model = strip([[1], [2], [3]])
        model.sync([1, 2, 3, 4], focus: 1, width: 0.5)
        #expect(model.columns.map(\.ids) == [[1], [4], [2], [3]])
    }

    @Test func aGoneWindowLeavesItsColumnAndAnEmptyColumnGoes() {
        var model = strip([[1, 2], [3]])
        model.sync([1], focus: nil, width: 0.5)
        #expect(model.columns.map(\.ids) == [[1]])
        #expect(model.columns[0].heights == [1])
    }

    @Test func consumeMovesTheWindowIntoTheNextColumnAndExpelTakesItOut() {
        var model = strip([[1], [2]])
        let consumed = model.consumeOrExpel(2, by: -1)
        #expect(consumed && model.columns.map(\.ids) == [[1, 2]])
        let expelled = model.consumeOrExpel(2, by: 1)
        #expect(expelled && model.columns.map(\.ids) == [[1], [2]])
        let past = model.consumeOrExpel(2, by: 1)
        #expect(!past)
    }

    @Test func moveColumnStopsAtTheEnds() {
        var model = strip([[1], [2]])
        let moved = model.moveColumn(of: 1, by: 1)
        #expect(moved && model.columns.map(\.ids) == [[2], [1]])
        let past = model.moveColumn(of: 1, by: 1)
        #expect(!past)
    }

    @Test func cycleWidthStepsThroughThePresetsAndWraps() {
        var model = strip([[1]])
        let presets: [CGFloat] = [1.0 / 3, 0.5, 2.0 / 3]
        model.cycleWidth(of: 1, presets: presets)
        #expect(model.columns[0].width == 2.0 / 3)
        model.cycleWidth(of: 1, presets: presets)
        #expect(model.columns[0].width == 1.0 / 3)
    }

    @Test func widthStaysInRange() {
        var model = strip([[1]])
        model.setWidth(of: 1) { $0 + 5 }
        #expect(model.columns[0].width == 1)
        model.setWidth(of: 1) { _ in 0 }
        #expect(model.columns[0].width == Strip.widthRange.lowerBound)
    }

    @Test func aHeightChangeResizesOneWindowInItsColumn() throws {
        var model = strip([[1, 2]])
        model.setHeight(of: 1, by: 0.25)
        let frames = model.frames(in: rect, gap: 0)
        let top = try #require(frames[1]), bottom = try #require(frames[2])
        #expect(top.height == 600)
        #expect(bottom.height == 200)
        #expect(top.maxY == bottom.minY)
    }

    @Test func columnsSitSideBySideWithTheGapBetweenThem() throws {
        let model = strip([[1], [2]])
        let frames = model.frames(in: rect, gap: 10)
        let left = try #require(frames[1]), right = try #require(frames[2])
        #expect(left.minX == rect.minX && right.maxX == rect.maxX)
        #expect(right.minX - left.maxX == 10)
        #expect(left.height == rect.height)
    }

    @Test func minimumScrollShowsTheFocusedColumnAtTheNearEdge() {
        var model = strip([[1], [2], [3], [4]])
        model.reveal(4, in: rect, gap: 0, scroll: .minimum, centerSingle: true)
        #expect(model.offset == 1000)
        model.reveal(2, in: rect, gap: 0, scroll: .minimum, centerSingle: true)
        #expect(model.offset == 500)
        model.reveal(3, in: rect, gap: 0, scroll: .minimum, centerSingle: true)
        #expect(model.offset == 500)
    }

    @Test func centerScrollPutsTheFocusedColumnInTheMiddle() {
        var model = strip([[1], [2], [3]])
        model.reveal(2, in: rect, gap: 0, scroll: .center, centerSingle: true)
        #expect(model.offset == 250)
    }

    @Test func aSingleColumnIsCentered() throws {
        var model = strip([[1]])
        model.reveal(1, in: rect, gap: 0, scroll: .minimum, centerSingle: true)
        let frame = try #require(model.frames(in: rect, gap: 0)[1])
        #expect(frame.midX == rect.midX)
        model.reveal(1, in: rect, gap: 0, scroll: .minimum, centerSingle: false)
        #expect(model.frames(in: rect, gap: 0)[1]?.minX == rect.minX)
    }
}
