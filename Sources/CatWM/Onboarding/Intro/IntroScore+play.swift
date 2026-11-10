import AudioToolbox
import AVFoundation
import CatWMKit

extension IntroScore {
    func play() {
        guard ready else { return }
        do { try engine.start() } catch {
            Log.info("intro: audio engine failed (\(error.localizedDescription))")
            return
        }
        keepAlive = self
        let start = DispatchTime.now()
        queue.async { [self] in
            var last = 0.0
            for note in notes {
                schedule(start + note.time) { [weak self] in self?.noteOn(note) }
                schedule(start + note.time + note.length) { [weak self] in self?.noteOff(note) }
                last = max(last, note.time + note.length)
            }
            schedule(start + last + 3) { [weak self] in self?.stop() }
        }
    }

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

    func schedule(_ when: DispatchTime, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        pending.append(work)
        queue.asyncAfter(deadline: when, execute: work)
    }

    func noteOn(_ note: Note) {
        guard let sampler = samplers[note.voice] else { return }
        note.keys.forEach { sampler.startNote($0, withVelocity: note.velocity, onChannel: 0) }
    }

    func noteOff(_ note: Note) {
        guard let sampler = samplers[note.voice] else { return }
        note.keys.forEach { sampler.stopNote($0, onChannel: 0) }
    }

    func stop() {
        pending.forEach { $0.cancel() }
        pending = []
        for sampler in samplers.values { (0...127).forEach { sampler.stopNote(UInt8($0), onChannel: 0) } }
        engine.stop()
        keepAlive = nil
    }

    static var orchestra: [Note] {
        var notes: [Note] = []
        func add(_ time: Double, _ voice: Voice, _ keys: [UInt8], _ velocity: UInt8, _ length: Double) {
            notes.append(Note(time: time, voice: voice, keys: keys, velocity: velocity, length: length))
        }
        add(0, .piano, [Dn3, An3], 70, 0.5)
        add(0.25, .piano, [Fs4], 62, 0.25)

        for (i, time) in Beat.arrive.enumerated() {
            let key = [Dn4, Fs4, An4, Dn5, Fs5][i]
            add(time, .piano, [key - 12, key], 100, 0.35)
            add(time, .pizzicato, [[Dn3, An2, Dn3, An2, Dn3][i]], 52, 0.2)
            if i < Beat.arrive.count - 1 { add(time + 0.25, .piano, [An5], 46, 0.1) }
        }

        add(Beat.word, .piano, [Dn3, An3, Dn4, Fs4, An4], 92, 0.3)
        add(Beat.word, .strings, [Dn3, Fs3, An3, Dn4], 72, 0.3)
        add(Beat.word, .pizzicato, [Dn2], 84, 0.3)
        add(Beat.word, .piano, [An5], 76, 0.2)
        add(Beat.word + 0.25, .piano, [Fs5], 64, 0.2)

        for (i, key) in [Dn6, An5, Fs5, Dn5, An4].enumerated() {
            add(Beat.retile + Double(i) * Beat.step, .piano, [key], 78 - UInt8(i * 4), 0.1)
        }
        add(Beat.retile, .pizzicato, [Gn2, Gn3], 80, 0.25)
        add(Beat.retile, .piano, [Gn3, Bn3, Dn4], 66, 0.25)
        add(Beat.retile + 0.5, .pizzicato, [An2, An3], 80, 0.25)
        add(Beat.retile + 0.5, .piano, [An3, Cs4, En4], 66, 0.25)

        let rise: [UInt8] = [An3, Dn4, En4, Fs4, An4, Bn4, Cs5, Dn5, En5, Fs5, An5, Bn5]
        let span = Beat.impact - 0.25 - Beat.gather
        for (i, key) in rise.enumerated() {
            let time = Beat.gather + span * Double(i) / Double(rise.count)
            add(time, .piano, [key], 56 + UInt8(i * 3), 0.09)
        }
        for i in 0..<12 { add(Beat.gather + Double(i) * span / 12, .timpani, [An2], 34 + UInt8(i * 4), 0.07) }
        add(Beat.gather, .strings, [An3, En4, An4], 50, span)
        add(Beat.gather + span * 0.5, .strings, [Cs5, En5], 70, span * 0.5)

        for (i, key) in [Dn1, Dn2, An2, Dn3, Fs3, An3, Dn4, Fs4, An4, Dn5, Fs5, An5, Dn6].enumerated() {
            add(Beat.impact + Double(i) * 0.022, .piano, [key], 104 - UInt8(i * 2), 3.2)
        }
        add(Beat.impact, .strings, [Dn3, An3, Dn4, Fs4], 52, 2.6)
        add(Beat.impact, .timpani, [Dn2], 70, 1.2)
        add(Beat.impact + 0.75, .piano, [Fs6], 56, 1.4)
        add(Beat.impact + 1.0, .piano, [An6], 50, 1.4)
        add(Beat.impact + 1.25, .piano, [Dn6], 54, 2.4)
        drums(add)
        band(add)
        return notes
    }
}
