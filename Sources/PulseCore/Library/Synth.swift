import Foundation

/// Small, deterministic synthesizer used to render PULSE's built-in music and sound effects on the
/// user's Mac. Everything is generated from code (no samples), so the library is royalty-free and
/// costs nothing to ship. All voices return mono buffers at `Synth.sampleRate`.
public enum Synth {
    public static let sampleRate = 48_000.0
    static let sr = sampleRate
    static let twoPi = 2 * Double.pi

    static func samples(_ seconds: Double) -> Int { max(0, Int((seconds * sr).rounded())) }
    public static func hz(midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    /// Deterministic white noise.
    struct Noise {
        var rng: SeededGenerator
        init(seed: UInt64) { rng = SeededGenerator(seed: seed) }
        mutating func next() -> Float { Float.random(in: -1...1, using: &rng) }
    }

    /// Attack/release gain applied in place (linear ramps), with optional exponential decay while held.
    static func shape(_ x: inout [Float], attack: Double, release: Double, decayPerSecond: Double = 0) {
        let a = max(1, samples(attack)), r = max(1, samples(release))
        let n = x.count
        for i in 0..<n {
            var g: Double = 1
            if i < a { g = Double(i) / Double(a) }
            if i > n - r { g *= Double(n - i) / Double(r) }
            if decayPerSecond > 0 { g *= exp(-Double(i) / sr * decayPerSecond) }
            x[i] *= Float(g)
        }
    }

    // MARK: Drums

    /// Sine kick with a fast pitch drop and a click.
    static func kick(decay: Double = 0.42, top: Double = 165, bottom: Double = 46, drive: Double = 1.6, seed: UInt64 = 1) -> [Float] {
        var noise = Noise(seed: seed)
        let n = samples(decay * 1.4)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = bottom + (top - bottom) * exp(-t * 30)
            phase += twoPi * f / sr
            let body = sin(phase) * exp(-t / (decay * 0.38))
            let click = Double(noise.next()) * exp(-t * 700) * 0.35
            out[i] = Float(tanh(drive * (body + click)) / tanh(drive))
        }
        return out
    }

    static func snare(tone: Double = 190, decay: Double = 0.2, seed: UInt64 = 2) -> [Float] {
        var noise = Noise(seed: seed)
        let n = samples(decay * 1.6)
        var band = Biquad.bandPass(frequency: 2400, q: 0.7, sampleRate: sr)
        var high = Biquad.highPass(frequency: 900, sampleRate: sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let body = sin(twoPi * tone * t) * exp(-t * 22) * 0.55
            let rattle = high.process(band.process(Double(noise.next()))) * exp(-t / (decay * 0.42)) * 1.6
            out[i] = Float(body + rattle)
        }
        return out
    }

    static func clap(seed: UInt64 = 3) -> [Float] {
        var noise = Noise(seed: seed)
        let n = samples(0.35)
        var band = Biquad.bandPass(frequency: 1300, q: 1.1, sampleRate: sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            var env = exp(-max(0, t - 0.024) * 16) * 0.8
            for burst in [0.0, 0.011, 0.022] where t >= burst && t < burst + 0.011 { env = max(env, exp(-(t - burst) * 260)) }
            out[i] = Float(band.process(Double(noise.next())) * env * 2.2)
        }
        return out
    }

    static func hat(open: Bool = false, seed: UInt64 = 4) -> [Float] {
        var noise = Noise(seed: seed)
        let decay = open ? 0.22 : 0.035
        let n = samples(decay * 3)
        var high = Biquad.highPass(frequency: 7200, q: 0.8, sampleRate: sr)
        var high2 = Biquad.highPass(frequency: 7200, q: 0.8, sampleRate: sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            out[i] = Float(high2.process(high.process(Double(noise.next()))) * exp(-t / decay) * 0.9)
        }
        return out
    }

    static func tom(pitch: Double = 90, decay: Double = 0.6, seed: UInt64 = 5) -> [Float] {
        var noise = Noise(seed: seed)
        let n = samples(decay * 1.5)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var low = Biquad.lowPass(frequency: 900, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            phase += twoPi * pitch * (1 + 0.6 * exp(-t * 18)) / sr
            let body = sin(phase) * exp(-t / (decay * 0.4))
            let skin = low.process(Double(noise.next())) * exp(-t * 25) * 0.6
            out[i] = Float(tanh(1.4 * (body + skin)))
        }
        return out
    }

