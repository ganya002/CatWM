import CatWMKit
import SwiftUI

struct CatEye {
    var x: Double
    var y: Double
    var tilt: Double
    var chord: Double
    var rise: Double
    var width: Double
}

struct CatPose: VectorArithmetic {
    var values: SIMD16<Double>

    init(left: CatEye, right: CatEye) {
        values = SIMD16(left.x, left.y, left.tilt, left.chord, left.rise, left.width,
                        right.x, right.y, right.tilt, right.chord, right.rise, right.width, 0, 0, 0, 0)
    }

    private init(values: SIMD16<Double>) { self.values = values }

    var eyes: [CatEye] {
        [0, 6].map { i in
            CatEye(x: values[i], y: values[i + 1], tilt: values[i + 2],
                   chord: values[i + 3], rise: values[i + 4], width: values[i + 5])
        }
    }

    static var zero: Self { Self(values: .zero) }
    static func + (lhs: Self, rhs: Self) -> Self { Self(values: lhs.values + rhs.values) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(values: lhs.values - rhs.values) }
    mutating func scale(by rhs: Double) { values *= rhs }
    var magnitudeSquared: Double { (values * values).sum() }
}

struct CatShape: Shape {
    var pose: CatPose
    var lid = 0.0
    var look = CGVector.zero

    var animatableData: AnimatablePair<CatPose, Double> {
        get { AnimatablePair(pose, lid) }
        set { (pose, lid) = (newValue.first, newValue.second) }
    }

    static let aspectRatio = bodyBounds.width / bodyBounds.height

    static let body: Path = {
        let points: [CGFloat] = [
            231, 42, 234, 31, 245, 29, 250, 36, 268, 60, 294, 90, 310, 104, 330, 116, 356, 108, 384, 92,
            408, 78, 430, 60, 444, 40, 449, 33, 458, 38, 455, 50, 448, 84, 438, 112, 430, 136,
            408, 206, 368, 300, 356, 340, 348, 368, 398, 408, 399, 452, 400, 484, 372, 506, 330, 506,
            250, 508, 150, 508, 96, 496, 60, 488, 40, 450, 52, 400, 70, 326, 167, 264, 178, 226,
            194, 165, 212, 103, 231, 42
        ]
        var path = Path()
        path.move(to: CGPoint(x: points[0], y: points[1]))
        for i in stride(from: 2, to: points.count, by: 6) {
            path.addCurve(to: CGPoint(x: points[i + 4], y: points[i + 5]),
                          control1: CGPoint(x: points[i], y: points[i + 1]),
                          control2: CGPoint(x: points[i + 2], y: points[i + 3]))
        }
        path.closeSubpath()
        return path
    }()

    static let bodyBounds = body.boundingRect

    var eyes: Path {
        var eyes = Path()
        for eye in pose.eyes.map(closed) {
            guard let turn = turned(eye) else { continue }
            if eye.chord < 1 {
                let radius = max(0.25, eye.width / 2)
                let dot = CGRect(x: eye.x - radius, y: eye.y - radius, width: 2 * radius, height: 2 * radius)
                eyes.addPath(Path(ellipseIn: dot), transform: turn)
            } else {
                eyes.addPath(Self.arc(eye).strokedPath(StrokeStyle(lineWidth: max(0.5, eye.width), lineCap: .round)),
                             transform: turn)
            }
        }
        return eyes
    }

    private static let head = CGPoint(x: 302, y: 184), headRadius = 118.0

    private func turned(_ eye: CatEye) -> CGAffineTransform? {
        let restX = asin(max(-1, min(1, (eye.x - Self.head.x) / Self.headRadius)))
        let restY = asin(max(-1, min(1, (eye.y - Self.head.y) / Self.headRadius)))
        let angleX = remainder(restX + look.dx, 2 * .pi), angleY = restY + look.dy
        guard abs(angleX) < .pi / 2, abs(angleY) < .pi / 2 else { return nil }
        return CGAffineTransform(translationX: Self.head.x + Self.headRadius * sin(angleX),
                                 y: Self.head.y + Self.headRadius * sin(angleY))
            .scaledBy(x: cos(angleX) / cos(restX), y: cos(angleY) / cos(restY))
            .translatedBy(x: -eye.x, y: -eye.y)
    }

    func path(in rect: CGRect) -> Path {
        let bounds = Self.bodyBounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return Self.body.subtracting(eyes).applying(transform)
    }

    private func closed(_ eye: CatEye) -> CatEye {
        guard lid > 0 else { return eye }
        func mix(_ open: Double, _ shut: Double) -> Double { open + (shut - open) * lid }
        return CatEye(x: eye.x, y: mix(eye.y, eye.y + 2), tilt: eye.tilt,
                      chord: mix(eye.chord, max(eye.chord, 24) * 0.92), rise: mix(eye.rise, eye.rise * -0.15),
                      width: mix(eye.width, min(eye.width, 12)))
    }

    private static func arc(_ eye: CatEye) -> Path {
        let angle = eye.tilt * .pi / 180, along = CGVector(dx: cos(angle), dy: sin(angle))
        let half = max(0.01, eye.chord) / 2, bow = eye.rise * 1.33
        func point(_ distance: Double, _ lift: Double) -> CGPoint {
            CGPoint(x: eye.x + along.dx * distance + along.dy * lift, y: eye.y + along.dy * distance - along.dx * lift)
        }
        var path = Path()
        path.move(to: point(-half, 0))
        path.addCurve(to: point(half, 0), control1: point(-half * 0.55, bow), control2: point(half * 0.55, bow))
        return path
    }
}
