import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

#if DEBUG
@Suite struct DesktopSwipeTests {
    @Test func trackedProgressPreservesReversalInBothEncodings() throws {
        for augmented in [false, true] {
            for natural in [false, true] {
                for right in [false, true] {
                    let sign = (right ? 1.0 : -1.0) * (augmented ? (natural ? -1 : 1) : 1)
                    var observed: [Double] = []
                    for progress in [0.0, 0.3, 1.2, 0.3, 0.0] {
                        let sample = try #require(DesktopSwipe.trackingEvents(
                            right: right, sample: .init(phase: .changed, progress: progress, velocity: 0),
                            augmented: augmented, natural: natural))
                        let event = try #require(sample.first)
                        #expect(sample.count == (augmented ? 2 : 1))
                        #expect(event.getIntegerValueField(DesktopSwipe.field(132)) == 2)
                        observed.append(event.getDoubleValueField(DesktopSwipe.field(124)) * sign)
                    }
                    for (actual, expected) in zip(observed, [0.0, 0.3, 1.2, 0.3, 0.0]) {
                        #expect(abs(actual - expected) < 0.000001)
                    }
                }
            }
        }
    }

    @Test func cancellationIsDistinctFromACommitAndCarriesNoFling() throws {
        let sample = try #require(DesktopSwipe.trackingEvents(
            right: true, sample: .init(phase: .cancelled, progress: 0, velocity: 0),
            augmented: true, natural: true))
        let event = try #require(sample.first)
        #expect(event.getIntegerValueField(DesktopSwipe.field(132)) == 8)
        #expect(event.getDoubleValueField(DesktopSwipe.field(129)) == 0)
        #expect(event.getIntegerValueField(.eventSourceUserData) == DesktopSwipe.tag)
        let data = try #require(event.data)
        let payloadTag = (data as Data).range(of: Data([0x10, 0x6D]))
        #expect(payloadTag != nil)
    }

    @Test func invalidSamplesCannotOverflowTheFixedPointPayload() {
        for (progress, velocity) in [(Double.nan, 0.0), (0.0, Double.infinity), (-0.1, 0), (2.1, 0), (0, 40_000)] {
            #expect(DesktopSwipe.trackingEvents(right: true, sample: .init(phase: .changed, progress: progress,
                                                                        velocity: velocity),
                                             augmented: true, natural: true) == nil)
        }
    }
}
#endif