    static func shaker(seed: UInt64 = 6) -> [Float] {
        var noise = Noise(seed: seed)
        let n = samples(0.09)
        var band = Biquad.bandPass(frequency: 6000, q: 1.2, sampleRate: sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let env = min(1, t / 0.02) * exp(-max(0, t - 0.02) * 60)
            out[i] = Float(band.process(Double(noise.next())) * env * 1.5)
        }
        return out
    }

    // MARK: Bass

    /// 808: sine with saturation and an optional glide from another note.
    static func bass808(_ frequency: Double, length: Double, glideFrom: Double? = nil, drive: Double = 2.4) -> [Float] {
        let n = samples(length + 0.08)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            var f = frequency
            if let from = glideFrom { f = frequency + (from - frequency) * exp(-t * 14) }
            phase += twoPi * f / sr
            let env = min(1, t / 0.004) * exp(-t * 0.9) * (t > length ? exp(-(t - length) * 60) : 1)
            out[i] = Float(tanh(drive * sin(phase)) / tanh(drive) * env)
        }
        return out
    }

    /// Filtered saw bass with a pluck envelope on the filter.
    static func sawBass(_ frequency: Double, length: Double, cutoff: Double = 520, envAmount: Double = 900) -> [Float] {
        let n = samples(length + 0.05)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0, sub = 0.0
        var filter = Biquad.lowPass(frequency: cutoff + envAmount, q: 1.1, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            if i % 32 == 0 { filter.retune(Biquad.lowPass(frequency: cutoff + envAmount * exp(-t * 9), q: 1.1, sampleRate: sr)) }
            phase += frequency / sr
            phase -= floor(phase)
            sub += twoPi * frequency / 2 / sr
            let raw = (2 * phase - 1) * 0.7 + sin(sub) * 0.5
            let env = min(1, t / 0.005) * (t > length ? exp(-(t - length) * 80) : 1)
            out[i] = Float(filter.process(raw) * env)
        }
        return out
    }

    /// Soft round sine bass (lo-fi, ambient).
    static func sineBass(_ frequency: Double, length: Double) -> [Float] {
        let n = samples(length + 0.1)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let env = min(1, t / 0.012) * exp(-t * 0.6) * (t > length ? exp(-(t - length) * 40) : 1)
            out[i] = Float((sin(twoPi * frequency * t) + 0.18 * sin(twoPi * 2 * frequency * t)) * env)
        }
        return out
    }

    // MARK: Melodic

    /// Karplus–Strong plucked string (guitar / ukulele / harp).
    static func pluck(_ frequency: Double, length: Double, brightness: Double = 0.5, damping: Double = 0.996, seed: UInt64 = 7) -> [Float] {
        var noise = Noise(seed: seed &+ UInt64(frequency * 10))
        let period = max(2, Int(sr / frequency))
        var line = (0..<period).map { _ in noise.next() }
        // Darker excitation for lower brightness.
        var low = Biquad.lowPass(frequency: 800 + 7000 * brightness, sampleRate: sr)
        for i in line.indices { line[i] = Float(low.process(Double(line[i]))) }
        let n = samples(length + 0.3)
        var out = [Float](repeating: 0, count: n)
        var index = 0
        var previous: Float = 0
        let d = Float(damping)
        for i in 0..<n {
            let current = line[index]
            let next = d * 0.5 * (current + previous)
            previous = current
            line[index] = next
            index = (index + 1) % period
            let t = Double(i) / sr
            out[i] = current * Float(t > length ? exp(-(t - length) * 18) : 1)
        }
        return out
    }

    /// FM electric piano (Rhodes-like), optionally with tape wobble for lo-fi.
    static func keys(_ frequency: Double, length: Double, wobble: Double = 0, brightness: Double = 1) -> [Float] {
        let n = samples(length + 0.6)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0, mod = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = frequency * (1 + wobble * sin(twoPi * 0.55 * t))
            mod += twoPi * f / sr
            phase += twoPi * f / sr
            let index = brightness * (1.6 * exp(-t * 3.5) + 0.25)
            let tine = sin(14 * mod) * 0.04 * exp(-t * 28)
            let env = min(1, t / 0.003) * exp(-t * 1.1) * (t > length ? exp(-(t - length) * 9) : 1)
            out[i] = Float((sin(phase + index * sin(mod)) + tine) * env)
        }
        return out
    }

    /// FM bell / glockenspiel.
    static func bell(_ frequency: Double, length: Double = 1.6, ratio: Double = 3.5) -> [Float] {
        let n = samples(length)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let index = 2.6 * exp(-t * 2.5)
            let env = min(1, t / 0.002) * exp(-t * 2.2)
            out[i] = Float(sin(twoPi * frequency * t + index * sin(twoPi * frequency * ratio * t)) * env)
        }
        return out
    }

    enum Wave { case saw, square(duty: Double), triangle }

    /// Detuned oscillator stack through a low-pass, with attack/release (pads, strings, leads, chiptune).
    static func tone(_ frequency: Double, length: Double, wave: Wave, voices: Int = 1, detuneCents: Double = 0,
                     cutoff: Double = 20_000, attack: Double = 0.005, release: Double = 0.08,
                     vibrato: Double = 0, decayPerSecond: Double = 0) -> [Float] {
        let n = samples(length + release)
        var out = [Float](repeating: 0, count: n)
        var phases = (0..<voices).map { Double($0) * 0.37 }
        let detunes = (0..<voices).map { v -> Double in
            voices == 1 ? 1 : pow(2, (detuneCents * (Double(v) / Double(voices - 1) * 2 - 1)) / 1200)
        }
        for i in 0..<n {
            let t = Double(i) / sr
            let vib = vibrato > 0 ? 1 + vibrato * sin(twoPi * 5.2 * t) * min(1, t / 0.4) : 1
            var s = 0.0
            for v in 0..<voices {
                phases[v] += frequency * detunes[v] * vib / sr
                phases[v] -= floor(phases[v])
                let p = phases[v]
                switch wave {
                case .saw: s += 2 * p - 1
                case .square(let duty): s += p < duty ? 1 : -1
                case .triangle: s += 4 * abs(p - 0.5) - 1
                }
            }
            out[i] = Float(s / Double(voices))
        }
        if cutoff < 19_000 {
            var f1 = Biquad.lowPass(frequency: cutoff, sampleRate: sr)
            var f2 = Biquad.lowPass(frequency: cutoff, sampleRate: sr)
            for i in out.indices { out[i] = Float(f2.process(f1.process(Double(out[i])))) }
        }
        let held = samples(length)
        let a = max(1, samples(attack)), r = max(1, n - held)
        for i in 0..<n {
            var g = i < a ? Double(i) / Double(a) : 1
            if i >= held { g *= Double(n - i) / Double(r) }
            if decayPerSecond > 0 { g *= exp(-Double(i) / sr * decayPerSecond) }
            out[i] *= Float(g)
        }
        return out
    }

    // MARK: Effects

    /// Freeverb-style stereo reverb (8 damped combs + 4 all-passes per side).
    static func reverb(_ input: [Float], room: Double = 0.82, damp: Double = 0.3) -> (left: [Float], right: [Float]) {
        let scale = sr / 44_100
        let combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let allpasses = [556, 441, 341, 225]
        func channel(spread: Int) -> [Float] {
            var out = [Float](repeating: 0, count: input.count)
            var buffers = combs.map { [Float](repeating: 0, count: Int(Double($0 + spread) * scale)) }
            var indices = [Int](repeating: 0, count: combs.count)
            var stores = [Float](repeating: 0, count: combs.count)
            let feedback = Float(room), d = Float(damp)
            for i in input.indices {
                let x = input[i] * 0.015
                var s: Float = 0
                for c in 0..<combs.count {
                    let y = buffers[c][indices[c]]
                    stores[c] = y * (1 - d) + stores[c] * d
                    buffers[c][indices[c]] = x + stores[c] * feedback
                    indices[c] = (indices[c] + 1) % buffers[c].count
                    s += y
                }
                out[i] = s * 2
            }
            for a in allpasses {
                var buffer = [Float](repeating: 0, count: Int(Double(a + spread) * scale))
                var index = 0
                for i in out.indices {
                    let b = buffer[index]
                    buffer[index] = out[i] + b * 0.5
                    out[i] = b - out[i]
                    index = (index + 1) % buffer.count
                }
            }
            return out
        }
        return (channel(spread: 0), channel(spread: 23))
    }

    /// Simple feedback delay (echo).
    static func echo(_ x: inout [Float], seconds: Double, feedback: Float = 0.35, mix: Float = 0.3) {
        let d = max(1, samples(seconds))
        guard d < x.count else { return }
        var wet = [Float](repeating: 0, count: x.count)
        for i in d..<x.count { wet[i] = x[i - d] + wet[i - d] * feedback }
        for i in x.indices { x[i] += wet[i] * mix }
    }

    static func bitcrush(_ x: inout [Float], bits: Int, hold: Int) {
        let levels = Float(1 << max(1, bits - 1))
        var held: Float = 0
        for i in x.indices {
            if i % max(1, hold) == 0 { held = (x[i] * levels).rounded() / levels }
            x[i] = held
        }
    }
}

