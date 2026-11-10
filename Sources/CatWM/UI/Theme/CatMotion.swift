import CatWMKit
import Foundation

struct CatMotion: Equatable {
    var lift = 0.0
    var stretch = 1.0
    var lean = 0.0
    var lookX = 0.0
    var lookY = 0.0

    static func idle(at time: Double) -> Self {
        let wave = { (period: Double) in sin(2 * .pi * time / period) }
        return CatMotion(stretch: 1 + 0.012 * (1 - cos(2 * .pi * time / 3.4)), lean: 1.2 * wave(9),
                         lookX: 0.22 * wave(7.3) + 0.08 * wave(3.1), lookY: 0.12 * wave(5.7))
    }
}

struct CatTrack {
    enum Curve { case ease, easeIn, easeOut, linear }

    let times: [Double]
    let values: [Double]
    var curves: [Curve] = []

    var duration: Double { times.last ?? 0 }

    func value(at time: Double) -> Double {
        guard let first = values.first, let last = values.last else { return 0 }
        guard time > times[0] else { return first }
        guard let next = times.firstIndex(where: { $0 > time }) else { return last }
        let start = next - 1, span = times[next] - times[start]
        let progress = (time - times[start]) / span
        let eased = switch start < curves.count ? curves[start] : .ease {
        case .ease: progress * progress * (3 - 2 * progress)
        case .easeIn: progress * progress
        case .easeOut: 1 - (1 - progress) * (1 - progress)
        case .linear: progress
        }
        return values[start] + (values[next] - values[start]) * eased
    }
}

extension CatMove {
    private struct Tracks {
        var lift = CatTrack(times: [0], values: [0])
        var stretch = CatTrack(times: [0], values: [1])
        var lean = CatTrack(times: [0], values: [0])
        var lookX = CatTrack(times: [0], values: [0])
        var lookY = CatTrack(times: [0], values: [0])

        var all: [CatTrack] { [lift, stretch, lean, lookX, lookY] }
    }

    private var tracks: Tracks {
        switch self {
        case .hop:
            Tracks(lift: CatTrack(times: [0, 0.14, 0.35, 0.56, 0.66, 0.74], values: [0, 0, 0.22, 0, 0.03, 0],
                                  curves: [.linear, .easeOut, .easeIn, .easeOut, .easeIn]),
                   stretch: CatTrack(times: [0, 0.14, 0.22, 0.35, 0.56, 0.62, 0.74, 0.8, 0.92, 1.05],
                                     values: [1, 0.8, 1.16, 1, 1.06, 0.8, 0.94, 1.06, 0.98, 1]),
                   lookY: CatTrack(times: [0, 0.14, 0.35, 0.6, 0.9], values: [0, 0.2, -0.35, -0.1, 0]))
        case .spin:
            Tracks(lift: CatTrack(times: [0, 0.14, 0.4, 0.7, 0.78, 0.86], values: [0, 0, 0.14, 0, 0.02, 0],
                                  curves: [.linear, .easeOut, .easeIn, .easeOut, .easeIn]),
                   stretch: CatTrack(times: [0, 0.14, 0.24, 0.4, 0.7, 0.76, 0.88, 1.0],
                                     values: [1, 0.86, 1.08, 1, 1.03, 0.88, 1.03, 1]),
                   lookX: CatTrack(times: [0, 0.12, 0.75, 0.9], values: [0, -0.25, 2 * .pi + 0.12, 2 * .pi]))
        case .wiggle:
            Tracks(stretch: CatTrack(times: [0, 0.1, 0.3, 0.5, 0.8], values: [1, 0.92, 1.05, 0.98, 1]),
                   lean: CatTrack(times: [0, 0.1, 0.26, 0.42, 0.56, 0.68, 0.8], values: [0, 10, -10, 7, -4, 1.5, 0]),
                   lookX: CatTrack(times: [0, 0.1, 0.26, 0.42, 0.56, 0.8], values: [0, -0.35, 0.35, -0.25, 0.12, 0]))
        case .look:
            Tracks(stretch: CatTrack(times: [0, 0.2, 0.35, 1.1, 1.25, 1.9], values: [1, 1.03, 1, 1, 1.03, 1]),
                   lookX: CatTrack(times: [0, 0.3, 1.0, 1.35, 1.95, 2.3], values: [0, 0.75, 0.75, -0.7, -0.7, 0]),
                   lookY: CatTrack(times: [0, 0.3, 1.0, 1.35, 1.95, 2.3], values: [0, -0.5, -0.5, 0.15, 0.15, 0]))
        }
    }

    var duration: Double { tracks.all.map(\.duration).max() ?? 0 }

    func motion(at time: Double) -> CatMotion {
        let tracks = tracks
        return CatMotion(lift: tracks.lift.value(at: time), stretch: tracks.stretch.value(at: time),
                         lean: tracks.lean.value(at: time), lookX: tracks.lookX.value(at: time),
                         lookY: tracks.lookY.value(at: time))
    }
}
