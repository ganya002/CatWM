@testable import CatWM
@testable import CatWMKit
import Testing

struct TrajectoryTests {
    private let spec = MotionSpec(duration: 0.2, curve: .easeOut, bounce: 0.5)

    @Test func withoutVelocityItFollowsTheCurve() {
        let trajectory = Trajectory(from: 0, to: 10, spec: spec)
        for time in stride(from: 0.0, through: 0.2, by: 0.02) {
            let expected = 10 * spec.curve.progress(time / 0.2, bounce: spec.bounce)
            #expect(abs(trajectory.value(at: time) - expected) < 1e-9)
        }
    }

    @Test func aTurnaroundLeavesAtTheInheritedVelocity() {
        let trajectory = Trajectory(from: 0.6, to: 0, spec: spec, velocity: 4)
        #expect(abs(trajectory.value(at: 0) - 0.6) < 1e-9)
        #expect(abs(trajectory.velocity(at: 0) - 4) < 0.5)
    }

    @Test func aTurnaroundKeepsMovingBeforeItComesBack() {
        let trajectory = Trajectory(from: 0.6, to: 0, spec: spec, velocity: 4)
        #expect(trajectory.value(at: 0.01) > 0.6)
        #expect(trajectory.value(at: 0.2) == 0)
        #expect(trajectory.velocity(at: 0.2) == 0)
    }

    @Test func theSpeedNeverJumpsDuringATurnaround() {
        let trajectory = Trajectory(from: 0.6, to: 0, spec: spec, velocity: 4)
        var previous = trajectory.velocity(at: 0)
        for time in stride(from: 0.002, to: 0.2, by: 0.002) {
            let speed = trajectory.velocity(at: time)
            #expect(abs(speed - previous) < 2.5)
            previous = speed
        }
    }

    @Test func aRestingStartIsInstantAtZeroDuration() {
        let trajectory = Trajectory(from: 1, to: 3, spec: .instant, velocity: 5)
        #expect(trajectory.value(at: 0) == 3)
    }

    @Test func retargetingKeepsTheCarriedVelocity() {
        let trajectory = Trajectory(from: 0.6, to: 0, spec: spec, velocity: 4)
        let same = trajectory.retargeted(to: 0)
        for time in stride(from: 0.0, through: 0.2, by: 0.02) {
            #expect(abs(same.value(at: time) - trajectory.value(at: time)) < 1e-12)
        }
    }
}
