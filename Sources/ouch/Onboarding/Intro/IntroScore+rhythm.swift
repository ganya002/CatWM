import AVFoundation
import AudioToolbox

extension IntroScore {
    static func rhythm(_ r: Combo.Rhythm, _ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
        typealias B = Beat
        let kit = r == .brushes ? brushKit : Voice.drums
        func hit(_ at: Double, _ keys: [UInt8], _ vel: UInt8) { add(at, kit, keys, vel, 0.3) }
        switch r {
        case .none:
            return
        case .kit:
            drums(add)
            return
        case .brushes:
            for (i, t) in B.arrive.enumerated() {
                hit(t, i % 2 == 1 ? [kick, snare] : [kick], 62)
                hit(t + 0.25, [hat], 38)
            }
            hit(B.word, [kick, snare], 70)
            hit(B.retile, [kick], 64)
            hit(B.retile + 0.5, [snare], 60)
        case .light:
            for (i, t) in B.arrive.enumerated() {
                hit(t, i % 2 == 1 ? [sideStick, clap] : [sideStick], 66)
                hit(t + 0.25, [shaker], 44)
            }
            hit(B.word, [clap, tambourine], 72)
            for i in 0..<5 { hit(B.retile + Double(i) * B.step, [claves], 60 - UInt8(i * 3)) }
            for i in 0..<12 { hit(B.gather + Double(i) * (B.impact - 0.25 - B.gather) / 12, [cabasa], 30 + UInt8(i * 4)) }
        case .claps:
            for (i, t) in B.arrive.enumerated() where i % 2 == 1 { hit(t, [clap], 74) }
            hit(B.word, [clap, tambourine], 76)
            hit(B.retile + 0.5, [clap], 70)
        case .softKick:
            for t in B.arrive { hit(t, [kick], 70) }
            hit(B.word, [kick], 76)
            hit(B.retile, [kick], 70)
        }
        hit(B.impact, [kick, crash], 72)
    }

    static func accent(_ a: Combo.Accent, _ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
        typealias B = Beat
        let span = B.impact - 0.25 - B.gather
        switch a {
        case .timpani:
            for i in 0..<12 { add(B.gather + Double(i) * span / 12, .timpani, [A2], 34 + UInt8(i * 4), 0.07) }
            add(B.word, .timpani, [D2], 64, 0.6)
            add(B.impact, .timpani, [D2], 74, 1.2)
        case .taiko:
            add(B.word, taiko, [D2], 78, 0.6)
            for i in 0..<4 { add(B.gather + Double(i) * span / 4, taiko, [A1], 50 + UInt8(i * 8), 0.3) }
            add(B.impact, taiko, [D2], 88, 1.2)
        case .swell:
            var t = B.gather
            while t < B.impact - 0.01 {
                add(t, .drums, [ride], 24 + UInt8((t - B.gather) / (B.impact - B.gather) * 40), 0.2)
                t += 0.0625
            }
            add(B.impact - 1.45, .reverseCymbal, [60], 70, 1.45)
            add(B.impact, .drums, [crash], 68, 2.5)
        case .sub:
            add(B.impact - 1.45, .reverseCymbal, [60], 64, 1.45)
            add(B.impact, Voice.synthBass.at(0.8), [D1], 100, 2.2)
        case .crash:
            add(B.impact, .drums, [crash], 70, 2.5)
        }
    }
}
