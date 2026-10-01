import Foundation

/// Second-order IIR filter (RBJ "Audio EQ Cookbook"), transposed direct form II.
public struct Biquad: Sendable {
    public var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var z1 = 0.0
    private var z2 = 0.0

    public init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    public static func highPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cw = cos(w), alpha = sin(w) / (2 * q)
        return Biquad(b0: (1 + cw) / 2, b1: -(1 + cw), b2: (1 + cw) / 2, a0: 1 + alpha, a1: -2 * cw, a2: 1 - alpha)
    }

    public static func lowPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cw = cos(w), alpha = sin(w) / (2 * q)
        return Biquad(b0: (1 - cw) / 2, b1: 1 - cw, b2: (1 - cw) / 2, a0: 1 + alpha, a1: -2 * cw, a2: 1 - alpha)
    }

    /// Constant 0 dB peak gain band-pass.
    public static func bandPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cw = cos(w), alpha = sin(w) / (2 * q)
        return Biquad(b0: alpha, b1: 0, b2: -alpha, a0: 1 + alpha, a1: -2 * cw, a2: 1 - alpha)
    }

    /// Takes another filter's coefficients but keeps this one's state (for sweeps without clicks).
    public mutating func retune(_ other: Biquad) {
        b0 = other.b0; b1 = other.b1; b2 = other.b2; a1 = other.a1; a2 = other.a2
    }

    public static func peaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cw = cos(w), alpha = sin(w) / (2 * q)
        return Biquad(b0: 1 + alpha * a, b1: -2 * cw, b2: 1 - alpha * a, a0: 1 + alpha / a, a1: -2 * cw, a2: 1 - alpha / a)
    }

    public static func lowShelf(frequency: Double, gainDB: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cw = cos(w), alpha = sin(w) / (2 * q), sa = 2 * sqrt(a) * alpha
        return Biquad(b0: a * ((a + 1) - (a - 1) * cw + sa), b1: 2 * a * ((a - 1) - (a + 1) * cw), b2: a * ((a + 1) - (a - 1) * cw - sa),
                      a0: (a + 1) + (a - 1) * cw + sa, a1: -2 * ((a - 1) + (a + 1) * cw), a2: (a + 1) + (a - 1) * cw - sa)
    }

    public static func highShelf(frequency: Double, gainDB: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cw = cos(w), alpha = sin(w) / (2 * q), sa = 2 * sqrt(a) * alpha
        return Biquad(b0: a * ((a + 1) + (a - 1) * cw + sa), b1: -2 * a * ((a - 1) + (a + 1) * cw), b2: a * ((a + 1) + (a - 1) * cw - sa),
                      a0: (a + 1) - (a - 1) * cw + sa, a1: 2 * ((a - 1) - (a + 1) * cw), a2: (a + 1) - (a - 1) * cw - sa)
    }

    @inline(__always)
    public mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    public mutating func process(_ samples: inout [Float]) {
        for i in samples.indices { samples[i] = Float(process(Double(samples[i]))) }
    }
}

/// ITU-R BS.1770 integrated loudness (LUFS) with K-weighting and gating.
public enum LoudnessMeter {
    public static func integratedLUFS(_ channels: [[Float]], sampleRate: Double) -> Double {
        guard let length = channels.first?.count, length > 0 else { return -.infinity }
        // K-weighting: high-shelf pre-filter + RLB high-pass (parameters from the spec, valid at any rate).
        var weighted: [[Float]] = []
        for channel in channels {
            var shelf = Biquad.highShelf(frequency: 1681.974450955533, gainDB: 3.999843853973347, q: 0.7071752369554196, sampleRate: sampleRate)
            var rlb = Biquad.highPass(frequency: 38.13547087602444, q: 0.5003270373238773, sampleRate: sampleRate)
            var out = channel
            for i in out.indices { out[i] = Float(rlb.process(shelf.process(Double(out[i])))) }
            weighted.append(out)
        }
        let block = Int(0.4 * sampleRate)
        let step = max(1, block / 4)
        guard length >= block else {
            let ms = weighted.map { ch in ch.reduce(0.0) { $0 + Double($1 * $1) } / Double(length) }.reduce(0, +)
            return ms > 0 ? -0.691 + 10 * log10(ms) : -.infinity
        }
        var blockPowers: [Double] = []
        var start = 0
        while start + block <= length {
            var sum = 0.0
            for ch in weighted {
                var s = 0.0
                for i in start..<(start + block) { s += Double(ch[i] * ch[i]) }
                sum += s / Double(block)
            }
            blockPowers.append(sum)
            start += step
        }
        func loudness(_ p: Double) -> Double { p > 0 ? -0.691 + 10 * log10(p) : -.infinity }
        let absolute = blockPowers.filter { loudness($0) > -70 }
        guard !absolute.isEmpty else { return -.infinity }
        let relativeGate = loudness(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { loudness($0) > relativeGate }
        guard !gated.isEmpty else { return -.infinity }
        return loudness(gated.reduce(0, +) / Double(gated.count))
    }

    public static func samplePeak(_ channels: [[Float]]) -> Float {
        channels.reduce(Float(0)) { m, ch in max(m, ch.reduce(Float(0)) { max($0, abs($1)) }) }
    }
}

/// The clip "Enhance" chain: high-pass → noise reduction → EQ / voice → compressor → pan → loudness → limiter.
/// Works on de-interleaved channels so it can run on any channel count.
public enum AudioEnhanceChain {
    /// Short-form platforms normalize to roughly −14 LUFS.
    public static let targetLUFS = -14.0
    public static let ceilingDB = -1.0

