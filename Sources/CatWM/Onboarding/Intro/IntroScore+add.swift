import AudioToolbox
import AVFoundation
import CatWMKit

extension IntroScore {
    static var grand: [Note] {
        var notes: [Note] = []
        func add(_ time: Double, _ voice: Voice, _ keys: [UInt8], _ velocity: UInt8, _ length: Double) {
            notes.append(Note(time: time, voice: voice, keys: keys, velocity: velocity, length: length))
        }
        let span = Beat.impact - 0.25 - Beat.gather

        add(0, .piano, [Dn3, An3], 70, 0.5)
        add(0.25, .piano, [Fs4], 62, 0.25)
        add(0, .cello, [Dn2], 44, Beat.arrive[2])

        for (i, time) in Beat.arrive.enumerated() {
            let key = [Dn4, Fs4, An4, Dn5, Fs5][i]
            add(time, .piano, [key - 12, key], 100, 0.35)
            if i < Beat.arrive.count - 1 { add(time + 0.25, .piano, [An5], 44, 0.1) }
        }
        add(Beat.arrive[2], .cello, [An2], 52, Beat.word - Beat.arrive[2])
        for (i, key) in [An3, Dn4, Fs4].enumerated() {
            add(Beat.arrive[i + 2], .horns, [key], 46 + UInt8(i * 6), Beat.word - Beat.arrive[i + 2])
        }

        add(Beat.word, .piano, [Dn3, An3, Dn4, Fs4, An4], 90, 0.3)
        add(Beat.word, .piano, [An5], 72, 0.2)
        add(Beat.word + 0.25, .piano, [Fs5], 62, 0.2)
        add(Beat.word, .horns, [An3, An4], 72, 0.45)
        add(Beat.word + 0.5, .horns, [Dn4, Dn5], 76, Beat.retile - Beat.word - 0.5)
        add(Beat.word, .cello, [Dn2, Dn3], 66, Beat.retile - Beat.word)

        for (i, key) in [Dn6, An5, Fs5, Dn5, An4].enumerated() {
            add(Beat.retile + Double(i) * Beat.step, .piano, [key], 78 - UInt8(i * 4), 0.1)
        }
        add(Beat.retile, .cello, [Gn2, Dn3], 66, 0.5)
        add(Beat.retile, .horns, [Gn3, Dn4, Bn4], 60, 0.5)
        add(Beat.retile + 0.5, .cello, [An2, En3], 66, 0.5)
        add(Beat.retile + 0.5, .horns, [An3, En4, Cs5], 60, 0.5)

        let rise: [UInt8] = [An3, Dn4, En4, Fs4, An4, Bn4, Cs5, Dn5, En5, Fs5, An5, Bn5]
        for (i, key) in rise.enumerated() {
            add(Beat.gather + span * Double(i) / Double(rise.count), .piano, [key], 56 + UInt8(i * 3), 0.09)
        }
        add(Beat.gather, .cello, [An2, En3], 56, span / 2)
        add(Beat.gather + span / 2, .cello, [An2, En3], 70, span / 2 + 0.2)
        add(Beat.gather, .horns, [An3, En4], 50, span / 2)
        add(Beat.gather + span / 2, .horns, [An3, En4, An4], 66, span / 2 + 0.2)
        var time = Beat.gather
        while time < Beat.impact - 0.01 {
            let progress = (time - Beat.gather) / (Beat.impact - Beat.gather)
            add(time, .drums, [ride], 24 + UInt8(progress * 40), 0.2)
            time += 0.0625
        }
        add(Beat.impact - 1.45, .reverseCymbal, [60], 70, 1.45)

        for (i, key) in [Dn1, Dn2, An2, Dn3, Fs3, An3, Dn4, Fs4, An4, Dn5, Fs5, An5, Dn6].enumerated() {
            add(Beat.impact + Double(i) * 0.022, .piano, [key], 100 - UInt8(i * 2), 3.2)
        }
        add(Beat.impact, .horns, [Dn3, An3, Dn4, Fs4], 74, 2.4)
        add(Beat.impact, .cello, [Dn2, Dn3], 74, 2.6)
        add(Beat.impact, .drums, [crash], 70, 2.5)
        add(Beat.impact + 0.75, .piano, [Fs6], 56, 1.4)
        add(Beat.impact + 1.0, .piano, [An6], 50, 1.4)
        add(Beat.impact + 1.25, .piano, [Dn6], 54, 2.4)
        add(Beat.impact + 2.4, .horns, [Dn4], 44, 1.2)
        return notes
    }

    static func score(_ combo: Combo) -> [Note] {
        var notes: [Note] = []
        func add(_ time: Double, _ voice: Voice, _ keys: [UInt8], _ velocity: UInt8, _ length: Double) {
            notes.append(Note(time: time, voice: voice, keys: keys, velocity: velocity, length: length))
        }
        scoreArrival(combo, add)
        scoreWord(combo, add)
        scoreRetile(combo, add)
        scoreGather(combo, add)
        scoreImpact(combo, add)
        rhythm(combo.rhythm, add)
        for accentKind in combo.accents { accent(accentKind, add) }
        return notes
    }

