import ApplicationServices
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct AXStallMemoryTests {
    final class Clock { var time: CFTimeInterval = 100 }

    @Test func aQuickAppIsNeverStalled() {
        let clock = Clock()
        let stalls = AXStalls { clock.time }
        stalls.record(42, .success, took: 0.001)
        stalls.record(42, .noValue, took: 0.4)
        #expect(!stalls.isStalled(42))
    }

    @Test func aShortTimeoutDoesNotMarkTheApp() {
        let clock = Clock()
        let stalls = AXStalls { clock.time }
        stalls.record(42, .cannotComplete, took: 0.03)
        #expect(!stalls.isStalled(42))
    }

    @Test func aTimeoutMarksOnlyThatApp() {
        let clock = Clock()
        let stalls = AXStalls { clock.time }
        stalls.record(42, .cannotComplete, took: 0.5)
        #expect(stalls.isStalled(42))
        #expect(!stalls.isStalled(7))
    }

    @Test func anAnswerClearsTheMark() {
        let clock = Clock()
        let stalls = AXStalls { clock.time }
        stalls.record(42, .cannotComplete, took: 0.5)
        stalls.record(42, .success, took: 0.001)
        #expect(!stalls.isStalled(42))
    }

    @Test func theMarkExpires() {
        let clock = Clock()
        let stalls = AXStalls { clock.time }
        stalls.record(42, .cannotComplete, took: 0.5)
        clock.time += AXStalls.memory - 0.1
        #expect(stalls.isStalled(42))
        clock.time += 0.2
        #expect(!stalls.isStalled(42))
    }

    @Test func aTimedOutCallOnTheElementMarksItsApp() {
        let clock = Clock()
        let stalls = AXStalls { clock.time }
        let element = AXUIElementCreateApplication(getpid())
        clock.time = 200
        stalls.note(element, .cannotComplete, since: 200 - AXStalls.hangLine)
        #expect(stalls.isStalled(getpid()))
        stalls.note(element, .success, since: 200)
        #expect(!stalls.isStalled(getpid()))
    }
}
