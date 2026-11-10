@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct CatMotionTests {
    @Test(arguments: CatMove.allCases)
    func everyMoveEndsAtRest(_ move: CatMove) {
        #expect(move.motion(at: 0) == CatMotion())
        let end = move.motion(at: move.duration)
        #expect(end.lift == 0 && end.stretch == 1 && end.lean == 0 && end.lookY == 0)
        #expect(end.lookX.truncatingRemainder(dividingBy: 2 * .pi) == 0)
    }

    @Test func trackEasesBetweenKeys() {
        let track = CatTrack(times: [0, 1, 2], values: [0, 10, 10], curves: [.linear])
        #expect(track.value(at: -1) == 0)
        #expect(track.value(at: 0.25) == 2.5)
        #expect(track.value(at: 1.5) == 10)
        #expect(track.value(at: 3) == 10)
    }
}