    /// A learned denoiser supplied by the engine (Core has no ML frameworks). It replaces the channels with
    /// the isolated voice, time-aligned with the input, and returns false when it can't run.
    public typealias VoiceIsolator = (_ channels: inout [[Float]], _ sampleRate: Double) -> Bool

    /// How much of the original stays under the isolated voice for a noise-reduction amount (0…1):
    /// 0.4 ≈ −9 dB of background, 0.7 ≈ −21 dB, 1 = voice only.
    public static func backgroundGain(amount: Double) -> Float {
        let rest = 1 - amount.clamped(0, 1)
        return Float(rest * rest)
    }

    /// Returns the method actually used for noise reduction (nil when none ran).
    @discardableResult
    public static func process(_ channels: inout [[Float]], sampleRate: Double, settings: AudioSettings,
                               voiceIsolator: VoiceIsolator? = nil) -> NoiseReductionMethod? {
        guard !channels.isEmpty, let length = channels.first?.count, length > 0 else { return nil }
        var denoisedWith: NoiseReductionMethod?

        // 1. High-pass: explicit EQ cut-off, or 80 Hz rumble removal for voice.
        var highPass = settings.eq.isEnabled ? settings.eq.highPassHz : 0
        if settings.voiceEnhance { highPass = max(highPass, 80) }
        if highPass > 10 {
            for c in channels.indices {
                var f = Biquad.highPass(frequency: highPass, sampleRate: sampleRate)
                f.process(&channels[c])
            }
        }

        // 2. Noise reduction. The neural voice isolator removes any non-voice sound; the original is
        //    mixed back in under it by amount. Classic mode (or no isolator): spectral subtraction removes
        //    steady noise (hiss, fans, hum), then a gentle expander quiets what's left between words.
        if settings.noiseReduction > 0.001 {
            let amount = settings.noiseReduction.clamped(0, 1)
            if settings.noiseMethod == .voiceIsolation, let voiceIsolator {
                let original = channels
                if voiceIsolator(&channels, sampleRate), channels.count == original.count, channels.allSatisfy({ $0.count == length }) {
                    let keep = backgroundGain(amount: amount)
                    if keep > 0 {
                        for c in channels.indices {
                            for i in 0..<length { channels[c][i] += keep * (original[c][i] - channels[c][i]) }
                        }
                    }
                    denoisedWith = .voiceIsolation
                } else {
                    channels = original
                }
            }
            if denoisedWith == nil {
                SpectralDenoiser.process(&channels, amount: amount)
                expand(&channels, sampleRate: sampleRate, amount: amount * 0.5)
                denoisedWith = .spectral
            }
        }

        // 3. EQ + voice shaping.
        var filters: [(Double) -> Biquad] = []
        if settings.eq.isEnabled {
            let eq = settings.eq
            if abs(eq.lowGain) > 0.05 { filters.append { Biquad.lowShelf(frequency: 120, gainDB: eq.lowGain, sampleRate: $0) } }
            if abs(eq.midGain) > 0.05 { filters.append { Biquad.peaking(frequency: 1200, gainDB: eq.midGain, q: 0.8, sampleRate: $0) } }
            if abs(eq.highGain) > 0.05 { filters.append { Biquad.highShelf(frequency: 8000, gainDB: eq.highGain, sampleRate: $0) } }
        }
        if settings.voiceEnhance {
            filters.append { Biquad.peaking(frequency: 300, gainDB: -2.5, q: 1.0, sampleRate: $0) }   // less mud
            filters.append { Biquad.peaking(frequency: 3500, gainDB: 3, q: 0.9, sampleRate: $0) }     // presence
            filters.append { Biquad.highShelf(frequency: 10000, gainDB: 1.5, sampleRate: $0) }        // air
        }
        if !filters.isEmpty {
            for c in channels.indices {
                var chain = filters.map { $0(sampleRate) }
                for i in channels[c].indices {
                    var x = Double(channels[c][i])
                    for k in chain.indices { x = chain[k].process(x) }
                    channels[c][i] = Float(x)
                }
            }
        }

        // 4. Compressor (voice enhance implies gentle compression).
        if settings.compressor.isEnabled {
            compress(&channels, sampleRate: sampleRate, thresholdDB: settings.compressor.thresholdDB,
                     ratio: max(1, settings.compressor.ratio), makeupDB: settings.compressor.makeupGainDB)
        } else if settings.voiceEnhance {
            compress(&channels, sampleRate: sampleRate, thresholdDB: -20, ratio: 2.5, makeupDB: 3)
        }

        // 5. Pan before loudness so normalization measures what's actually heard
        //    (balance for stereo; mono sources become stereo so they can be placed).
        if abs(settings.pan) > 0.001 {
            applyPan(&channels, pan: settings.pan.clamped(-1, 1))
        }

        // 6. Loudness normalization.
        if settings.normalize {
            let lufs = LoudnessMeter.integratedLUFS(channels, sampleRate: sampleRate)
            if lufs.isFinite {
                let gain = Float(pow(10, (targetLUFS - lufs) / 20).clamped(0.05, 20))
                for c in channels.indices {
                    for i in channels[c].indices { channels[c][i] *= gain }
                }
            }
        }

        // 7. Limiter (always after normalization so boosted peaks never clip).
        if settings.limiter || settings.normalize || settings.voiceEnhance || settings.compressor.isEnabled {
            limit(&channels, sampleRate: sampleRate, ceilingDB: ceilingDB)
        }
        return denoisedWith
    }

