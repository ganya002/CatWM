@testable import CatWM
@testable import CatWMKit
import CoreGraphics
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

    @Test func aWideMinimumInAStackWidensTheWholeStack() {
        let tall = [CGRect(x: 0, y: 0, width: 600, height: 600), CGRect(x: 610, y: 0, width: 290, height: 295),
                    CGRect(x: 610, y: 305, width: 290, height: 295)]
        let frames = fitMinimums(tall, mins: [nil, CGSize(width: 400, height: 100), nil], gap: 10)
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 490, height: 600))
        #expect(frames[1] == CGRect(x: 500, y: 0, width: 400, height: 295))
        #expect(frames[2] == CGRect(x: 500, y: 305, width: 400, height: 295))
    }

    @Test func aMinimumOnlyTakesTheRoomItNeedsFromAnUnequalSplit() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let raw = try #require(Layout.tall.frames(count: 2, in: screen, ratio: 0.8, mainCount: 1))
        let frames = fitMinimums(raw, mins: [nil, CGSize(width: 300, height: 100)], gap: 0)
        #expect(frames == [CGRect(x: 0, y: 0, width: 700, height: 600),
                           CGRect(x: 700, y: 0, width: 300, height: 600)])
        #expect(fitMinimums(frames, mins: [nil, CGSize(width: 300, height: 100)], gap: 0) == frames)
    }

    @Test func aTallMinimumInTheBottomRowTakesRoomFromTheMainRow() throws {
        let wide = try #require(Layout.wide.frames(count: 3, in: CGRect(x: 0, y: 0, width: 1000, height: 600),
                                                   ratio: 0.5, mainCount: 1))
        let frames = fitMinimums(wide, mins: [nil, CGSize(width: 100, height: 400), nil], gap: 0)
        #expect(frames == [CGRect(x: 0, y: 0, width: 1000, height: 200), CGRect(x: 0, y: 200, width: 500, height: 400),
                           CGRect(x: 500, y: 200, width: 500, height: 400)])
    }

    @Test func oneLargeWindowNeverCoversAnotherInAGridLayout() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let stacked: [Layout] = [.floating, .fullscreen, .twoPane, .twoPaneRight, .bsp]
        for layout in Layout.allCases where !stacked.contains(layout) {
            for count in 2...5 {
                for index in 0..<count {
                    for min in [CGSize(width: 0, height: 380), CGSize(width: 600, height: 0)] {
                        let raw = layout.frames(count: count, in: screen, ratio: 0.5, mainCount: 1) ?? []
                        var mins = [CGSize?](repeating: nil, count: count)
                        mins[index] = min
                        let frames = zip(fitMinimums(raw, mins: mins, gap: 0), mins).map {
                            clampToMinimum($0, min: $1, bounds: screen)
                        }
                        for i in frames.indices {
                            for j in frames.indices where j > i {
                                let overlap = frames[i].intersection(frames[j])
                                #expect(overlap.isNull || overlap.width < 1 || overlap.height < 1,
                                        "\(layout) with \(count) windows and \(min) on \(index)")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Suite struct SplitDividerTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func slots(_ layout: Layout, count: Int, ratio: CGFloat, gap: CGFloat, mainCount: Int = 1) -> [CGRect] {
        let raw = layout.frames(count: count, in: screen.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: ratio,
                                mainCount: mainCount) ?? []
        return raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
    }

    @Test func sitsInTheGapBetweenMainAndStack() throws {
        let divider = try #require(SplitDivider(layout: .tall, slots: slots(.tall, count: 3, ratio: 0.6, gap: 10),
                                                mainCount: 1, in: screen))
        #expect(divider.vertical)
        #expect(divider.frame.width == 10)
        #expect(abs(divider.position - 601) < 0.01)
        #expect(divider.frame.height == screen.height)
    }

    @Test func positionGivesBackTheRatio() throws {
        for layout in [Layout.tall, .tallRight, .wide, .twoPane, .twoPaneRight, .bsp, .widescreenTallRight] {
            let frames = slots(layout, count: 3, ratio: 0.35, gap: 10)
            let divider = try #require(SplitDivider(layout: layout, slots: frames, mainCount: 1, in: screen),
                                       "\(layout)")
            #expect(abs(divider.ratio(at: divider.position, in: screen, gap: 10) - 0.35) < 0.001, "\(layout)")
        }
    }

    @Test func wideSplitsAcrossTheScreen() throws {
        let divider = try #require(SplitDivider(layout: .wide, slots: slots(.wide, count: 2, ratio: 0.5, gap: 0),
                                                mainCount: 1, in: screen))
        #expect(!divider.vertical)
        #expect(divider.position == 300)
    }

    @Test func ratioStaysInRange() throws {
        let divider = try #require(SplitDivider(layout: .tall, slots: slots(.tall, count: 2, ratio: 0.5, gap: 0),
                                                mainCount: 1, in: screen))
        #expect(divider.ratio(at: -500, in: screen, gap: 0) == SplitDivider.ratioRange.lowerBound)
        #expect(divider.ratio(at: 5000, in: screen, gap: 0) == SplitDivider.ratioRange.upperBound)
    }

    @Test func noDividerWithoutTwoSides() {
        #expect(SplitDivider(layout: .tall, slots: slots(.tall, count: 1, ratio: 0.5, gap: 0), mainCount: 1,
                             in: screen) == nil)
        #expect(SplitDivider(layout: .tall, slots: slots(.tall, count: 2, ratio: 0.5, gap: 0, mainCount: 2),
                             mainCount: 2, in: screen) == nil)
        #expect(SplitDivider(layout: .column, slots: slots(.column, count: 3, ratio: 0.5, gap: 0), mainCount: 1,
                             in: screen) == nil)
    }

    @Test func mirroringSwapsTheSidesAndKeepsTheSizes() throws {
        for layout in Layout.allCases {
            guard let mirrored = layout.mirrored else { continue }
            #expect(mirrored.mirrored == layout)
            let before = try #require(layout.frames(count: 3, in: screen, ratio: 0.6, mainCount: 1))
            let after = try #require(mirrored.frames(count: 3, in: screen, ratio: 0.6, mainCount: 1))
            #expect(before[0].size == after[0].size, "\(layout)")
            #expect(before[0].midX == screen.width - after[0].midX, "\(layout)")
        }
    }
}

