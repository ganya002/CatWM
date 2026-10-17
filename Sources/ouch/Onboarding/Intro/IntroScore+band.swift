import AVFoundation
import AudioToolbox

extension IntroScore {
    static func band(_ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
        typealias B = Beat
        let span = B.impact - 0.25 - B.gather

        for (i, t) in B.arrive.enumerated() { add(t, .bass, [[D2, D2, A1, A1, D2][i]], 90, 0.4) }
        add(B.word, .bass, [D2], 96, 0.5)
        add(B.retile, .bass, [G1], 92, 0.45)
        add(B.retile + 0.5, .bass, [A1], 92, 0.45)
        for i in 0..<4 { add(B.gather + Double(i) * span / 4, .bass, [A1], 76 + UInt8(i * 5), 0.18) }
        add(B.impact, .bass, [D1, D2], 84, 2.4)

        add(B.arrive[0], .cello, [D3], 58, B.word - B.arrive[0])
        add(B.word, .cello, [D3], 70, B.retile - B.word)
        add(B.retile, .cello, [G2], 70, 0.5)
        add(B.retile + 0.5, .cello, [A2], 70, 0.5)
        add(B.gather, .cello, [A2, E3], 62, span)
        add(B.impact, .cello, [D2, D3], 70, 2.6)

        for (i, t) in B.arrive.enumerated() { add(t, .glockenspiel, [[D4, Fs4, A4, D5, Fs5][i] + 24], 70, 0.4) }
        add(B.word, .glockenspiel, [A6], 72, 0.5)
        add(B.impact + 0.05, .glockenspiel, [D6, A6], 76, 1.5)
        add(B.impact + 0.75, .glockenspiel, [Fs6 + 12], 56, 1.2)

        for (i, k) in [D4, Fs4, A4, D5, Fs5].enumerated() { add(B.word - 0.2 + Double(i) * 0.04, .harp, [k], 60 + UInt8(i * 3), 0.8) }
        let gliss: [UInt8] = [A3, B3, Cs4, D4, E4, Fs4, A4, B4, Cs5, D5, E5, Fs5, A5, B5, D6]
        for (i, k) in gliss.enumerated() {
            add(B.gather + span * Double(i) / Double(gliss.count), .harp, [k], 48 + UInt8(i * 3), 0.5)
        }
        for (i, k) in [D3, A3, D4, Fs4, A4, D5].enumerated() { add(B.impact + Double(i) * 0.03, .harp, [k], 62, 2) }

        add(B.word, .flute, [Fs5], 70, 0.5)
        add(B.word + 0.5, .flute, [E5], 64, 0.25)
        add(B.retile, .flute, [D5], 66, 0.5)
        add(B.retile + 0.5, .flute, [Cs5], 66, 0.5)
        add(B.gather, .flute, [E5], 56, span)
        add(B.impact, .flute, [Fs5], 76, 1.4)
        add(B.impact + 1.4, .flute, [D5], 62, 1.4)
    }

    static func drums(_ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
        typealias B = Beat
        func hit(_ at: Double, _ keys: [UInt8], _ vel: UInt8) { add(at, .drums, keys, vel, 0.3) }

        hit(0.25, [hat], 40)
        for (i, t) in B.arrive.enumerated() {
            hit(t, i % 2 == 1 ? [kick, snare] : [kick], 92)
            if i < B.arrive.count - 1 { hit(t + 0.25, [hat], 50) }
        }
        hit(B.arrive.last! + 0.25, [openHat], 56)

        hit(B.word, [kick, crash], 96)
        hit(B.word + 0.25, [hat], 46)
        hit(B.word + 0.5, [snare], 70)

        for (i, k) in [highTom, highTom, midTom, midTom, lowTom].enumerated() {
            hit(B.retile + Double(i) * B.step, [k], 84 - UInt8(i * 2))
        }
        hit(B.retile, [kick], 90)
        hit(B.retile + 0.5, [kick, ride], 84)

        let span = B.impact - 0.25 - B.gather
        var t = B.gather
        while t < B.gather + span - 0.01 {
            let f = (t - B.gather) / span
            hit(t, [snare], 32 + UInt8(f * 44))
            t += f < 0.5 ? 0.125 : 0.0625
        }

        hit(B.impact, [kick, splash], 84)
        add(B.impact, .drums, [crash], 78, 2.5)
    }

