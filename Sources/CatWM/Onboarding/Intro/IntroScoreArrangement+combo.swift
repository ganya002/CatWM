import AudioToolbox
import AVFoundation
import CatWMKit

extension IntroScore.Arrangement {
    private typealias Voice = IntroScore.Voice

    private static func combo(_ id: String, _ name: String, _ blurb: String, _ combo: IntroScore.Combo) -> Self {
        Self(id: id, name: name, blurb: blurb) { IntroScore.score(combo) }
    }

    static let all: [Self] = [
        combo("1", "Felt piano, cello, soft strings", "Calm and personal",
              .init(lead: .piano, bass: Voice.cello.at(0.5), pad: Voice(program: 49, volume: 0.4))),
        combo("2", "Piano, celesta, harp", "Light and magical",
              .init(lead: .piano, sparkle: Voice(program: 8, volume: 0.4), pluck: .harp)),
        combo("3", "Nylon guitar, upright bass, brushes", "Relaxed and handmade",
              .init(lead: Voice(program: 24), bass: .bass, pluck: Voice(program: 24, volume: 0.5),
                    rhythm: .brushes)),
        combo("4", "Piano, synth pad, sub bass", "Polished keynote sound",
              .init(lead: .piano, bass: Voice.synthBass.at(0.6), pad: Voice(program: 90, volume: 0.35),
                    accents: [.sub])),
        Self(id: "5", name: "Marimba, pluck, light percussion", blurb: "Crisp and quick",
             notes: { IntroScore.marimba }),
        combo("6", "Glockenspiel, kalimba, soft kick", "Precise little dings",
              .init(lead: Voice.glockenspiel.at(0.8), bass: Voice.synthBass.at(0.4), pluck: .kalimba,
                    rhythm: .softKick)),
        combo("7", "Piano, strings, timpani", "Epic and confident",
              .init(lead: .piano, bass: Voice.cello.at(0.5), pad: Voice.strings.at(0.5),
                    accents: [.timpani, .crash])),
        Self(id: "8", name: "Piano, French horns, cellos, cymbal swell", blurb: "Noble and grand",
             notes: { IntroScore.grand }),
        combo("9", "Choir, strings, sub hit", "Awe and scale",
              .init(lead: .piano, bass: Voice.synthBass.at(0.5), pad: Voice(program: 52, volume: 0.45),
                    sparkle: Voice.strings.at(0.3), accents: [.sub, .taiko])),
        combo("10", "Solo piano, string quartet", "Refined and quiet",
              .init(lead: .piano, bass: Voice.cello.at(0.45), pad: Voice(program: 41, volume: 0.35),
                    pluck: Voice(program: 40, volume: 0.35))),
        combo("11", "Harp, flute, vibraphone", "Airy and elegant",
              .init(lead: Voice.harp.at(1), pad: Voice.flute.at(0.35), sparkle: Voice(program: 11, volume: 0.45))),
        combo("12", "Rhodes, upright bass, brushed snare", "Smooth and jazzy",
              .init(lead: Voice(program: 4), bass: .bass, pluck: Voice(program: 4, volume: 0.5), rhythm: .brushes)),
        combo("13", "Piano, drum kit, electric bass, synth stabs", "Driving and punchy",
              .init(lead: .piano, bass: Voice(program: 33, volume: 0.65), pad: Voice(program: 50, volume: 0.35),
                    rhythm: .kit)),
        combo("14", "Pizzicato, marimba, claps", "Playful and rhythmic",
              .init(lead: .marimba, bass: Voice.pizzicato.at(0.7), pluck: Voice.pizzicato.at(0.6), rhythm: .claps)),
        Self(id: "band", name: "Full band (earlier version)", blurb: "Piano over drums, bass, harp, flute",
             notes: { IntroScore.orchestra })
    ]
}
