import AudioToolbox
import AVFoundation
import CatWMKit

extension IntroScore {
    static func band(_ add: AddNote) {
        let span = Beat.impact - 0.25 - Beat.gather

        for (i, time) in Beat.arrive.enumerated() { add(time, .bass, [[Dn2, Dn2, An1, An1, Dn2][i]], 90, 0.4) }
        add(Beat.word, .bass, [Dn2], 96, 0.5)
        add(Beat.retile, .bass, [Gn1], 92, 0.45)
        add(Beat.retile + 0.5, .bass, [An1], 92, 0.45)
        for i in 0..<4 { add(Beat.gather + Double(i) * span / 4, .bass, [An1], 76 + UInt8(i * 5), 0.18) }
        add(Beat.impact, .bass, [Dn1, Dn2], 84, 2.4)

        add(Beat.arrive[0], .cello, [Dn3], 58, Beat.word - Beat.arrive[0])
        add(Beat.word, .cello, [Dn3], 70, Beat.retile - Beat.word)
        add(Beat.retile, .cello, [Gn2], 70, 0.5)
        add(Beat.retile + 0.5, .cello, [An2], 70, 0.5)
        add(Beat.gather, .cello, [An2, En3], 62, span)
        add(Beat.impact, .cello, [Dn2, Dn3], 70, 2.6)

        for (i, time) in Beat.arrive.enumerated() {
            add(time, .glockenspiel, [[Dn4, Fs4, An4, Dn5, Fs5][i] + 24], 70, 0.4)
        }
        add(Beat.word, .glockenspiel, [An6], 72, 0.5)
        add(Beat.impact + 0.05, .glockenspiel, [Dn6, An6], 76, 1.5)
        add(Beat.impact + 0.75, .glockenspiel, [Fs6 + 12], 56, 1.2)

        for (i, key) in [Dn4, Fs4, An4, Dn5, Fs5].enumerated() {
            add(Beat.word - 0.2 + Double(i) * 0.04, .harp, [key], 60 + UInt8(i * 3), 0.8)
        }
        let gliss: [UInt8] = [An3, Bn3, Cs4, Dn4, En4, Fs4, An4, Bn4, Cs5, Dn5, En5, Fs5, An5, Bn5, Dn6]
        for (i, key) in gliss.enumerated() {
            add(Beat.gather + span * Double(i) / Double(gliss.count), .harp, [key], 48 + UInt8(i * 3), 0.5)
        }
        for (i, key) in [Dn3, An3, Dn4, Fs4, An4, Dn5].enumerated() {
            add(Beat.impact + Double(i) * 0.03, .harp, [key], 62, 2)
        }

        add(Beat.word, .flute, [Fs5], 70, 0.5)
        add(Beat.word + 0.5, .flute, [En5], 64, 0.25)
        add(Beat.retile, .flute, [Dn5], 66, 0.5)
        add(Beat.retile + 0.5, .flute, [Cs5], 66, 0.5)
        add(Beat.gather, .flute, [En5], 56, span)
        add(Beat.impact, .flute, [Fs5], 76, 1.4)
        add(Beat.impact + 1.4, .flute, [Dn5], 62, 1.4)
    }

    static func drums(_ add: AddNote) {
        func hit(_ time: Double, _ keys: [UInt8], _ velocity: UInt8) { add(time, .drums, keys, velocity, 0.3) }

        hit(0.25, [hat], 40)
        for (i, time) in Beat.arrive.enumerated() {
            hit(time, !i.isMultiple(of: 2) ? [kick, snare] : [kick], 92)
            if i < Beat.arrive.count - 1 { hit(time + 0.25, [hat], 50) }
        }
        if let lastArrival = Beat.arrive.last { hit(lastArrival + 0.25, [openHat], 56) }

        hit(Beat.word, [kick, crash], 96)
        hit(Beat.word + 0.25, [hat], 46)
        hit(Beat.word + 0.5, [snare], 70)

        for (i, key) in [highTom, highTom, midTom, midTom, lowTom].enumerated() {
            hit(Beat.retile + Double(i) * Beat.step, [key], 84 - UInt8(i * 2))
        }
        hit(Beat.retile, [kick], 90)
        hit(Beat.retile + 0.5, [kick, ride], 84)

        let span = Beat.impact - 0.25 - Beat.gather
        var time = Beat.gather
        while time < Beat.gather + span - 0.01 {
            let progress = (time - Beat.gather) / span
            hit(time, [snare], 32 + UInt8(progress * 44))
            time += progress < 0.5 ? 0.125 : 0.0625
        }

        hit(Beat.impact, [kick, splash], 84)
        add(Beat.impact, .drums, [crash], 78, 2.5)
    }

