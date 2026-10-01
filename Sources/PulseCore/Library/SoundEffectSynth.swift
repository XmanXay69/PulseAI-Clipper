import Foundation

/// The built-in sound effects, each synthesized from scratch.
public enum SoundEffectKind: String, Codable, CaseIterable, Sendable {
    case whoosh, swoosh, riser, downlifter, impact, bassDrop, boom, pop, bubble, ding, success, error, notification,
         click, typing, shutter, glitch, scratch, laser, boing, rimshot, drumroll, heartbeat, countdown, coin, levelUp,
         sadTrombone, applause
}

public enum SoundEffectSynth {
    static let sr = Synth.sr
    static let twoPi = Synth.twoPi

    /// Stereo audio peaking at −3 dBFS.
    public static func render(_ kind: SoundEffectKind) -> [[Float]] {
        var out = make(kind)
        SynthMaster.finish(&out, lufs: nil, peakDB: -3, fadeOut: 0.01)
        return out
    }

    static func stereo(_ mono: [Float], pan: Float = 0) -> [[Float]] {
        var mix = SynthMix(length: mono.count)
        mix.add(mono, at: 0, gain: 1, pan: pan)
        return mix.render()
    }

    /// Mono → stereo with a reverb tail of `tail` seconds appended.
    static func spacious(_ mono: [Float], wet: Float, tail: Double = 1.2, room: Double = 0.86) -> [[Float]] {
        let padded = mono + [Float](repeating: 0, count: Synth.samples(tail))
        var mix = SynthMix(length: padded.count)
        mix.add(padded, at: 0, gain: 1, reverb: wet)
        return mix.render(room: room)
    }

    /// Band-passed noise whose centre frequency follows `frequency(t)`, shaped by `amplitude(t)`.
    static func sweptNoise(_ seconds: Double, q: Double = 1.2, seed: UInt64, frequency: (Double) -> Double, amplitude: (Double) -> Double) -> [Float] {
        var noise = Synth.Noise(seed: seed)
        let n = Synth.samples(seconds)
        var filter = Biquad.bandPass(frequency: frequency(0), q: q, sampleRate: sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            if i % 32 == 0 { filter.retune(Biquad.bandPass(frequency: max(40, frequency(t)), q: q, sampleRate: sr)) }
            out[i] = Float(filter.process(Double(noise.next())) * amplitude(t))
        }
        return out
    }

