import AVFoundation
import AudioToolbox

extension IntroScore {
    static var grand: [Note] {
        var n: [Note] = []
        func add(_ at: Double, _ v: Voice, _ keys: [UInt8], _ vel: UInt8, _ len: Double) {
            n.append(Note(at: at, voice: v, keys: keys, velocity: vel, length: len))
        }
        typealias B = Beat
        let span = B.impact - 0.25 - B.gather

        add(0, .piano, [D3, A3], 70, 0.5)
        add(0.25, .piano, [Fs4], 62, 0.25)
        add(0, .cello, [D2], 44, B.arrive[2])

        for (i, t) in B.arrive.enumerated() {
            let k = [D4, Fs4, A4, D5, Fs5][i]
            add(t, .piano, [k - 12, k], 100, 0.35)
            if i < B.arrive.count - 1 { add(t + 0.25, .piano, [A5], 44, 0.1) }
        }
        add(B.arrive[2], .cello, [A2], 52, B.word - B.arrive[2])
        for (i, k) in [A3, D4, Fs4].enumerated() {
            add(B.arrive[i + 2], .horns, [k], 46 + UInt8(i * 6), B.word - B.arrive[i + 2])
        }

        add(B.word, .piano, [D3, A3, D4, Fs4, A4], 90, 0.3)
        add(B.word, .piano, [A5], 72, 0.2)
        add(B.word + 0.25, .piano, [Fs5], 62, 0.2)
        add(B.word, .horns, [A3, A4], 72, 0.45)
        add(B.word + 0.5, .horns, [D4, D5], 76, B.retile - B.word - 0.5)
        add(B.word, .cello, [D2, D3], 66, B.retile - B.word)

        for (i, k) in [D6, A5, Fs5, D5, A4].enumerated() {
            add(B.retile + Double(i) * B.step, .piano, [k], 78 - UInt8(i * 4), 0.1)
        }
        add(B.retile, .cello, [G2, D3], 66, 0.5)
        add(B.retile, .horns, [G3, D4, B4], 60, 0.5)
        add(B.retile + 0.5, .cello, [A2, E3], 66, 0.5)
        add(B.retile + 0.5, .horns, [A3, E4, Cs5], 60, 0.5)

        let rise: [UInt8] = [A3, D4, E4, Fs4, A4, B4, Cs5, D5, E5, Fs5, A5, B5]
        for (i, k) in rise.enumerated() {
            add(B.gather + span * Double(i) / Double(rise.count), .piano, [k], 56 + UInt8(i * 3), 0.09)
        }
        add(B.gather, .cello, [A2, E3], 56, span / 2)
        add(B.gather + span / 2, .cello, [A2, E3], 70, span / 2 + 0.2)
        add(B.gather, .horns, [A3, E4], 50, span / 2)
        add(B.gather + span / 2, .horns, [A3, E4, A4], 66, span / 2 + 0.2)
        var t = B.gather
        while t < B.impact - 0.01 {
            let f = (t - B.gather) / (B.impact - B.gather)
            add(t, .drums, [ride], 24 + UInt8(f * 40), 0.2)
            t += 0.0625
        }
        add(B.impact - 1.45, .reverseCymbal, [60], 70, 1.45)

        for (i, k) in [D1, D2, A2, D3, Fs3, A3, D4, Fs4, A4, D5, Fs5, A5, D6].enumerated() {
            add(B.impact + Double(i) * 0.022, .piano, [k], 100 - UInt8(i * 2), 3.2)
        }
        add(B.impact, .horns, [D3, A3, D4, Fs4], 74, 2.4)
        add(B.impact, .cello, [D2, D3], 74, 2.6)
        add(B.impact, .drums, [crash], 70, 2.5)
        add(B.impact + 0.75, .piano, [Fs6], 56, 1.4)
        add(B.impact + 1.0, .piano, [A6], 50, 1.4)
        add(B.impact + 1.25, .piano, [D6], 54, 2.4)
        add(B.impact + 2.4, .horns, [D4], 44, 1.2)
        return n
    }