    private static func scoreArrival(_ combo: Combo, _ add: AddNote) {
        let lead = combo.lead
        add(0, lead, [Dn3, An3], 70, 0.5)
        add(0.25, lead, [Fs4], 62, 0.25)

        for (i, time) in Beat.arrive.enumerated() {
            let key = [Dn4, Fs4, An4, Dn5, Fs5][i]
            add(time, lead, [key - 12, key], 100, 0.35)
            if let sparkle = combo.sparkle { add(time, sparkle, [key + 24], 64, 0.4) }
            if i < Beat.arrive.count - 1 {
                if let pluck = combo.pluck {
                    add(time + 0.25, pluck, [[An5, Dn6, An5, Fs5][i]], 72, 0.25)
                } else {
                    add(time + 0.25, lead, [An5], 44, 0.1)
                }
            }
            if let bass = combo.bass { add(time, bass, [[Dn2, Dn2, An1, An1, Dn2][i]], 86, 0.4) }
        }
        if let pad = combo.pad {
            add(Beat.arrive[0], pad, [Dn3, An3, Dn4], 44, Beat.arrive[2] - Beat.arrive[0])
            add(Beat.arrive[2], pad, [An2, En3, An3, Cs4], 50, Beat.word - Beat.arrive[2])
        }
    }

    private static func scoreWord(_ combo: Combo, _ add: AddNote) {
        let hook = combo.pluck ?? combo.lead
        add(Beat.word, combo.lead, [Dn3, An3, Dn4, Fs4, An4], 90, 0.3)
        add(Beat.word, hook, [An5], 76, 0.25)
        add(Beat.word + 0.25, hook, [Fs5], 66, 0.25)
        if let sparkle = combo.sparkle { add(Beat.word, sparkle, [An6], 68, 0.5) }
        if let bass = combo.bass { add(Beat.word, bass, [Dn2], 92, 0.5) }
        if let pad = combo.pad { add(Beat.word, pad, [Dn3, Fs3, An3, Dn4], 58, Beat.retile - Beat.word) }
    }

    private static func scoreRetile(_ combo: Combo, _ add: AddNote) {
        for (i, key) in [Dn6, An5, Fs5, Dn5, An4].enumerated() {
            add(Beat.retile + Double(i) * Beat.step, combo.lead, [key], 80 - UInt8(i * 4), 0.12)
        }
        if let bass = combo.bass {
            add(Beat.retile, bass, [Gn1], 88, 0.45)
            add(Beat.retile + 0.5, bass, [An1], 88, 0.45)
        }
        if let pad = combo.pad {
            add(Beat.retile, pad, [Gn2, Dn3, Gn3, Bn3], 56, 0.5)
            add(Beat.retile + 0.5, pad, [An2, En3, An3, Cs4], 56, 0.5)
        }
    }

    private static func scoreGather(_ combo: Combo, _ add: AddNote) {
        let span = Beat.impact - 0.25 - Beat.gather
        let rise: [UInt8] = [An3, Dn4, En4, Fs4, An4, Bn4, Cs5, Dn5, En5, Fs5, An5, Bn5]
        for (i, key) in rise.enumerated() {
            add(Beat.gather + span * Double(i) / Double(rise.count), combo.lead, [key], 56 + UInt8(i * 3), 0.09)
        }
        if let pad = combo.pad {
            add(Beat.gather, pad, [An3, En4, An4], 48, span / 2)
            add(Beat.gather + span / 2, pad, [An3, En4, An4, Cs5], 64, span / 2 + 0.2)
        }
        if let bass = combo.bass {
            for i in 0..<4 { add(Beat.gather + Double(i) * span / 4, bass, [An1], 74 + UInt8(i * 5), 0.18) }
        }
    }

    private static func scoreImpact(_ combo: Combo, _ add: AddNote) {
        let high = combo.sparkle ?? combo.lead
        for (i, key) in [Dn2, An2, Dn3, Fs3, An3, Dn4, Fs4, An4, Dn5, Fs5, An5, Dn6].enumerated() {
            add(Beat.impact + Double(i) * 0.022, combo.lead, [key], 98 - UInt8(i * 2), 3)
        }
        if let bass = combo.bass { add(Beat.impact, bass, [Dn1, Dn2], 84, 2.4) }
        if let pad = combo.pad { add(Beat.impact, pad, [Dn3, An3, Dn4, Fs4], 60, 2.8) }
        if let sparkle = combo.sparkle { add(Beat.impact + 0.05, sparkle, [Dn6, An6], 70, 1.5) }
        add(Beat.impact + 0.75, high, [Fs6], 56, 1.4)
        add(Beat.impact + 1.0, high, [An6], 50, 1.4)
        add(Beat.impact + 1.25, high, [Dn6], 54, 2.4)
    }
}
