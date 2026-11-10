import CatWMKit
import Foundation

struct CatFrame {
    var pose: CatPose
    var lid = 0.0
    var motion = CatMotion()
}

final class CatPuppet {
    var idleBlinks = true
    var gaze: CGVector?
    private var gazeValue = CGVector.zero
    private var lastFrame: Double?
    private(set) var feeling: CatFeeling
    private let born: Double
    private var from: CatPose, transitionStart: Double?
    private var move: CatMove?, moveStart = 0.0
    private var blinkStart: Double?, blinkTwice = false
    private var nextBlink: Double

    init(feeling: CatFeeling, at time: Double) {
        self.feeling = feeling
        from = feeling.pose
        born = time
        nextBlink = time + Double.random(in: 1.5...4)
    }

    func show(_ next: CatFeeling, at time: Double) {
        guard next != feeling else { return }
        from = pose(at: time)
        feeling = next
        transitionStart = time
    }

    func play(_ next: CatMove, at time: Double) {
        move = next
        moveStart = time
    }

    func blink(twice: Bool, at time: Double) {
        guard feeling.blinkSpeed != nil else { return }
        blinkStart = time
        blinkTwice = twice
    }

    func frame(at now: Double) -> CatFrame {
        if idleBlinks, now >= nextBlink {
            blink(twice: Double.random(in: 0...1) < 0.18, at: now)
            nextBlink = now + Double.random(in: 2.4...6.2)
        }
        var motion = CatMotion.idle(at: now - born)
        let step = min(0.05, now - (lastFrame ?? now))
        lastFrame = now
        let target = gaze ?? .zero, ease = 1 - exp(-step * 14)
        gazeValue.dx += (target.dx - gazeValue.dx) * ease
        gazeValue.dy += (target.dy - gazeValue.dy) * ease
        motion.lookX += gazeValue.dx
        motion.lookY += gazeValue.dy
        if let move, now - moveStart < move.duration {
            let played = move.motion(at: now - moveStart)
            motion.lift = played.lift
            motion.stretch *= played.stretch
            motion.lean += played.lean
            motion.lookX += played.lookX
            motion.lookY += played.lookY
        }
        return CatFrame(pose: pose(at: now), lid: lid(at: now), motion: motion)
    }

    private func pose(at time: Double) -> CatPose {
        guard let start = transitionStart, time - start < feeling.spring.settlingDuration else { return feeling.pose }
        var delta = feeling.pose - from
        delta.scale(by: feeling.spring.value(target: 1.0, time: max(0, time - start)))
        return from + delta
    }

    private static let blinkLength = 0.25

    private func lid(at time: Double) -> Double {
        guard let start = blinkStart else { return 0 }
        let speed = feeling.blinkSpeed ?? 1, length = Self.blinkLength * speed, gap = 0.07 * speed
        let elapsed = time - start
        let local = blinkTwice && elapsed > length + gap ? elapsed - length - gap : elapsed
        func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
        switch local / speed {
        case ..<0: return 0
        case let shut where shut < 0.07: return smooth(shut / 0.07)
        case ..<0.11: return 1
        case let opening where opening < Self.blinkLength: return 1 - smooth((opening - 0.11) / 0.14)
        default: return 0
        }
    }
}