@Suite struct ClampToMinimumTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func aWindowThatFitsKeepsItsSlot() {
        let slot = CGRect(x: 0, y: 0, width: 500, height: 300)
        #expect(clampToMinimum(slot, min: CGSize(width: 400, height: 300), bounds: bounds) == slot)
        #expect(clampToMinimum(slot, min: nil, bounds: bounds) == slot)
    }

    @Test func aLoneOversizedWindowOverflowsRightAndDown() {
        let slot = CGRect(x: 100, y: 100, width: 200, height: 200)
        let frame = clampToMinimum(slot, min: CGSize(width: 400, height: 300), bounds: bounds)
        #expect(frame == CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    @Test func theOversizedWindowStaysInsideTheScreen() {
        let slot = CGRect(x: 800, y: 500, width: 200, height: 100)
        let frame = clampToMinimum(slot, min: CGSize(width: 400, height: 300), bounds: bounds)
        #expect(frame == CGRect(x: 600, y: 300, width: 400, height: 300))
    }

    @Test func aGroupThatCannotFitStillGivesOneStableFrame() {
        let column = [CGRect(x: 0, y: 0, width: 500, height: 300), CGRect(x: 0, y: 300, width: 500, height: 300)]
        let mins = [CGSize(width: 100, height: 500), CGSize(width: 100, height: 500)]
        let slots = fitMinimums(column, mins: mins, gap: 0)
        let frames = zip(slots, mins).map { clampToMinimum($0, min: $1, bounds: bounds) }
        #expect(frames == [CGRect(x: 0, y: 0, width: 500, height: 500), CGRect(x: 0, y: 100, width: 500, height: 500)])
        #expect(zip(frames, mins).map { clampToMinimum($0, min: $1, bounds: bounds) } == frames)
    }
}
