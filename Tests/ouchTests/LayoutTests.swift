import CoreGraphics
@testable import ouch
import Testing

@Suite struct LayoutFramesTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func noWindowsGivesNoFrames() {
        for layout in Layout.allCases where layout != .floating {
            #expect(layout.frames(count: 0, in: screen, ratio: 0.5, mainCount: 1)?.isEmpty == true)
        }
    }

    @Test func floatingDoesNotTouchWindows() {
        #expect(Layout.floating.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1) == nil)
    }

    @Test func everyLayoutGivesOneFrameEachInsideTheScreen() {
        for layout in Layout.allCases where layout != .floating {
            for count in 1...7 {
                let frames = layout.frames(count: count, in: screen, ratio: 0.6, mainCount: 2) ?? []
                #expect(frames.count == count, "\(layout) with \(count) windows")
                #expect(
                    frames.allSatisfy { screen.insetBy(dx: -0.5, dy: -0.5).contains($0) },
                    "\(layout) with \(count) windows"
                )
            }
        }
    }

    @Test func tallPutsMainLeftAndStacksTheRest() throws {
        let frames = try #require(Layout.tall.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1))
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[1] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(frames[2] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func tallRightPutsMainRight() throws {
        let frames = try #require(Layout.tallRight.frames(count: 2, in: screen, ratio: 0.6, mainCount: 1))
        #expect(frames[0] == CGRect(x: 400, y: 0, width: 600, height: 600))
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 400, height: 600))
    }

    @Test func tallWithOnlyMainWindowsStacksThemInRows() throws {
        let frames = try #require(Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 2))
        #expect(frames == [
            CGRect(x: 0, y: 0, width: 1000, height: 300),
            CGRect(x: 0, y: 300, width: 1000, height: 300)
        ])
    }

    @Test func mainCountIsClampedToTheWindowCount() {
        let tooMany = Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 9)
        let allMain = Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 2)
        #expect(tooMany == allMain)
        let noMain = Layout.tall.frames(count: 3, in: screen, ratio: 0.5, mainCount: 0)
        let oneMain = Layout.tall.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)
        #expect(noMain == oneMain)
    }

    @Test func wideSplitsTopAndBottom() throws {
        let frames = try #require(Layout.wide.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1))
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(frames[1] == CGRect(x: 0, y: 300, width: 500, height: 300))
        #expect(frames[2] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func fullscreenGivesEveryWindowTheScreen() {
        #expect(
            Layout.fullscreen.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)
                == Array(repeating: screen, count: 3)
        )
    }

    @Test func twoPaneStacksTheRestInOneSlot() throws {
        let frames = try #require(Layout.twoPane.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1))
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[1] == frames[2])
        #expect(frames[1] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    @Test func middleWideWithTwoWindowsIsTall() {
        #expect(Layout.middleWide.frames(count: 2, in: screen, ratio: 0.5, mainCount: 1)
                == Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 1))
    }

    @Test func middleWidePutsMainInTheMiddle() throws {
        let frames = try #require(Layout.middleWide.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1))
        #expect(frames[0] == CGRect(x: 250, y: 0, width: 500, height: 600))
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 250, height: 600))
        #expect(frames[2] == CGRect(x: 750, y: 0, width: 250, height: 600))
    }

    @Test func bspSplitsTheRestInHalves() throws {
        let frames = try #require(Layout.bsp.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1))
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[1] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(frames[2] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func framesDoNotOverlap() throws {
        for layout in Layout.allCases where ![.floating, .fullscreen, .twoPane, .twoPaneRight].contains(layout) {
            let frames = try #require(layout.frames(count: 5, in: screen, ratio: 0.55, mainCount: 1))
            for i in frames.indices {
                for j in frames.indices where j > i {
                    let overlap = frames[i].intersection(frames[j])
                    #expect(overlap.isNull || overlap.width * overlap.height < 1, "\(layout): \(i) and \(j) overlap")
                }
            }
        }
    }
}

@Suite struct FitMinimumsTests {
    let column = [CGRect(x: 0, y: 0, width: 500, height: 300), CGRect(x: 0, y: 300, width: 500, height: 300)]

    @Test func noMinimumsLeavesFramesAlone() {
        #expect(fitMinimums(column, mins: [nil, nil], gap: 0) == column)
    }

    @Test func aMinimumThatFitsLeavesFramesAlone() {
        #expect(fitMinimums(column, mins: [CGSize(width: 100, height: 200), nil], gap: 0) == column)
    }

    @Test func aTallMinimumTakesRoomFromItsStack() {
        let frames = fitMinimums(column, mins: [CGSize(width: 100, height: 400), nil], gap: 0)
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[1] == CGRect(x: 0, y: 400, width: 500, height: 200))
    }

    @Test func theGapStaysBetweenWindows() {
        let gapped = [CGRect(x: 0, y: 0, width: 500, height: 295), CGRect(x: 0, y: 305, width: 500, height: 295)]
        let frames = fitMinimums(gapped, mins: [nil, CGSize(width: 100, height: 390)], gap: 10)
        #expect(frames[1].height == 390)
        #expect(frames[1].minY - frames[0].maxY == 10)
    }

    @Test func aStackThatCannotFitIsLeftAlone() {
        let mins = [CGSize(width: 100, height: 500), CGSize(width: 100, height: 500)]
        #expect(fitMinimums(column, mins: mins, gap: 0) == column)
    }

    @Test func windowsStackedOnTopOfEachOtherAreLeftAlone() {
        let same = [column[0], column[0]]
        #expect(fitMinimums(same, mins: [CGSize(width: 100, height: 400), nil], gap: 0) == same)
    }

    @Test func badFramesAreLeftAlone() {
        let bad = [CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), column[1]]
        let frames = fitMinimums(bad, mins: [CGSize(width: 100, height: 400), nil], gap: 0)
        #expect(frames[0].minX.isNaN)
        #expect(frames[1] == column[1])
    }

    @Test func aWideMinimumTakesRoomFromItsRow() {
        let row = [CGRect(x: 0, y: 0, width: 300, height: 600), CGRect(x: 300, y: 0, width: 300, height: 600),
                   CGRect(x: 600, y: 0, width: 300, height: 600)]
        let frames = fitMinimums(row, mins: [nil, CGSize(width: 500, height: 100), nil], gap: 0)
        #expect(frames.map(\.width) == [200, 500, 200])
        #expect(frames.map(\.minX) == [0, 200, 700])
    }
}
