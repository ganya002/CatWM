import AudioToolbox
import AVFoundation
import CatWMKit

extension IntroScore {
    static func rhythm(_ rhythm: Rhythm, _ add: AddNote) {
        let kit = rhythm == .brushes ? brushKit : Voice.drums
        func hit(_ time: Double, _ keys: [UInt8], _ velocity: UInt8) { add(time, kit, keys, velocity, 0.3) }
        switch rhythm {
        case .none:
            return
        case .kit:
            drums(add)
            return
        case .brushes:
            for (i, time) in Beat.arrive.enumerated() {
                hit(time, !i.isMultiple(of: 2) ? [kick, snare] : [kick], 62)
                hit(time + 0.25, [hat], 38)
            }
            hit(Beat.word, [kick, snare], 70)
            hit(Beat.retile, [kick], 64)
            hit(Beat.retile + 0.5, [snare], 60)
        case .light:
            for (i, time) in Beat.arrive.enumerated() {
                hit(time, !i.isMultiple(of: 2) ? [sideStick, clap] : [sideStick], 66)
                hit(time + 0.25, [shaker], 44)
            }
            hit(Beat.word, [clap, tambourine], 72)
            for i in 0..<5 { hit(Beat.retile + Double(i) * Beat.step, [claves], 60 - UInt8(i * 3)) }
            let span = Beat.impact - 0.25 - Beat.gather
            for i in 0..<12 { hit(Beat.gather + Double(i) * span / 12, [cabasa], 30 + UInt8(i * 4)) }
        case .claps:
            for (i, time) in Beat.arrive.enumerated() where !i.isMultiple(of: 2) { hit(time, [clap], 74) }
            hit(Beat.word, [clap, tambourine], 76)
            hit(Beat.retile + 0.5, [clap], 70)
        case .softKick:
            for time in Beat.arrive { hit(time, [kick], 70) }
            hit(Beat.word, [kick], 76)
            hit(Beat.retile, [kick], 70)
        }
        hit(Beat.impact, [kick, crash], 72)
    }

    static func accent(_ accent: Accent, _ add: AddNote) {
        let span = Beat.impact - 0.25 - Beat.gather
        switch accent {
        case .timpani:
            for i in 0..<12 { add(Beat.gather + Double(i) * span / 12, .timpani, [An2], 34 + UInt8(i * 4), 0.07) }
            add(Beat.word, .timpani, [Dn2], 64, 0.6)
            add(Beat.impact, .timpani, [Dn2], 74, 1.2)
        case .taiko:
            add(Beat.word, taiko, [Dn2], 78, 0.6)
            for i in 0..<4 { add(Beat.gather + Double(i) * span / 4, taiko, [An1], 50 + UInt8(i * 8), 0.3) }
            add(Beat.impact, taiko, [Dn2], 88, 1.2)
        case .swell:
            var time = Beat.gather
            while time < Beat.impact - 0.01 {
                add(time, .drums, [ride], 24 + UInt8((time - Beat.gather) / (Beat.impact - Beat.gather) * 40), 0.2)
                time += 0.0625
            }
            add(Beat.impact - 1.45, .reverseCymbal, [60], 70, 1.45)
            add(Beat.impact, .drums, [crash], 68, 2.5)
        case .sub:
            add(Beat.impact - 1.45, .reverseCymbal, [60], 64, 1.45)
            add(Beat.impact, Voice.synthBass.at(0.8), [Dn1], 100, 2.2)
        case .crash:
            add(Beat.impact, .drums, [crash], 70, 2.5)
        }
    }
}
