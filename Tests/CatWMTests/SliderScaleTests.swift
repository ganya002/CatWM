@testable import CatWM
import Testing

@Suite struct SliderScaleTests {
    @Test(arguments: [9.0, 10.0, 11.0])
    func discreteAdjustmentsMoveThroughTicks(value: Double) {
        let scale = SliderScale(range: 0...60, step: 1, ticks: [10])
        #expect(scale.stepping(value, by: 1) == value + 1)
        #expect(scale.stepping(value, by: -1) == value - 1)
    }

    @Test func shiftedAdjustmentsAndBounds() {
        let scale = SliderScale(range: 0...60, step: 1, ticks: [10])
        #expect(scale.stepping(10, by: 10) == 20)
        #expect(scale.stepping(20, by: -10) == 10)
        #expect(scale.stepping(60, by: 1) == 60)
        #expect(scale.stepping(0, by: -1) == 0)
    }

    @Test func pointerStillSnapsNearTicks() {
        let scale = SliderScale(range: 0...60, step: 1, ticks: [10])
        #expect(scale.value(at: 9.0 / 60) == 10)
        #expect(scale.value(at: 11.0 / 60) == 10)
        #expect(scale.value(at: 12.0 / 60) == 12)
    }
}
