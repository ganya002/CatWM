import CoreGraphics
import QuartzCore

extension Animator {
    package struct Item {
        package let move: Move
        package let start: CFTimeInterval
        package let duration: Double
        package let tracks: [Trajectory]

        package init(move: Move, from: CGRect, start: CFTimeInterval, spec: MotionSpec, velocity: [Double]? = nil) {
            self.move = move
            self.start = start
            duration = spec.duration
            let target = move.target
            let pairs = [(from.minX, target.minX), (from.minY, target.minY),
                         (from.width, target.width), (from.height, target.height)]
            tracks = pairs.enumerated().map { index, pair in
                Trajectory(from: pair.0, to: pair.1, spec: spec, velocity: velocity?[index])
            }
        }

        package init(move: Move, tracks: [Trajectory], start: CFTimeInterval, duration: Double) {
            self.move = move
            self.start = start
            self.duration = duration
            self.tracks = tracks
        }
    }
}

extension Animator.Item {
    package func frame(at now: CFTimeInterval, aligned: Bool = true) -> CGRect {
        let elapsed = now - start
        let values = tracks.map { $0.value(at: elapsed) }
        let frame = CGRect(x: values[0], y: values[1], width: max(1, values[2]), height: max(1, values[3]))
        return aligned ? frame.pixelAligned : frame
    }

    package func velocity(at now: CFTimeInterval) -> [Double] {
        tracks.map { $0.velocity(at: now - start) }
    }
}
