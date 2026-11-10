import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

struct WindowScenePlacementTests {
    @Test func coverageHidesSizeAndPositionWritesInEitherOrder() {
        let source = CGRect(x: 600, y: 500, width: 200, height: 100)
        let target = CGRect(x: 100, y: 100, width: 500, height: 400)
        var placement = WindowScenePlacement(frame: source)
        placement.retarget(to: target)
        #expect(placement.coverage.contains(source))
        #expect(placement.coverage.contains(target))
        #expect(placement.coverage.contains(CGRect(origin: source.origin, size: target.size)))
        #expect(placement.coverage.contains(CGRect(origin: target.origin, size: source.size)))
    }

    @Test func aPreviousLandingCannotExposeAnInFlightRetarget() {
        let source = CGRect(x: 600, y: 500, width: 200, height: 100)
        let first = CGRect(x: 100, y: 100, width: 500, height: 400)
        let second = CGRect(x: 400, y: 200, width: 800, height: 500)
        var placement = WindowScenePlacement(frame: source)
        placement.retarget(to: first)
        placement.retarget(to: second)
        placement.landed(at: first, target: first)
        #expect(placement.coverage.contains(source))
        #expect(placement.coverage.contains(CGRect(origin: first.origin, size: second.size)))
        #expect(placement.coverage.contains(second))
        placement.landed(at: second, target: second)
        #expect(placement.coverage == second)
    }

    @Test func aRefusedResizeKeepsTheWholeActualWindowCovered() {
        let source = CGRect(x: 100, y: 100, width: 800, height: 600)
        let target = CGRect(x: 100, y: 100, width: 400, height: 300)
        let actual = CGRect(x: 100, y: 100, width: 900, height: 700)
        var placement = WindowScenePlacement(frame: source)
        placement.retarget(to: target)
        placement.landed(at: actual, target: target)
        #expect(placement.coverage.contains(source))
        #expect(placement.coverage.contains(actual))
    }
}
