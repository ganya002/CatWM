import AVFoundation
import AudioToolbox

final class IntroScore {
    struct Voice: Hashable {
        let program: UInt8
        var kit = false
        var volume: Float = 1

        static let piano = Voice(program: 0)
        static let pizzicato = Voice(program: 45, volume: 0.55)
        static let timpani = Voice(program: 47, volume: 0.45)
        static let strings = Voice(program: 48, volume: 0.4)
        static let drums = Voice(program: 0, kit: true, volume: 0.6)
        static let bass = Voice(program: 32, volume: 0.7)
        static let cello = Voice(program: 42, volume: 0.4)
        static let harp = Voice(program: 46, volume: 0.5)
        static let flute = Voice(program: 73, volume: 0.4)
        static let glockenspiel = Voice(program: 9, volume: 0.3)
        static let marimba = Voice(program: 12)
        static let kalimba = Voice(program: 108, volume: 0.45)
        static let synthBass = Voice(program: 38, volume: 0.55)
        static let pad = Voice(program: 89, volume: 0.35)
        static let horns = Voice(program: 60, volume: 0.5)
        static let reverseCymbal = Voice(program: 119, volume: 0.4)

        func at(_ volume: Float) -> Voice { Voice(program: program, kit: kit, volume: volume) }
    }

    struct Arrangement: Identifiable {
        let id: String
        let name: String
        let blurb: String
        let notes: () -> [Note]

        static func named(_ id: String) -> Arrangement? { all.first { $0.id == id } }
        static var standard: Arrangement { named("1")! }
    }

    struct Note {
        let at: Double
        let voice: Voice
        let keys: [UInt8]
        let velocity: UInt8
        let length: Double
    }

    enum Beat {
        static let arrive: [Double] = [0.5, 1.0, 1.5, 2.0, 2.5]
        static let word = 3.0
        static let retile = 3.75
        static let step = 0.125
        static let gather = 4.75
        static let impact = 5.75
    }

    private static let soundBank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var samplers: [Voice: AVAudioUnitSampler] = [:]
    private let queue = DispatchQueue(label: "ouch.intro.score", qos: .userInteractive)
    private var pending: [DispatchWorkItem] = []
    private var keepAlive: IntroScore?
    private var ready = false
    private let notes: [Note]

