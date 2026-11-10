import AudioToolbox
import AVFoundation
import CatWMKit

final class IntroScore {
    typealias AddNote = (Double, Voice, [UInt8], UInt8, Double) -> Void

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
        static var standard: Arrangement { named("1") ?? all[0] }
    }

    struct Note {
        let time: Double
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

    static let soundBank = URL(
        fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
    )

    let engine = AVAudioEngine()
    let reverb = AVAudioUnitReverb()
    var samplers: [Voice: AVAudioUnitSampler] = [:]
    let queue = DispatchQueue(label: "catwm.intro.score", qos: .userInteractive)
    var pending: [DispatchWorkItem] = []
    var keepAlive: IntroScore?
    var ready = false
    let notes: [Note]

    var isPlaying: Bool { keepAlive != nil }

    static let Gn1: UInt8 = 31, An1: UInt8 = 33
    static let Dn1: UInt8 = 26, Dn2: UInt8 = 38, Gn2: UInt8 = 43, An2: UInt8 = 45
    static let Dn3: UInt8 = 50, En3: UInt8 = 52, Fs3: UInt8 = 54
    static let Gn3: UInt8 = 55, An3: UInt8 = 57, Bn3: UInt8 = 59
    static let Cs4: UInt8 = 61, Dn4: UInt8 = 62, En4: UInt8 = 64
    static let Fs4: UInt8 = 66, An4: UInt8 = 69, Bn4: UInt8 = 71
    static let Cs5: UInt8 = 73, Dn5: UInt8 = 74, En5: UInt8 = 76
    static let Fs5: UInt8 = 78, An5: UInt8 = 81, Bn5: UInt8 = 83
    static let Dn6: UInt8 = 86, Fs6: UInt8 = 90, An6: UInt8 = 93

    static let kick: UInt8 = 36, snare: UInt8 = 38, hat: UInt8 = 42, openHat: UInt8 = 46, crash: UInt8 = 49
    static let splash: UInt8 = 57, lowTom: UInt8 = 41, midTom: UInt8 = 45, highTom: UInt8 = 48, ride: UInt8 = 51

    static let Dn7: UInt8 = 98
    static let sideStick: UInt8 = 37, clap: UInt8 = 39, tambourine: UInt8 = 54, cabasa: UInt8 = 69
    static let shaker: UInt8 = 70, claves: UInt8 = 75

    enum Rhythm { case none, kit, brushes, light, claps, softKick }
    enum Accent { case timpani, taiko, swell, sub, crash }

    struct Combo {
        var lead: Voice = .piano
        var bass: Voice?
        var pad: Voice?
        var sparkle: Voice?
        var pluck: Voice?
        var rhythm: Rhythm = .none
        var accents: [Accent] = []
    }

    static let brushKit = Voice(program: 40, kit: true, volume: 0.6)
    static let taiko = Voice(program: 116, volume: 0.6)

    init(_ arrangement: Arrangement = .standard) {
        notes = arrangement.notes()
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 22
        let band = AVAudioMixerNode()
        engine.attach(band)
        engine.attach(reverb)
        engine.connect(band, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        for voice in Set(notes.map(\.voice)) {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: band, fromBus: 0, toBus: band.nextAvailableInputBus, format: nil)
            sampler.volume = voice.volume
            do {
                let bank = voice.kit ? kAUSampler_DefaultPercussionBankMSB : kAUSampler_DefaultMelodicBankMSB
                try sampler.loadSoundBankInstrument(at: Self.soundBank, program: voice.program, bankMSB: UInt8(bank),
                                                    bankLSB: UInt8(kAUSampler_DefaultBankLSB))
            } catch {
                Log.info("intro: no instrument \(voice.program) (\(error.localizedDescription))")
                continue
            }
            samplers[voice] = sampler
        }
        engine.mainMixerNode.outputVolume = 0.75
        engine.prepare()
        ready = true
    }
}