    /// Oscillator whose frequency follows `frequency(t)`.
    static func sweep(_ seconds: Double, wave: Synth.Wave = .triangle, frequency: (Double) -> Double, amplitude: (Double) -> Double) -> [Float] {
        let n = Synth.samples(seconds)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0, sine = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = frequency(t)
            phase += f / sr
            phase -= floor(phase)
            sine += twoPi * f / sr
            let x: Double
            switch wave {
            case .saw: x = 2 * phase - 1
            case .square(let duty): x = phase < duty ? 1 : -1
            case .triangle: x = sin(sine)
            }
            out[i] = Float(x * amplitude(t))
        }
        return out
    }

    static func mixMono(_ parts: [(sound: [Float], at: Double, gain: Float)]) -> [Float] {
        let length = parts.map { Synth.samples($0.at) + $0.sound.count }.max() ?? 0
        var out = [Float](repeating: 0, count: length)
        for part in parts {
            let start = Synth.samples(part.at)
            for i in part.sound.indices { out[start + i] += part.sound[i] * part.gain }
        }
        return out
    }

    static func make(_ kind: SoundEffectKind) -> [[Float]] {
        switch kind {
        case .whoosh:
            let d = 0.8
            let mono = sweptNoise(d, q: 1.4, seed: 11, frequency: { t in 350 + 2600 * sin(Double.pi * min(1, t / d)) },
                                  amplitude: { t in pow(sin(Double.pi * min(1, t / d)), 2) })
            var mix = SynthMix(length: mono.count)
            // Moves left → right.
            let half = mono.count / 2
            mix.add(Array(mono[..<half]), at: 0, gain: 1, pan: -0.6)
            mix.add(Array(mono[half...]), at: Double(half) / sr, gain: 1, pan: 0.6)
            return mix.render()
        case .swoosh:
            let d = 0.35
            return stereo(sweptNoise(d, q: 1.8, seed: 12, frequency: { t in 900 + 5200 * (t / d) },
                                     amplitude: { t in pow(sin(Double.pi * min(1, t / d)), 1.5) }), pan: 0.2)
        case .riser:
            let d = 3.0
            let noise = sweptNoise(d, q: 2, seed: 13, frequency: { t in 300 * pow(30, t / d) }, amplitude: { t in pow(t / d, 2) })
            let tone = sweep(d, wave: .saw, frequency: { t in 110 * pow(8, t / d) }, amplitude: { t in 0.25 * pow(t / d, 2.5) })
            return spacious(mixMono([(noise, 0, 1), (tone, 0, 1)]), wet: 0.25, tail: 0.4)
        case .downlifter:
            let d = 2.0
            let noise = sweptNoise(d, q: 1.5, seed: 14, frequency: { t in 6000 * pow(0.03, t / d) }, amplitude: { t in exp(-t * 1.6) })
            let tone = sweep(d, frequency: { t in 900 * pow(0.08, t / d) }, amplitude: { t in 0.4 * exp(-t * 1.8) })
            return spacious(mixMono([(noise, 0, 1), (tone, 0, 1)]), wet: 0.3, tail: 0.6)
        case .impact:
            let boom = sweep(1.6, frequency: { t in 35 + 45 * exp(-t * 6) }, amplitude: { t in exp(-t * 2.4) })
            let crack = sweptNoise(0.5, q: 0.6, seed: 15, frequency: { _ in 1800 }, amplitude: { t in exp(-t * 14) })
            let driven = mixMono([(boom, 0, 1), (crack, 0, 0.8)]).map { Float(tanh(Double($0) * 2)) }
            return spacious(driven, wet: 0.35, tail: 1.5, room: 0.9)
        case .bassDrop:
            return stereo(sweep(1.4, frequency: { t in 30 + 110 * exp(-t * 2.2) }, amplitude: { t in min(1, t / 0.01) * exp(-t * 1.1) })
                .map { Float(tanh(Double($0) * 2.5)) })
        case .boom:
            let thud = sweep(1.2, frequency: { t in 42 + 30 * exp(-t * 9) }, amplitude: { t in min(1, t / 0.003) * exp(-t * 2) })
                .map { Float(tanh(Double($0) * 3.2)) }
            return spacious(thud, wet: 0.6, tail: 2.2, room: 0.92)
        case .pop:
            return stereo(sweep(0.09, frequency: { t in 380 + 1400 * (t / 0.09) }, amplitude: { t in min(1, t / 0.002) * exp(-t * 40) }))
        case .bubble:
            return stereo(sweep(0.16, frequency: { t in 280 + 900 * pow(t / 0.16, 0.6) }, amplitude: { t in sin(Double.pi * min(1, t / 0.16)) }))
        case .ding:
            return spacious(Synth.bell(1568, length: 1.6, ratio: 3.01), wet: 0.25, tail: 0.6)
        case .success:
            let notes = [1047.0, 1319, 1568, 2093]
            var parts: [(sound: [Float], at: Double, gain: Float)] = []
            for (k, f) in notes.enumerated() { parts.append((Synth.bell(f, length: 1.2, ratio: 3.01), Double(k) * 0.075, 0.7)) }
            return spacious(mixMono(parts), wet: 0.3, tail: 0.6)
        case .error:
            let buzz = mixMono([
                (Synth.tone(150, length: 0.16, wave: .square(duty: 0.5), voices: 2, detuneCents: 30, cutoff: 2500, release: 0.02), 0, 1),
                (Synth.tone(150, length: 0.3, wave: .square(duty: 0.5), voices: 2, detuneCents: 30, cutoff: 2500, release: 0.03), 0.2, 1),
            ])
            return stereo(buzz)
        case .notification:
            let a = Synth.tone(880, length: 0.12, wave: .triangle, attack: 0.004, release: 0.12)
            let b = Synth.tone(1320, length: 0.2, wave: .triangle, attack: 0.004, release: 0.25)
            return spacious(mixMono([(a, 0, 0.8), (b, 0.13, 0.8)]), wet: 0.2, tail: 0.4)
        case .click:
            return stereo(click(seed: 16, pitch: 2200))
        case .typing:
            var rng = SeededGenerator(seed: 17)
            var parts: [(sound: [Float], at: Double, gain: Float)] = []
            var t = 0.0
            while t < 1.4 {
                let pitch = Double.random(in: 1500...3200, using: &rng)
                parts.append((click(seed: UInt64(parts.count + 100), pitch: pitch), t, Float.random(in: 0.6...1, using: &rng)))
                t += Double.random(in: 0.06...0.16, using: &rng)
            }
            return stereo(mixMono(parts), pan: 0.1)
        case .shutter:
            let blade = sweptNoise(0.05, q: 1, seed: 18, frequency: { _ in 3200 }, amplitude: { t in exp(-t * 90) })
            let thump = sweep(0.05, frequency: { _ in 180 }, amplitude: { t in exp(-t * 80) * 0.5 })
            return stereo(mixMono([(blade, 0, 1), (thump, 0, 1), (blade, 0.075, 0.8), (thump, 0.075, 0.7)]))
        case .glitch:
            var rng = SeededGenerator(seed: 19)
            var parts: [(sound: [Float], at: Double, gain: Float)] = []
            var t = 0.0
            while t < 0.6 {
                let f = Double.random(in: 120...1800, using: &rng)
                let len = Double.random(in: 0.02...0.06, using: &rng)
                let piece = Synth.tone(f, length: len, wave: .square(duty: Double.random(in: 0.1...0.5, using: &rng)), release: 0.002)
                for repeatIndex in 0..<Int.random(in: 1...3, using: &rng) { parts.append((piece, t + Double(repeatIndex) * len, 0.7)) }
                t += len * 3
            }
            var mono = mixMono(parts)
            Synth.bitcrush(&mono, bits: 5, hold: 4)
            return stereo(mono)
        case .scratch:
            // Noise "groove" read at a rate that swings forward and back, like a record pushed by hand.
            var noise = Synth.Noise(seed: 20)
            let source = (0..<Synth.samples(0.6)).map { _ in noise.next() }
            var low = Biquad.lowPass(frequency: 1800, sampleRate: sr)
            let groove = source.map { Float(low.process(Double($0))) }
            let n = Synth.samples(0.55)
            var position = 0.3 * sr
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                let t = Double(i) / sr
                let rate = 2.6 * sin(twoPi * 3.6 * t)
                position = min(Double(groove.count - 2), max(0, position + rate))
                let k = Int(position)
                let frac = Float(position - Double(k))
                out[i] = (groove[k] * (1 - frac) + groove[k + 1] * frac) * Float(min(1, abs(rate) / 1.5)) * 3
            }
            return stereo(out)
        case .laser:
            return spacious(sweep(0.28, wave: .square(duty: 0.5), frequency: { t in 200 + 2200 * exp(-t * 14) }, amplitude: { t in exp(-t * 6) * 0.6 }),
                            wet: 0.25, tail: 0.4)
        case .boing:
            return stereo(sweep(0.9, frequency: { t in 210 * (1 + 0.45 * exp(-t * 3.5) * sin(twoPi * 11 * t)) + 60 * t },
                                amplitude: { t in min(1, t / 0.004) * exp(-t * 3.2) }))
        case .rimshot:
            let hi = Synth.tom(pitch: 150, decay: 0.35)
            let lo = Synth.tom(pitch: 105, decay: 0.45)
            let kick = Synth.kick()
            let crash = Synth.hat(open: true, seed: 21).map { $0 * 1.4 }
            let longCrash = crash + [Float](repeating: 0, count: Synth.samples(0.6))
            return spacious(mixMono([(hi, 0, 0.8), (lo, 0.22, 0.85), (kick, 0.62, 0.9), (longCrash, 0.62, 0.9)]), wet: 0.3, tail: 0.8)
        case .drumroll:
            var parts: [(sound: [Float], at: Double, gain: Float)] = []
            let snare = Synth.snare(decay: 0.12)
            var t = 0.0
            while t < 2.0 {
                parts.append((snare, t, Float(0.2 + 0.6 * t / 2)))
                t += 0.045
            }
            parts.append((Synth.kick(), 2.05, 1))
            parts.append((Synth.hat(open: true, seed: 22).map { $0 * 1.5 }, 2.05, 1))
            return spacious(mixMono(parts), wet: 0.3, tail: 1.0)
        case .heartbeat:
            let thump = Synth.kick(decay: 0.25, top: 70, bottom: 40, drive: 1.3)
            return stereo(mixMono([(thump, 0, 1), (thump, 0.24, 0.7), (thump, 0.9, 1), (thump, 1.14, 0.7)]))
        case .countdown:
            let beep = Synth.tone(880, length: 0.14, wave: .triangle, attack: 0.003, release: 0.03)
            let go = Synth.tone(1760, length: 0.6, wave: .triangle, attack: 0.003, release: 0.2)
            return stereo(mixMono([(beep, 0, 0.8), (beep, 1, 0.8), (beep, 2, 0.8), (go, 3, 0.9)]))
        case .coin:
            let a = Synth.tone(988, length: 0.07, wave: .square(duty: 0.5), release: 0.003)
            let b = Synth.tone(1319, length: 0.32, wave: .square(duty: 0.5), release: 0.12, decayPerSecond: 4)
            return stereo(mixMono([(a, 0, 0.5), (b, 0.07, 0.5)]))
        case .levelUp:
            let notes = [523.0, 659, 784, 1047, 1319, 1568]
            var parts: [(sound: [Float], at: Double, gain: Float)] = []
            for (k, f) in notes.enumerated() { parts.append((Synth.tone(f, length: 0.07, wave: .square(duty: 0.25), release: 0.01), Double(k) * 0.07, 0.45)) }
            parts.append((Synth.tone(2093, length: 0.3, wave: .square(duty: 0.25), release: 0.1, vibrato: 0.01), 0.42, 0.45))
            return stereo(mixMono(parts))
        case .sadTrombone:
            // "Wah wah wah waaah": a brassy saw through a wah (moving band-pass), last note wobbling down.
            let notes: [(Double, Double, Double)] = [(311, 0, 0.42), (294, 0.45, 0.42), (277, 0.9, 0.42), (262, 1.35, 1.2)]
            var parts: [(sound: [Float], at: Double, gain: Float)] = []
            for (k, note) in notes.enumerated() {
                let last = k == notes.count - 1
                var raw = sweep(note.2, wave: .saw, frequency: { t in note.0 * (last ? (1 - 0.06 * t / note.2) * (1 + 0.02 * sin(twoPi * 6 * t)) : 1) },
                                amplitude: { t in min(1, t / 0.04) * min(1, (note.2 - t) / 0.08) })
                var wah = Biquad.bandPass(frequency: 500, q: 2.5, sampleRate: sr)
                for i in raw.indices {
                    let t = Double(i) / sr
                    if i % 32 == 0 { wah.retune(Biquad.bandPass(frequency: 450 + 900 * sin(Double.pi * min(1, t / min(note.2, 0.45))), q: 2.5, sampleRate: sr)) }
                    raw[i] = Float(wah.process(Double(raw[i])))
                }
                parts.append((raw, note.1, 1))
            }
            return spacious(mixMono(parts), wet: 0.2, tail: 0.5)
        case .applause:
            var rng = SeededGenerator(seed: 23)
            var parts: [(sound: [Float], at: Double, gain: Float)] = []
            for k in 0..<420 {
                let t = Double.random(in: 0...2.6, using: &rng)
                let swell = Float(sin(Double.pi * min(1, t / 2.8)))
                parts.append((Synth.clap(seed: UInt64(30 + k % 24)), t, (0.15 + 0.25 * swell) * Float.random(in: 0.5...1, using: &rng)))
            }
            return spacious(mixMono(parts), wet: 0.4, tail: 0.6)
        }
    }

    static func click(seed: UInt64, pitch: Double) -> [Float] {
        let tick = sweptNoise(0.02, q: 2, seed: seed, frequency: { _ in pitch }, amplitude: { t in exp(-t * 300) })
        let body = sweep(0.02, frequency: { _ in pitch / 4 }, amplitude: { t in exp(-t * 250) * 0.4 })
        return mixMono([(tick, 0, 1.4), (body, 0, 1)])
    }
}