/// A stereo mix bus with a reverb send and a side-chained ("pumping") bus.
struct SynthMix {
    let length: Int
    var dry: [[Float]]
    var pumped: [[Float]]
    var send: [Float]
    var kicks: [Int] = []

    init(length: Int) {
        self.length = length
        dry = [[Float](repeating: 0, count: length), [Float](repeating: 0, count: length)]
        pumped = dry
        send = [Float](repeating: 0, count: length)
    }

    /// Adds a mono sound at `time` seconds. `pan` −1…1 (constant power).
    mutating func add(_ sound: [Float], at time: Double, gain: Float, pan: Float = 0, reverb: Float = 0, pump: Bool = false) {
        let start = Int((time * Synth.sr).rounded())
        guard start < length, !sound.isEmpty else { return }
        let angle = Double(pan + 1) * Double.pi / 4
        let l = gain * Float(cos(angle) * 2.0.squareRoot()), r = gain * Float(sin(angle) * 2.0.squareRoot())
        let begin = max(0, start), end = min(length, start + sound.count)
        guard begin < end else { return }
        for i in begin..<end {
            let x = sound[i - start]
            if pump {
                pumped[0][i] += x * l
                pumped[1][i] += x * r
            } else {
                dry[0][i] += x * l
                dry[1][i] += x * r
            }
            if reverb > 0 { send[i] += x * gain * reverb }
        }
    }