    init(_ arrangement: Arrangement = .standard) {
        notes = arrangement.notes()
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 22
        let band = AVAudioMixerNode()
        engine.attach(band)
        engine.attach(reverb)
        engine.connect(band, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        for v in Set(notes.map(\.voice)) {
            let s = AVAudioUnitSampler()
            engine.attach(s)
            engine.connect(s, to: band, fromBus: 0, toBus: band.nextAvailableInputBus, format: nil)
            s.volume = v.volume
            do {
                let bank = v.kit ? kAUSampler_DefaultPercussionBankMSB : kAUSampler_DefaultMelodicBankMSB
                try s.loadSoundBankInstrument(at: Self.soundBank, program: v.program, bankMSB: UInt8(bank),
                                              bankLSB: UInt8(kAUSampler_DefaultBankLSB))
            } catch {
                Log.info("intro: no instrument \(v.program) (\(error.localizedDescription))")
                continue
            }
            samplers[v] = s
        }
        engine.mainMixerNode.outputVolume = 0.75
        engine.prepare()
        ready = true
    }

    func play() {
        guard ready else { return }
        do { try engine.start() } catch { Log.info("intro: audio engine failed (\(error.localizedDescription))"); return }
        keepAlive = self
        let start = DispatchTime.now()
        queue.async { [self] in
            var last = 0.0
            for n in notes {
                schedule(start + n.at) { [weak self] in self?.on(n) }
                schedule(start + n.at + n.length) { [weak self] in self?.off(n) }
                last = max(last, n.at + n.length)
            }
            schedule(start + last + 3) { [weak self] in self?.stop() }
        }
    }

    var isPlaying: Bool { keepAlive != nil }

    func fadeOut(over seconds: Double = 1.2) {
        queue.async { [self] in
            guard keepAlive != nil else { return }
            pending.forEach { $0.cancel() }
            pending = []
            let steps = 24, from = engine.mainMixerNode.outputVolume
            for i in 1...steps {
                schedule(.now() + seconds * Double(i) / Double(steps)) { [weak self] in
                    self?.engine.mainMixerNode.outputVolume = from * Float(1 - Double(i) / Double(steps))
                }
            }
            schedule(.now() + seconds + 0.05) { [weak self] in self?.stop() }
        }
    }

    private func schedule(_ when: DispatchTime, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        pending.append(w)
        queue.asyncAfter(deadline: when, execute: w)
    }

    private func on(_ n: Note) {
        guard let s = samplers[n.voice] else { return }
        n.keys.forEach { s.startNote($0, withVelocity: n.velocity, onChannel: 0) }
    }

    private func off(_ n: Note) {
        guard let s = samplers[n.voice] else { return }
        n.keys.forEach { s.stopNote($0, onChannel: 0) }
    }

    private func stop() {
        pending.forEach { $0.cancel() }
        pending = []
        for s in samplers.values { (0...127).forEach { s.stopNote(UInt8($0), onChannel: 0) } }
        engine.stop()
        keepAlive = nil
    }


    private static let G1: UInt8 = 31, A1: UInt8 = 33
    private static let D1: UInt8 = 26, D2: UInt8 = 38, G2: UInt8 = 43, A2: UInt8 = 45
    private static let D3: UInt8 = 50, E3: UInt8 = 52, Fs3: UInt8 = 54, G3: UInt8 = 55, A3: UInt8 = 57, B3: UInt8 = 59
    private static let Cs4: UInt8 = 61, D4: UInt8 = 62, E4: UInt8 = 64, Fs4: UInt8 = 66, A4: UInt8 = 69, B4: UInt8 = 71
    private static let Cs5: UInt8 = 73, D5: UInt8 = 74, E5: UInt8 = 76, Fs5: UInt8 = 78, A5: UInt8 = 81, B5: UInt8 = 83
    private static let D6: UInt8 = 86, Fs6: UInt8 = 90, A6: UInt8 = 93

    private static let kick: UInt8 = 36, snare: UInt8 = 38, hat: UInt8 = 42, openHat: UInt8 = 46, crash: UInt8 = 49
    private static let splash: UInt8 = 57, lowTom: UInt8 = 41, midTom: UInt8 = 45, highTom: UInt8 = 48, ride: UInt8 = 51

    fileprivate static var orchestra: [Note] {
        var n: [Note] = []
        func add(_ at: Double, _ v: Voice, _ keys: [UInt8], _ vel: UInt8, _ len: Double) {
            n.append(Note(at: at, voice: v, keys: keys, velocity: vel, length: len))
        }
        typealias B = Beat

        add(0, .piano, [D3, A3], 70, 0.5)
        add(0.25, .piano, [Fs4], 62, 0.25)

        for (i, t) in B.arrive.enumerated() {
            let k = [D4, Fs4, A4, D5, Fs5][i]
            add(t, .piano, [k - 12, k], 100, 0.35)
            add(t, .pizzicato, [[D3, A2, D3, A2, D3][i]], 52, 0.2)
            if i < B.arrive.count - 1 { add(t + 0.25, .piano, [A5], 46, 0.1) }
        }

        add(B.word, .piano, [D3, A3, D4, Fs4, A4], 92, 0.3)
        add(B.word, .strings, [D3, Fs3, A3, D4], 72, 0.3)
        add(B.word, .pizzicato, [D2], 84, 0.3)
        add(B.word, .piano, [A5], 76, 0.2)
        add(B.word + 0.25, .piano, [Fs5], 64, 0.2)

        for (i, k) in [D6, A5, Fs5, D5, A4].enumerated() {
            add(B.retile + Double(i) * B.step, .piano, [k], 78 - UInt8(i * 4), 0.1)
        }
        add(B.retile, .pizzicato, [G2, G3], 80, 0.25)
        add(B.retile, .piano, [G3, B3, D4], 66, 0.25)
        add(B.retile + 0.5, .pizzicato, [A2, A3], 80, 0.25)
        add(B.retile + 0.5, .piano, [A3, Cs4, E4], 66, 0.25)

        let rise: [UInt8] = [A3, D4, E4, Fs4, A4, B4, Cs5, D5, E5, Fs5, A5, B5]
        let span = B.impact - 0.25 - B.gather
        for (i, k) in rise.enumerated() {
            let t = B.gather + span * Double(i) / Double(rise.count)
            add(t, .piano, [k], 56 + UInt8(i * 3), 0.09)
        }
        for i in 0..<12 { add(B.gather + Double(i) * span / 12, .timpani, [A2], 34 + UInt8(i * 4), 0.07) }
        add(B.gather, .strings, [A3, E4, A4], 50, span)
        add(B.gather + span * 0.5, .strings, [Cs5, E5], 70, span * 0.5)

        for (i, k) in [D1, D2, A2, D3, Fs3, A3, D4, Fs4, A4, D5, Fs5, A5, D6].enumerated() {
            add(B.impact + Double(i) * 0.022, .piano, [k], 104 - UInt8(i * 2), 3.2)
        }
        add(B.impact, .strings, [D3, A3, D4, Fs4], 52, 2.6)
        add(B.impact, .timpani, [D2], 70, 1.2)
        add(B.impact + 0.75, .piano, [Fs6], 56, 1.4)
        add(B.impact + 1.0, .piano, [A6], 50, 1.4)
        add(B.impact + 1.25, .piano, [D6], 54, 2.4)
        drums(add)
        band(add)
        return n
    }

    private static func band(_ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
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

    private static func drums(_ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
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


    private static let D7: UInt8 = 98
    private static let sideStick: UInt8 = 37, clap: UInt8 = 39, tambourine: UInt8 = 54, cabasa: UInt8 = 69
    private static let shaker: UInt8 = 70, claves: UInt8 = 75

    fileprivate static var marimba: [Note] {
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


    fileprivate static var grand: [Note] {
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


    struct Combo {
        enum Rhythm { case none, kit, brushes, light, claps, softKick }
        enum Accent { case timpani, taiko, swell, sub, crash }

        var lead: Voice = .piano
        var bass: Voice?
        var pad: Voice?
        var sparkle: Voice?
        var pluck: Voice?
        var rhythm: Rhythm = .none
        var accents: [Accent] = []
    }

    private static let brushKit = Voice(program: 40, kit: true, volume: 0.6)
    private static let taiko = Voice(program: 116, volume: 0.6)

    fileprivate static func score(_ c: Combo) -> [Note] {
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

    private static func rhythm(_ r: Combo.Rhythm, _ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
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

    private static func accent(_ a: Combo.Accent, _ add: (Double, Voice, [UInt8], UInt8, Double) -> Void) {
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

extension IntroScore.Arrangement {
    private typealias S = IntroScore
    private typealias V = IntroScore.Voice

    private static func combo(_ id: String, _ name: String, _ blurb: String, _ c: IntroScore.Combo) -> Self {
        Self(id: id, name: name, blurb: blurb) { IntroScore.score(c) }
    }

    static let all: [Self] = [
        combo("1", "Felt piano, cello, soft strings", "Calm and personal",
              .init(lead: .piano, bass: V.cello.at(0.5), pad: V(program: 49, volume: 0.4))),
        combo("2", "Piano, celesta, harp", "Light and magical",
              .init(lead: .piano, sparkle: V(program: 8, volume: 0.4), pluck: .harp)),
        combo("3", "Nylon guitar, upright bass, brushes", "Relaxed and handmade",
              .init(lead: V(program: 24), bass: .bass, pluck: V(program: 24, volume: 0.5), rhythm: .brushes)),
        combo("4", "Piano, synth pad, sub bass", "Polished keynote sound",
              .init(lead: .piano, bass: V.synthBass.at(0.6), pad: V(program: 90, volume: 0.35), accents: [.sub])),
        Self(id: "5", name: "Marimba, pluck, light percussion", blurb: "Crisp and quick", notes: { S.marimba }),
        combo("6", "Glockenspiel, kalimba, soft kick", "Precise little dings",
              .init(lead: V.glockenspiel.at(0.8), bass: V.synthBass.at(0.4), pluck: .kalimba, rhythm: .softKick)),
        combo("7", "Piano, strings, timpani", "Epic and confident",
              .init(lead: .piano, bass: V.cello.at(0.5), pad: V.strings.at(0.5), accents: [.timpani, .crash])),
        Self(id: "8", name: "Piano, French horns, cellos, cymbal swell", blurb: "Noble and grand", notes: { S.grand }),
        combo("9", "Choir, strings, sub hit", "Awe and scale",
              .init(lead: .piano, bass: V.synthBass.at(0.5), pad: V(program: 52, volume: 0.45), sparkle: V.strings.at(0.3),
                    accents: [.sub, .taiko])),
        combo("10", "Solo piano, string quartet", "Refined and quiet",
              .init(lead: .piano, bass: V.cello.at(0.45), pad: V(program: 41, volume: 0.35), pluck: V(program: 40, volume: 0.35))),
        combo("11", "Harp, flute, vibraphone", "Airy and elegant",
              .init(lead: V.harp.at(1), pad: V.flute.at(0.35), sparkle: V(program: 11, volume: 0.45))),
        combo("12", "Rhodes, upright bass, brushed snare", "Smooth and jazzy",
              .init(lead: V(program: 4), bass: .bass, pluck: V(program: 4, volume: 0.5), rhythm: .brushes)),
        combo("13", "Piano, drum kit, electric bass, synth stabs", "Driving and punchy",
              .init(lead: .piano, bass: V(program: 33, volume: 0.65), pad: V(program: 50, volume: 0.35), rhythm: .kit)),
        combo("14", "Pizzicato, marimba, claps", "Playful and rhythmic",
              .init(lead: .marimba, bass: V.pizzicato.at(0.7), pluck: V.pizzicato.at(0.6), rhythm: .claps)),
        Self(id: "band", name: "Full band (earlier version)", blurb: "Piano over drums, bass, harp, flute",
             notes: { S.orchestra }),
    ]
}