    static var marimba: [Note] {
        var notes: [Note] = []
        func add(_ time: Double, _ voice: Voice, _ keys: [UInt8], _ velocity: UInt8, _ length: Double) {
            notes.append(Note(time: time, voice: voice, keys: keys, velocity: velocity, length: length))
        }
        func perc(_ time: Double, _ keys: [UInt8], _ velocity: UInt8) { add(time, .drums, keys, velocity, 0.3) }
        let span = Beat.impact - 0.25 - Beat.gather

        add(0, .marimba, [Dn4, An4], 72, 0.4)
        add(0.25, .marimba, [Fs5], 64, 0.3)
        perc(0.25, [shaker], 36)

        let snaps: [UInt8] = [Dn4, Fs4, An4, Dn5, Fs5], plucks: [UInt8] = [An5, Dn6, An5, Fs5]
        for (i, time) in Beat.arrive.enumerated() {
            add(time, .marimba, [snaps[i], snaps[i] + 12], 100, 0.4)
            add(time, .synthBass, [[Dn2, Dn2, An1, An1, Dn2][i]], 84, 0.22)
            perc(time, !i.isMultiple(of: 2) ? [sideStick, clap] : [sideStick], 70)
            perc(time + 0.125, [shaker], 34)
            perc(time + 0.375, [shaker], 34)
            if i < plucks.count {
                add(time + 0.25, .kalimba, [plucks[i]], 74, 0.25)
                perc(time + 0.25, [shaker], 46)
            }
        }

        add(Beat.word, .marimba, [Dn4, Fs4, An4, Dn5], 96, 0.5)
        add(Beat.word, .kalimba, [An5], 84, 0.3)
        add(Beat.word + 0.25, .kalimba, [Fs5], 72, 0.3)
        add(Beat.word, .synthBass, [Dn2], 92, 0.4)
        add(Beat.word, .pad, [Dn4, Fs4, An4], 44, 0.75)
        perc(Beat.word, [clap, tambourine], 76)
        perc(Beat.word + 0.5, [sideStick], 60)

        for (i, key) in [Dn6, An5, Fs5, Dn5, An4].enumerated() {
            let time = Beat.retile + Double(i) * Beat.step
            add(time, .marimba, [key], 90 - UInt8(i * 4), 0.2)
            perc(time, [claves], 62 - UInt8(i * 3))
        }
        add(Beat.retile, .synthBass, [Gn1], 88, 0.4)
        add(Beat.retile + 0.5, .synthBass, [An1], 88, 0.4)
        add(Beat.retile + 0.5, .kalimba, [Cs5, En5], 66, 0.3)

        let climb: [UInt8] = [An3, Dn4, En4, Fs4, An4, Bn4, Cs5, Dn5, En5, Fs5, An5, Bn5,
                              Cs5 + 12, Dn6, En5 + 12, Fs5 + 12]
        for (i, key) in climb.enumerated() {
            let progress = Double(i) / Double(climb.count)
            add(Beat.gather + span * (1 - pow(1 - progress, 1.4)), .marimba, [key], 58 + UInt8(i * 2), 0.15)
        }
        for i in 0..<12 { perc(Beat.gather + Double(i) * span / 12, [cabasa], 30 + UInt8(i * 4)) }
        add(Beat.gather, .pad, [An3, En4, An4, Cs5], 40, span)
        add(Beat.gather, .synthBass, [An1], 70, span)

        let chord: [UInt8] = [Dn3, An3, Dn4, Fs4, An4, Dn5]
        for repeatIndex in 0..<14 {
            let fade = 1 - Double(repeatIndex) / 14
            let keys = repeatIndex == 0 ? chord : [Dn4, An4, Dn5]
            add(Beat.impact + Double(repeatIndex) * 0.0625, .marimba, keys, UInt8(30 + 46 * fade), 0.2)
        }
        add(Beat.impact, .synthBass, [Dn2], 92, 1.6)
        add(Beat.impact, .pad, [Dn3, An3, Dn4, Fs4, An4], 58, 2.8)
        perc(Beat.impact, [36, clap, tambourine], 68)
        add(Beat.impact + 0.25, .kalimba, [Fs5 + 12], 66, 1)
        add(Beat.impact + 0.5, .kalimba, [An5 + 12], 60, 1)
        add(Beat.impact + 0.75, .kalimba, [Dn7], 58, 1.4)
        add(Beat.impact + 1.25, .marimba, [Dn6], 64, 0.8)
        return notes
    }
}