    /// Sums buses: pumped bus ducks after each kick, reverb return is added.
    func render(pumpDepth: Float = 0, room: Double = 0.82, reverbLevel: Float = 1) -> [[Float]] {
        var out = dry
        if pumpDepth > 0 {
            var gain = [Float](repeating: 1, count: length)
            let release = Synth.sr * 0.16
            for k in kicks where k < length {
                for i in k..<min(length, k + Int(release * 4)) {
                    let g = 1 - pumpDepth * Float(exp(-Double(i - k) / release))
                    gain[i] = min(gain[i], g)
                }
            }
            for c in 0..<2 { for i in 0..<length { out[c][i] += pumped[c][i] * gain[i] } }
        } else {
            for c in 0..<2 { for i in 0..<length { out[c][i] += pumped[c][i] } }
        }
        if reverbLevel > 0, send.contains(where: { $0 != 0 }) {
            let (l, r) = Synth.reverb(send, room: room)
            for i in 0..<length {
                out[0][i] += l[i] * reverbLevel
                out[1][i] += r[i] * reverbLevel
            }
        }
        return out
    }
}

/// Final processing for library audio.
enum SynthMaster {
    /// High-pass, loudness target (music) or peak target (effects), limiter, fade-out tail.
    static func finish(_ channels: inout [[Float]], lufs: Double?, peakDB: Double = -1, fadeOut: Double = 0.03) {
        guard let n = channels.first?.count, n > 0 else { return }
        for c in channels.indices {
            var hp = Biquad.highPass(frequency: 28, sampleRate: Synth.sr)
            hp.process(&channels[c])
            for i in channels[c].indices where !channels[c][i].isFinite { channels[c][i] = 0 }
        }
        if let lufs {
            let measured = LoudnessMeter.integratedLUFS(channels, sampleRate: Synth.sr)
            if measured.isFinite {
                let g = Float(pow(10, (lufs - measured) / 20))
                for c in channels.indices { for i in 0..<n { channels[c][i] *= g } }
            }
        } else {
            let peak = LoudnessMeter.samplePeak(channels)
            if peak > 0 {
                let g = Float(pow(10, peakDB / 20)) / peak
                for c in channels.indices { for i in 0..<n { channels[c][i] *= g } }
            }
        }
        AudioEnhanceChain.limit(&channels, sampleRate: Synth.sr, ceilingDB: peakDB)
        let f = min(n, Synth.samples(fadeOut))
        for c in channels.indices {
            for k in 0..<f { channels[c][n - 1 - k] *= Float(k) / Float(max(f, 1)) }
        }
    }
}