    static var marimba: [Note] {
        var n: [Note] = []
        func add(_ at: Double, _ v: Voice, _ keys: [UInt8], _ vel: UInt8, _ len: Double) {
            n.append(Note(at: at, voice: v, keys: keys, velocity: vel, length: len))
        }
        func perc(_ at: Double, _ keys: [UInt8], _ vel: UInt8) { add(at, .drums, keys, vel, 0.3) }
        typealias B = Beat
        let span = B.impact - 0.25 - B.gather

        add(0, .marimba, [D4, A4], 72, 0.4)
        add(0.25, .marimba, [Fs5], 64, 0.3)
        perc(0.25, [shaker], 36)

        let snaps: [UInt8] = [D4, Fs4, A4, D5, Fs5], plucks: [UInt8] = [A5, D6, A5, Fs5]
        for (i, t) in B.arrive.enumerated() {
            add(t, .marimba, [snaps[i], snaps[i] + 12], 100, 0.4)
            add(t, .synthBass, [[D2, D2, A1, A1, D2][i]], 84, 0.22)
            perc(t, i % 2 == 1 ? [sideStick, clap] : [sideStick], 70)
            perc(t + 0.125, [shaker], 34)
            perc(t + 0.375, [shaker], 34)
            if i < plucks.count {
                add(t + 0.25, .kalimba, [plucks[i]], 74, 0.25)
                perc(t + 0.25, [shaker], 46)
            }
        }

        add(B.word, .marimba, [D4, Fs4, A4, D5], 96, 0.5)
        add(B.word, .kalimba, [A5], 84, 0.3)
        add(B.word + 0.25, .kalimba, [Fs5], 72, 0.3)
        add(B.word, .synthBass, [D2], 92, 0.4)
        add(B.word, .pad, [D4, Fs4, A4], 44, 0.75)
        perc(B.word, [clap, tambourine], 76)
        perc(B.word + 0.5, [sideStick], 60)

        for (i, k) in [D6, A5, Fs5, D5, A4].enumerated() {
            let t = B.retile + Double(i) * B.step
            add(t, .marimba, [k], 90 - UInt8(i * 4), 0.2)
            perc(t, [claves], 62 - UInt8(i * 3))
        }
        add(B.retile, .synthBass, [G1], 88, 0.4)
        add(B.retile + 0.5, .synthBass, [A1], 88, 0.4)
        add(B.retile + 0.5, .kalimba, [Cs5, E5], 66, 0.3)

        let climb: [UInt8] = [A3, D4, E4, Fs4, A4, B4, Cs5, D5, E5, Fs5, A5, B5, Cs5 + 12, D6, E5 + 12, Fs5 + 12]
        for (i, k) in climb.enumerated() {
            let f = Double(i) / Double(climb.count)
            add(B.gather + span * (1 - pow(1 - f, 1.4)), .marimba, [k], 58 + UInt8(i * 2), 0.15)
        }
        for i in 0..<12 { perc(B.gather + Double(i) * span / 12, [cabasa], 30 + UInt8(i * 4)) }
        add(B.gather, .pad, [A3, E4, A4, Cs5], 40, span)
        add(B.gather, .synthBass, [A1], 70, span)

        let chord: [UInt8] = [D3, A3, D4, Fs4, A4, D5]
        for r in 0..<14 {
            let fade = 1 - Double(r) / 14
            add(B.impact + Double(r) * 0.0625, .marimba, r == 0 ? chord : [D4, A4, D5], UInt8(30 + 46 * fade), 0.2)
        }
        add(B.impact, .synthBass, [D2], 92, 1.6)
        add(B.impact, .pad, [D3, A3, D4, Fs4, A4], 58, 2.8)
        perc(B.impact, [36, clap, tambourine], 68)
        add(B.impact + 0.25, .kalimba, [Fs5 + 12], 66, 1)
        add(B.impact + 0.5, .kalimba, [A5 + 12], 60, 1)
        add(B.impact + 0.75, .kalimba, [D7], 58, 1.4)
        add(B.impact + 1.25, .marimba, [D6], 64, 0.8)
        return n
    }

}
