import AVFoundation
import AudioToolbox

extension IntroScore {
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

    func schedule(_ when: DispatchTime, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        pending.append(w)
        queue.asyncAfter(deadline: when, execute: w)
    }

    func on(_ n: Note) {
        guard let s = samplers[n.voice] else { return }
        n.keys.forEach { s.startNote($0, withVelocity: n.velocity, onChannel: 0) }
    }

    func off(_ n: Note) {
        guard let s = samplers[n.voice] else { return }
        n.keys.forEach { s.stopNote($0, onChannel: 0) }
    }

    func stop() {
        pending.forEach { $0.cancel() }
        pending = []
        for s in samplers.values { (0...127).forEach { s.stopNote(UInt8($0), onChannel: 0) } }
        engine.stop()
        keepAlive = nil
    }

    static var orchestra: [Note] {
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

}