    static func score(_ c: Combo) -> [Note] {
        var n: [Note] = []
        func add(_ at: Double, _ v: Voice, _ keys: [UInt8], _ vel: UInt8, _ len: Double) {
            n.append(Note(at: at, voice: v, keys: keys, velocity: vel, length: len))
        }
        typealias B = Beat
        let span = B.impact - 0.25 - B.gather
        let lead = c.lead, hook = c.pluck ?? c.lead, high = c.sparkle ?? c.lead

        add(0, lead, [D3, A3], 70, 0.5)
        add(0.25, lead, [Fs4], 62, 0.25)

        for (i, t) in B.arrive.enumerated() {
            let k = [D4, Fs4, A4, D5, Fs5][i]
            add(t, lead, [k - 12, k], 100, 0.35)
            if let s = c.sparkle { add(t, s, [k + 24], 64, 0.4) }
            if i < B.arrive.count - 1 {
                if let p = c.pluck { add(t + 0.25, p, [[A5, D6, A5, Fs5][i]], 72, 0.25) } else { add(t + 0.25, lead, [A5], 44, 0.1) }
            }
            if let b = c.bass { add(t, b, [[D2, D2, A1, A1, D2][i]], 86, 0.4) }
        }
        if let p = c.pad {
            add(B.arrive[0], p, [D3, A3, D4], 44, B.arrive[2] - B.arrive[0])
            add(B.arrive[2], p, [A2, E3, A3, Cs4], 50, B.word - B.arrive[2])
        }

        add(B.word, lead, [D3, A3, D4, Fs4, A4], 90, 0.3)
        add(B.word, hook, [A5], 76, 0.25)
        add(B.word + 0.25, hook, [Fs5], 66, 0.25)
        if let s = c.sparkle { add(B.word, s, [A6], 68, 0.5) }
        if let b = c.bass { add(B.word, b, [D2], 92, 0.5) }
        if let p = c.pad { add(B.word, p, [D3, Fs3, A3, D4], 58, B.retile - B.word) }

        for (i, k) in [D6, A5, Fs5, D5, A4].enumerated() {
            add(B.retile + Double(i) * B.step, lead, [k], 80 - UInt8(i * 4), 0.12)
        }
        if let b = c.bass {
            add(B.retile, b, [G1], 88, 0.45)
            add(B.retile + 0.5, b, [A1], 88, 0.45)
        }
        if let p = c.pad {
            add(B.retile, p, [G2, D3, G3, B3], 56, 0.5)
            add(B.retile + 0.5, p, [A2, E3, A3, Cs4], 56, 0.5)
        }

        let rise: [UInt8] = [A3, D4, E4, Fs4, A4, B4, Cs5, D5, E5, Fs5, A5, B5]
        for (i, k) in rise.enumerated() {
            add(B.gather + span * Double(i) / Double(rise.count), lead, [k], 56 + UInt8(i * 3), 0.09)
        }
        if let p = c.pad {
            add(B.gather, p, [A3, E4, A4], 48, span / 2)
            add(B.gather + span / 2, p, [A3, E4, A4, Cs5], 64, span / 2 + 0.2)
        }
        if let b = c.bass { for i in 0..<4 { add(B.gather + Double(i) * span / 4, b, [A1], 74 + UInt8(i * 5), 0.18) } }

        for (i, k) in [D2, A2, D3, Fs3, A3, D4, Fs4, A4, D5, Fs5, A5, D6].enumerated() {
            add(B.impact + Double(i) * 0.022, lead, [k], 98 - UInt8(i * 2), 3)
        }
        if let b = c.bass { add(B.impact, b, [D1, D2], 84, 2.4) }
        if let p = c.pad { add(B.impact, p, [D3, A3, D4, Fs4], 60, 2.8) }
        if let s = c.sparkle { add(B.impact + 0.05, s, [D6, A6], 70, 1.5) }
        add(B.impact + 0.75, high, [Fs6], 56, 1.4)
        add(B.impact + 1.0, high, [A6], 50, 1.4)
        add(B.impact + 1.25, high, [D6], 54, 2.4)

        rhythm(c.rhythm, add)
        for a in c.accents { accent(a, add) }
        return n
    }

}