    /// Constant-power pan for mono, balance for stereo (the far side is attenuated).
    public static func applyPan(_ channels: inout [[Float]], pan: Double) {
        if channels.count == 1 {
            let angle = (pan + 1) * Double.pi / 4
            let left = Float(cos(angle) * 2.0.squareRoot()), right = Float(sin(angle) * 2.0.squareRoot())
            let mono = channels[0]
            channels = [mono.map { $0 * left }, mono.map { $0 * right }]
        } else if channels.count >= 2 {
            let left = Float(min(1, 1 - pan)), right = Float(min(1, 1 + pan))
            for i in channels[0].indices { channels[0][i] *= left }
            for i in channels[1].indices { channels[1][i] *= right }
        }
    }

    /// Feed-forward, stereo-linked compressor with a 6 dB soft knee.
    public static func compress(_ channels: inout [[Float]], sampleRate: Double, thresholdDB: Double, ratio: Double, makeupDB: Double,
                                attack: Double = 0.005, release: Double = 0.12) {
        let length = channels[0].count
        let attackCoef = exp(-1 / (attack * sampleRate))
        let releaseCoef = exp(-1 / (release * sampleRate))
        let knee = 6.0
        let slope = 1 - 1 / ratio
        var env = 0.0
        for i in 0..<length {
            var peak: Float = 0
            for c in channels.indices { peak = max(peak, abs(channels[c][i])) }
            let level = 20 * log10(max(Double(peak), 1e-6))
            let over = level - thresholdDB
            let reduction: Double
            if over <= -knee / 2 {
                reduction = 0
            } else if over >= knee / 2 {
                reduction = over * slope
            } else {
                let x = over + knee / 2
                reduction = slope * x * x / (2 * knee)
            }
            let coef = reduction > env ? attackCoef : releaseCoef
            env = coef * env + (1 - coef) * reduction
            let gain = Float(pow(10, (makeupDB - env) / 20))
            for c in channels.indices { channels[c][i] *= gain }
        }
    }

