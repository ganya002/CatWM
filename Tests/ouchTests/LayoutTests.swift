// Tests: the layout algorithms and the fit around minimum window sizes.
import CoreGraphics
import Testing
@testable import ouch

@Suite struct LayoutFramesTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func noWindowsGivesNoFrames() {
        for l in Layout.allCases where l != .floating {
            #expect(l.frames(count: 0, in: screen, ratio: 0.5, mainCount: 1) == [])
        }
    }

    @Test func floatingDoesNotTouchWindows() {
        #expect(Layout.floating.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1) == nil)
    }

    @Test func everyLayoutGivesOneFrameEachInsideTheScreen() {
        for l in Layout.allCases where l != .floating {
            for n in 1...7 {
                let f = l.frames(count: n, in: screen, ratio: 0.6, mainCount: 2) ?? []
                #expect(f.count == n, "\(l) with \(n) windows")
                #expect(f.allSatisfy { screen.insetBy(dx: -0.5, dy: -0.5).contains($0) }, "\(l) with \(n) windows")
            }
        }
    }

    @Test func tallPutsMainLeftAndStacksTheRest() {
        let f = Layout.tall.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)!
        #expect(f[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(f[1] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(f[2] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func tallRightPutsMainRight() {
        let f = Layout.tallRight.frames(count: 2, in: screen, ratio: 0.6, mainCount: 1)!
        #expect(f[0] == CGRect(x: 400, y: 0, width: 600, height: 600))
        #expect(f[1] == CGRect(x: 0, y: 0, width: 400, height: 600))
    }

    @Test func tallWithOnlyMainWindowsStacksThemInRows() {
        let f = Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 2)!
        #expect(f == [CGRect(x: 0, y: 0, width: 1000, height: 300), CGRect(x: 0, y: 300, width: 1000, height: 300)])
    }

    @Test func mainCountIsClampedToTheWindowCount() {
        let a = Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 9)
        let b = Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 2)
        #expect(a == b)
        let c = Layout.tall.frames(count: 3, in: screen, ratio: 0.5, mainCount: 0)
        let d = Layout.tall.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)
        #expect(c == d)
    }

    @Test func wideSplitsTopAndBottom() {
        let f = Layout.wide.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)!
        #expect(f[0] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(f[1] == CGRect(x: 0, y: 300, width: 500, height: 300))
        #expect(f[2] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func fullscreenGivesEveryWindowTheScreen() {
        #expect(Layout.fullscreen.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1) == Array(repeating: screen, count: 3))
    }

    @Test func twoPaneStacksTheRestInOneSlot() {
        let f = Layout.twoPane.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)!
        #expect(f[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(f[1] == f[2])
        #expect(f[1] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    @Test func middleWideWithTwoWindowsIsTall() {
        #expect(Layout.middleWide.frames(count: 2, in: screen, ratio: 0.5, mainCount: 1)
                == Layout.tall.frames(count: 2, in: screen, ratio: 0.5, mainCount: 1))
    }

    @Test func middleWidePutsMainInTheMiddle() {
        let f = Layout.middleWide.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)!
        #expect(f[0] == CGRect(x: 250, y: 0, width: 500, height: 600))
        #expect(f[1] == CGRect(x: 0, y: 0, width: 250, height: 600))
        #expect(f[2] == CGRect(x: 750, y: 0, width: 250, height: 600))
    }

    @Test func bspSplitsTheRestInHalves() {
        let f = Layout.bsp.frames(count: 3, in: screen, ratio: 0.5, mainCount: 1)!
        #expect(f[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(f[1] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(f[2] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func framesDoNotOverlap() {
        for l in Layout.allCases where ![.floating, .fullscreen, .twoPane, .twoPaneRight].contains(l) {
            let f = l.frames(count: 5, in: screen, ratio: 0.55, mainCount: 1)!
            for i in f.indices {
                for j in f.indices where j > i {
                    let o = f[i].intersection(f[j])
                    #expect(o.isNull || o.width * o.height < 1, "\(l): \(i) and \(j) overlap")
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
        let f = fitMinimums(column, mins: [CGSize(width: 100, height: 400), nil], gap: 0)
        #expect(f[0] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(f[1] == CGRect(x: 0, y: 400, width: 500, height: 200))
    }

    @Test func theGapStaysBetweenWindows() {
        let gapped = [CGRect(x: 0, y: 0, width: 500, height: 295), CGRect(x: 0, y: 305, width: 500, height: 295)]
        let f = fitMinimums(gapped, mins: [nil, CGSize(width: 100, height: 390)], gap: 10)
        #expect(f[1].height == 390)
        #expect(f[1].minY - f[0].maxY == 10)
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
        let f = fitMinimums(bad, mins: [CGSize(width: 100, height: 400), nil], gap: 0)
        #expect(f[0].minX.isNaN)
        #expect(f[1] == column[1])
    }

    @Test func aWideMinimumTakesRoomFromItsRow() {
        let row = [CGRect(x: 0, y: 0, width: 300, height: 600), CGRect(x: 300, y: 0, width: 300, height: 600),
                   CGRect(x: 600, y: 0, width: 300, height: 600)]
        let f = fitMinimums(row, mins: [nil, CGSize(width: 500, height: 100), nil], gap: 0)
        #expect(f.map(\.width) == [200, 500, 200])
        #expect(f.map(\.minX) == [0, 200, 700])
    }
}