    /// Look-ahead peak limiter: gain ramps down before a peak and recovers slowly, then a hard ceiling.
    public static func limit(_ channels: inout [[Float]], sampleRate: Double, ceilingDB: Double, lookahead: Double = 0.005, release: Double = 0.08) {
        let length = channels[0].count
        let ceiling = Float(pow(10, ceilingDB / 20))
        var gains = [Float](repeating: 1, count: length)
        var needsLimiting = false
        for i in 0..<length {
            var peak: Float = 0
            for c in channels.indices { peak = max(peak, abs(channels[c][i])) }
            if peak > ceiling {
                gains[i] = ceiling / peak
                needsLimiting = true
            }
        }
        guard needsLimiting else { return }
        let window = max(1, Int(lookahead * sampleRate))
        let attackStep = Float(1) / Float(window)
        let releaseStep = Float(1) / Float(max(1, release * sampleRate))
        // Backward pass: start reducing `window` samples before each peak.
        if length > 1 {
            for i in stride(from: length - 2, through: 0, by: -1) {
                gains[i] = min(gains[i], gains[i + 1] + attackStep)
            }
            // Forward pass: slow recovery after peaks.
            for i in 1..<length {
                gains[i] = min(gains[i], gains[i - 1] + releaseStep)
            }
        }
        for c in channels.indices {
            for i in 0..<length {
                let y = channels[c][i] * gains[i]
                channels[c][i] = min(max(y, -ceiling), ceiling)
            }
        }
    }

    /// Downward expander: frames quieter than the noise floor + margin are attenuated by up to 24 dB × amount.
    public static func expand(_ channels: inout [[Float]], sampleRate: Double, amount: Double) {
        let length = channels[0].count
        let frame = max(1, Int(0.01 * sampleRate))
        let frameCount = (length + frame - 1) / frame
        var levels = [Double](repeating: -120, count: frameCount)
        for f in 0..<frameCount {
            let start = f * frame
            let end = min(length, start + frame)
            var sum = 0.0
            for c in channels.indices {
                for i in start..<end { sum += Double(channels[c][i] * channels[c][i]) }
            }
            let ms = sum / Double(max(1, (end - start) * channels.count))
            levels[f] = ms > 0 ? 10 * log10(ms) : -120
        }
        let audible = levels.filter { $0 > -90 }.sorted()
        guard !audible.isEmpty else { return }
        let floor = audible[Int(Double(audible.count - 1) * 0.1)]
        let threshold = floor + 6 + 6 * amount
        let maxCut = 24 * amount
        var targets = [Double](repeating: 0, count: frameCount)
        for f in 0..<frameCount {
            let depth = ((threshold - levels[f]) / 10).clamped(0, 1)
            targets[f] = -maxCut * depth
        }
        // Smooth in the frame domain: fast open (5 ms), slower close (60 ms).
        var smoothed = targets
        var current = 0.0
        let openCoef = exp(-0.01 / 0.005)
        let closeCoef = exp(-0.01 / 0.06)
        for f in 0..<frameCount {
            let coef = targets[f] > current ? openCoef : closeCoef
            current = coef * current + (1 - coef) * targets[f]
            smoothed[f] = current
        }
        // Per-sample gain, interpolated between frame centres.
        for f in 0..<frameCount {
            let start = f * frame
            let end = min(length, start + frame)
            let g0 = pow(10, smoothed[f] / 20)
            let g1 = pow(10, smoothed[min(f + 1, frameCount - 1)] / 20)
            let span = Double(max(1, end - start))
            for i in start..<end {
                let g = Float(g0 + (g1 - g0) * Double(i - start) / span)
                for c in channels.indices { channels[c][i] *= g }
            }
        }
    }
}

extension AudioSettings {
    /// True when the clip needs the offline enhance render (the live audio mix handles volume/fades/ducking).
    public var needsEnhanceRender: Bool {
        !isMuted && (normalize || voiceEnhance || noiseReduction > 0.001 || limiter || eq.isEnabled || compressor.isEnabled || abs(pan) > 0.001)
    }

    /// Stable key for the cached render of the enhance chain.
    public var enhanceFingerprint: String {
        let parts: [String] = [
            normalize ? "n" : "", voiceEnhance ? "v" : "", limiter ? "l" : "",
            String(format: "nr%.3f", noiseReduction), String(format: "p%.3f", pan),
            noiseReduction > 0.001 && noiseMethod == .voiceIsolation ? "vi" : "",
            eq.isEnabled ? String(format: "eq%.2f,%.2f,%.2f,%.1f", eq.lowGain, eq.midGain, eq.highGain, eq.highPassHz) : "",
            compressor.isEnabled ? String(format: "c%.2f,%.2f,%.2f", compressor.thresholdDB, compressor.ratio, compressor.makeupGainDB) : "",
        ]
        return parts.joined(separator: "|")
    }

    /// Broadcast-style voice preset: rumble filter, presence, compression, loudness, limiter.
    public mutating func applyVoicePreset() {
        voiceEnhance = true
        normalize = true
        limiter = true
        if noiseReduction < 0.3 { noiseReduction = 0.3 }
    }
}

/// Stable 64-bit FNV-1a hash (Swift's Hasher is randomly seeded per launch).
public enum StableHash {
    public static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
