import Foundation

/// Genres the composer can write.
public enum MusicStyle: String, Codable, CaseIterable, Sendable {
    case lofi, trap, upbeat, acoustic, synthwave, cinematic, chiptune, suspense, quirky, ambient

    public var displayName: String {
        switch self {
        case .lofi: return "Lo-fi"
        case .trap: return "Trap / Hype"
        case .upbeat: return "Upbeat Pop"
        case .acoustic: return "Acoustic"
        case .synthwave: return "Synthwave"
        case .cinematic: return "Cinematic"
        case .chiptune: return "Chiptune"
        case .suspense: return "Suspense"
        case .quirky: return "Quirky / Comedy"
        case .ambient: return "Ambient"
        }
    }
}

/// One piece of library music: a style plus the choices that make it its own track.
public struct MusicPreset: Codable, Hashable, Sendable {
    public var style: MusicStyle
    public var bpm: Double
    /// MIDI note of the key's tonic around the chord register (57 = A3).
    public var root: Int
    public var minor: Bool
    public var seed: UInt64

    public init(style: MusicStyle, bpm: Double, root: Int, minor: Bool, seed: UInt64) {
        self.style = style
        self.bpm = bpm
        self.root = root
        self.minor = minor
        self.seed = seed
    }
}

/// Writes and renders a complete piece of music of an exact length: a short intro, the groove (with a
/// breakdown in longer pieces) and a real ending — a final hit that rings out on the last beat.
public enum MusicComposer {
    /// Length of the ring-out after the final hit.
    public static func tail(for duration: Double) -> Double { min(2.2, max(0.6, duration * 0.12)) }

    /// Stereo audio at `Synth.sampleRate`, exactly `duration` seconds long, at about −16 LUFS.
    public static func render(_ preset: MusicPreset, duration: Double) -> [[Float]] {
        let length = max(1, Synth.samples(duration))
        var composer = Composer(preset: preset, duration: Double(length) / Synth.sr)
        composer.write()
        var out = composer.mix.render(pumpDepth: composer.pumpDepth, room: composer.room, reverbLevel: composer.reverbLevel)
        composer.addTexture(&out)
        // Ring-out: fade the last part of the tail so the piece ends cleanly at the exact length.
        let fade = min(length, Synth.samples(composer.tail * 0.7))
        for c in out.indices {
            for k in 0..<fade {
                let x = Float(k) / Float(max(fade, 1))
                out[c][length - 1 - k] *= x * x
            }
        }
        SynthMaster.finish(&out, lufs: -16, peakDB: -1)
        return out
    }
}

final class SoundCache {
    var store: [String: [Float]] = [:]
}

struct Composer {
    let preset: MusicPreset
    let duration: Double
    let beat: Double
    let bar: Double
    let tail: Double
    /// When the final hit lands.
    let end: Double
    let bars: Int
    var mix: SynthMix
    var rng: SeededGenerator
    var pumpDepth: Float = 0
    var room = 0.82
    var reverbLevel: Float = 1
    private let cache = SoundCache()

    init(preset: MusicPreset, duration: Double) {
        self.preset = preset
        self.duration = duration
        beat = 60 / preset.bpm
        bar = beat * 4
        tail = MusicComposer.tail(for: duration)
        end = max(0.2, duration - tail)
        bars = max(1, Int(ceil(end / bar - 0.001)))
        mix = SynthMix(length: max(1, Synth.samples(duration)))
        rng = SeededGenerator(seed: preset.seed)
    }

    // MARK: Musical helpers

    var scale: [Int] { preset.minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11] }

    /// Semitones above the root for scale degree `d` (any integer, wraps octaves).
    func degree(_ d: Int) -> Int {
        let octave = Int(floor(Double(d) / 7))
        return scale[((d % 7) + 7) % 7] + 12 * octave
    }

    /// Chord tones (MIDI) for a degree: triad or seventh, voiced around the root.
    func chord(_ d: Int, seventh: Bool = false, octave: Int = 0) -> [Int] {
        (seventh ? [0, 2, 4, 6] : [0, 2, 4]).map { preset.root + 12 * octave + degree(d + $0) }
    }

    var progression: [Int] {
        switch preset.style {
        case .lofi: return [1, 4, 0, 5]
        case .trap: return [0, 5, 2, 6]
        case .upbeat: return [0, 4, 5, 3]
        case .acoustic: return [0, 3, 5, 4]
        case .synthwave: return [0, 3, 5, 4]
        case .cinematic: return [0, 5, 2, 6]
        case .chiptune: return [0, 5, 3, 4]
        case .suspense: return [0, 0, 5, 4]
        case .quirky: return [0, 3, 4, 0]
        case .ambient: return [0, 3, 5, 3]
        }
    }

    /// Bars each chord lasts.
    var barsPerChord: Int { [.cinematic, .ambient, .suspense].contains(preset.style) ? 2 : 1 }

    func chordDegree(bar b: Int) -> Int { progression[(b / barsPerChord) % progression.count] }

    /// 0 = intro, 1 = full, 0.6 = breakdown, with the last bar flagged for a fill.
    func energy(bar b: Int) -> Double {
        if bars >= 6 && b < (bars >= 12 ? 2 : 1) { return 0.4 }
        if bars >= 16 {
            let mid = bars / 2
            if b >= mid - 2 && b < mid { return 0.6 }
        }
        return 1
    }

    func isLastBar(_ b: Int) -> Bool { b == bars - 1 }

    /// Time of a 16th-note step in a bar, with swing on the off-16ths.
    func time(bar b: Int, step: Int, swing: Double = 0) -> Double {
        var t = Double(b) * bar + Double(step) * beat / 4
        if step % 2 == 1 { t += swing * beat / 4 }
        return t
    }

    func playable(_ t: Double) -> Bool { t < end - 0.02 }

    func hz(_ midi: Int) -> Double { Synth.hz(midi: Double(midi)) }

    func cached(_ key: String, _ make: () -> [Float]) -> [Float] {
        if let hit = cache.store[key] { return hit }
        let made = make()
        cache.store[key] = made
        return made
    }

    mutating func random() -> Double { Double.random(in: 0..<1, using: &rng) }

    mutating func place(_ sound: [Float], _ t: Double, _ gain: Float, pan: Float = 0, reverb: Float = 0, pump: Bool = false) {
        guard playable(t) else { return }
        mix.add(sound, at: t, gain: gain, pan: pan, reverb: reverb, pump: pump)
    }

    mutating func hitKick(_ t: Double, gain: Float = 0.95, sound: [Float]) {
        guard playable(t) else { return }
        mix.add(sound, at: t, gain: gain)
        mix.kicks.append(Int(t * Synth.sr))
    }

    /// A two-bar hook from chord tones and scale steps, as (16th step, scale degree offset, length in 16ths).
    mutating func motif(steps: Int = 32, density: Double = 0.55) -> [(step: Int, degree: Int, length: Int)] {
        var notes: [(step: Int, degree: Int, length: Int)] = []
        var step = 0
        var current = 4
        while step < steps {
            if random() < density {
                let move = [-2, -1, 1, 2, 0, 3, -3][Int(random() * 7)]
                current = max(0, min(9, current + move))
                if step % 8 == 0 { current = [0, 2, 4, 7][Int(random() * 4)] }   // land on chord tones on strong beats
                let length = random() < 0.3 ? 4 : 2
                notes.append((step: step, degree: current, length: length))
                step += length
            } else {
                step += 2
            }
        }
        return notes
    }

    // MARK: Writing

    mutating func write() {
        switch preset.style {
        case .lofi: writeLofi()
        case .trap: writeTrap()
        case .upbeat: writeUpbeat()
        case .acoustic: writeAcoustic()
        case .synthwave: writeSynthwave()
        case .cinematic: writeCinematic()
        case .chiptune: writeChiptune()
        case .suspense: writeSuspense()
        case .quirky: writeQuirky()
        case .ambient: writeAmbient()
        }
        writeEnding()
    }

    /// Final hit on the downbeat at `end`: tonic chord, bass and (for groove styles) kick + cymbal.
    mutating func writeEnding() {
        let tonic = chord(0, seventh: preset.style == .lofi)
        let ring = tail + 0.2
        for (i, note) in tonic.enumerated() {
            let pan = Float(i - 1) * 0.35
            switch preset.style {
            case .lofi: mix.add(Synth.keys(hz(note), length: ring, wobble: 0.003), at: end, gain: 0.3, pan: pan, reverb: 0.4)
            case .acoustic, .quirky: mix.add(Synth.pluck(hz(note), length: ring, brightness: 0.6), at: end + Double(i) * 0.03, gain: 0.4, pan: pan, reverb: 0.3)
            case .chiptune: mix.add(Synth.tone(hz(note + 12), length: ring * 0.6, wave: .square(duty: 0.5), release: 0.3), at: end, gain: 0.12, pan: pan)
            default: mix.add(Synth.tone(hz(note), length: ring, wave: .saw, voices: 3, detuneCents: 12, cutoff: 2400, attack: 0.01, release: 0.5),
                             at: end, gain: 0.22, pan: pan, reverb: 0.5)
            }
        }
        let bassNote = preset.root - 24
        if ![.ambient, .suspense].contains(preset.style) {
            mix.add(Synth.kick(), at: end, gain: 0.9)
            mix.add(Synth.hat(open: true, seed: 99).map { $0 * 1.2 }, at: end, gain: 0.5, reverb: 0.5)
            mix.add(Synth.sineBass(hz(bassNote), length: ring), at: end, gain: 0.55)
        } else {
            mix.add(Synth.tone(hz(bassNote), length: ring, wave: .triangle, attack: 0.05, release: 0.6), at: end, gain: 0.5, reverb: 0.3)
            mix.add(Synth.bell(hz(preset.root + 12), length: ring), at: end, gain: 0.25, reverb: 0.6)
        }
    }

    mutating func writeLofi() {
        let kick = Synth.kick(decay: 0.32, top: 120, bottom: 50, drive: 1.2)
        let snare = Synth.snare(tone: 170, decay: 0.16).map { $0 * 0.8 }
        let hat = Synth.hat()
        reverbLevel = 0.8
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            let notes = chord(d, seventh: true)
            // Lazy chords: hit on 1, re-strike on the "and" of 3.
            for (i, n) in notes.enumerated() {
                let k = cached("keys\(n)") { Synth.keys(hz(n), length: bar * 0.95, wobble: 0.003, brightness: 0.7) }
                place(k, time(bar: b, step: 0) + Double(i) * 0.012, 0.16, pan: Float(i - 1) * 0.3, reverb: 0.25)
            }
            let bass = cached("bass\(d)") { Synth.sineBass(hz(preset.root - 24 + degree(d)), length: beat * 1.6) }
            if e >= 0.6 {
                place(bass, time(bar: b, step: 0), 0.55)
                place(bass, time(bar: b, step: 10, swing: 0.3), 0.45)
            }
            for s in stride(from: 0, to: 16, by: 2) {
                place(hat, time(bar: b, step: s, swing: 0.3), s % 4 == 0 ? 0.22 : 0.14, pan: 0.2)
            }
            if e >= 1 {
                hitKick(time(bar: b, step: 0), gain: 0.8, sound: kick)
                hitKick(time(bar: b, step: 7, swing: 0.3), gain: 0.55, sound: kick)
                hitKick(time(bar: b, step: 10), gain: 0.7, sound: kick)
                place(snare, time(bar: b, step: 4), 0.55, reverb: 0.15)
                place(snare, time(bar: b, step: 12), 0.55, reverb: 0.15)
            }
            // Sparse melody every other bar.
            if e >= 1 && b % 2 == 1 {
                let top = preset.root + 12 + degree(d + [4, 2, 6][b % 3])
                place(Synth.keys(hz(top), length: beat, wobble: 0.004), time(bar: b, step: 6, swing: 0.3), 0.12, pan: -0.2, reverb: 0.4)
            }
        }
    }

    mutating func writeTrap() {
        let kick = Synth.kick(decay: 0.5, top: 180, bottom: 48, drive: 2)
        let clap = Synth.clap()
        let hat = Synth.hat()
        let openHat = Synth.hat(open: true)
        let hook = motif(density: 0.45)
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            // Dark pad.
            for (i, n) in chord(d).enumerated() {
                let p = cached("pad\(n)") { Synth.tone(hz(n), length: bar, wave: .saw, voices: 3, detuneCents: 14, cutoff: 1400, attack: 0.3, release: 0.4) }
                place(p, time(bar: b, step: 0), 0.1, pan: Float(i - 1) * 0.5, reverb: 0.3)
            }
            if e >= 0.6 {
                // Bell hook.
                for note in hook where (b % 2 == 0 ? note.step < 16 : note.step >= 16) {
                    let midi = preset.root + 12 + degree(note.degree)
                    let s = cached("bell\(midi)") { Synth.bell(hz(midi), length: 1.0) }
                    place(s, time(bar: b, step: note.step % 16), 0.18, pan: 0.25, reverb: 0.35)
                }
            }
            guard e >= 1 else { continue }
            // 808 pattern with a glide.
            let bassMidi = preset.root - 24 + degree(d)
            let long = cached("808\(bassMidi)") { Synth.bass808(hz(bassMidi), length: beat * 1.4) }
            hitKick(time(bar: b, step: 0), sound: kick)
            place(long, time(bar: b, step: 0), 0.75)
            hitKick(time(bar: b, step: 11), gain: 0.8, sound: kick)
            place(Synth.bass808(hz(bassMidi), length: beat * 0.9, glideFrom: hz(bassMidi + 12)), time(bar: b, step: 11), 0.65)
            place(clap, time(bar: b, step: 8), 0.7, reverb: 0.2)
            // Hats: 8ths with 16th/32nd rolls.
            for s in stride(from: 0, to: 16, by: 2) {
                if (s == 6 || s == 14) && random() < 0.6 {
                    for r in 0..<4 { place(hat, time(bar: b, step: s) + Double(r) * beat / 8, 0.16, pan: -0.15) }
                } else {
                    place(hat, time(bar: b, step: s), 0.2, pan: -0.15)
                }
            }
            if b % 4 == 3 { place(openHat, time(bar: b, step: 14), 0.18) }
        }
    }

    mutating func writeUpbeat() {
        let kick = Synth.kick(decay: 0.36, top: 150, bottom: 52, drive: 1.8)
        let clap = Synth.clap()
        let hat = Synth.hat()
        let openHat = Synth.hat(open: true)
        let hook = motif(density: 0.6)
        pumpDepth = 0.55
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            // Pumping chord stabs on the off-beats.
            for s in [2, 6, 10, 14] {
                for (i, n) in chord(d).enumerated() {
                    let stab = cached("stab\(n)") { Synth.tone(hz(n), length: beat * 0.3, wave: .saw, voices: 2, detuneCents: 10, cutoff: 3200, release: 0.06) }
                    place(stab, time(bar: b, step: s), 0.09, pan: Float(i - 1) * 0.4, reverb: 0.2, pump: true)
                }
            }
            let bassMidi = preset.root - 24 + degree(d)
            if e >= 0.6 {
                for s in [2, 6, 10, 14] {
                    let bass = cached("bass\(bassMidi)") { Synth.sawBass(hz(bassMidi), length: beat * 0.35) }
                    place(bass, time(bar: b, step: s), 0.5, pump: true)
                }
                for note in hook where (b % 2 == 0 ? note.step < 16 : note.step >= 16) {
                    let midi = preset.root + 12 + degree(note.degree)
                    let lead = cached("lead\(midi)-\(note.length)") {
                        Synth.tone(hz(midi), length: beat / 4 * Double(note.length) * 0.9, wave: .square(duty: 0.3), voices: 2, detuneCents: 8, cutoff: 4200, release: 0.08)
                    }
                    place(lead, time(bar: b, step: note.step % 16), 0.14, pan: 0.1, reverb: 0.3)
                }
            }
            for s in stride(from: 2, to: 16, by: 4) { place(openHat, time(bar: b, step: s), 0.14) }
            for s in stride(from: 0, to: 16, by: 2) { place(hat, time(bar: b, step: s), 0.12, pan: 0.3) }
            guard e >= 0.6 else { continue }
            if e >= 1 { for s in [0, 4, 8, 12] { hitKick(time(bar: b, step: s), sound: kick) } }
            place(clap, time(bar: b, step: 4), 0.6, reverb: 0.15)
            place(clap, time(bar: b, step: 12), 0.6, reverb: 0.15)
            if isLastBar(b) && bars > 2 { for s in 12..<16 { place(clap, time(bar: b, step: s), 0.35) } }
        }
    }

    mutating func writeAcoustic() {
        let kick = Synth.kick(decay: 0.3, top: 110, bottom: 55, drive: 1.1)
        let clap = Synth.clap()
        let shaker = Synth.shaker()
        let hook = motif(density: 0.5)
        reverbLevel = 0.7
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            // Strummed pattern: D D U U D U.
            let strums = [0, 4, 6, 10, 12, 14]
            for (k, s) in strums.enumerated() {
                let up = k % 2 == 1 && s % 4 != 0
                let notes = chord(d) + [chord(d)[0] + 12]
                for (i, n) in (up ? notes.reversed() : notes).enumerated() {
                    let p = cached("pluck\(n)") { Synth.pluck(hz(n), length: beat * 1.2, brightness: 0.55) }
                    place(p, time(bar: b, step: s) + Double(i) * 0.008, up ? 0.1 : 0.15, pan: Float(i) * 0.15 - 0.2, reverb: 0.15)
                }
            }
            for s in stride(from: 0, to: 16, by: 2) { place(shaker, time(bar: b, step: s, swing: 0.15), s % 4 == 2 ? 0.2 : 0.12, pan: 0.4) }
            guard e >= 0.6 else { continue }
            let bassMidi = preset.root - 24 + degree(d)
            let bass = cached("bass\(bassMidi)") { Synth.pluck(hz(bassMidi), length: beat, brightness: 0.2, damping: 0.998) }
            place(bass, time(bar: b, step: 0), 0.6)
            place(bass, time(bar: b, step: 8), 0.5)
            if e >= 1 {
                hitKick(time(bar: b, step: 0), gain: 0.7, sound: kick)
                hitKick(time(bar: b, step: 8), gain: 0.6, sound: kick)
                place(clap, time(bar: b, step: 4), 0.45, reverb: 0.2)
                place(clap, time(bar: b, step: 12), 0.45, reverb: 0.2)
                for note in hook where (b % 2 == 0 ? note.step < 16 : note.step >= 16) {
                    let midi = preset.root + 12 + degree(note.degree)
                    let s = cached("mel\(midi)") { Synth.tone(hz(midi), length: beat * 0.45, wave: .triangle, attack: 0.02, release: 0.1, vibrato: 0.004) }
                    place(s, time(bar: b, step: note.step % 16), 0.2, pan: -0.15, reverb: 0.3)
                }
            }
        }
    }

    mutating func writeSynthwave() {
        let kick = Synth.kick(decay: 0.4, top: 140, bottom: 50, drive: 1.5)
        let snare = Synth.snare(tone: 200, decay: 0.25)
        let hat = Synth.hat()
        room = 0.9
        pumpDepth = 0.3
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            for (i, n) in chord(d).enumerated() {
                let pad = cached("pad\(n)") { Synth.tone(hz(n), length: bar, wave: .saw, voices: 4, detuneCents: 18, cutoff: 2200, attack: 0.15, release: 0.3) }
                place(pad, time(bar: b, step: 0), 0.08, pan: Float(i - 1) * 0.6, reverb: 0.3, pump: true)
            }
            // 16th arpeggio up the chord.
            let arpNotes = chord(d, octave: 1)
            for s in 0..<16 where e >= 0.6 || s % 2 == 0 {
                let n = arpNotes[s % arpNotes.count] + (s / 8) * 12
                let a = cached("arp\(n)") { Synth.tone(hz(n), length: beat / 4 * 0.6, wave: .saw, voices: 2, detuneCents: 6, cutoff: 3000, release: 0.05) }
                place(a, time(bar: b, step: s), 0.07, pan: s % 2 == 0 ? -0.3 : 0.3, reverb: 0.15)
            }
            let bassMidi = preset.root - 24 + degree(d)
            if e >= 0.6 {
                for s in stride(from: 0, to: 16, by: 2) {
                    let bass = cached("bass\(bassMidi)") { Synth.sawBass(hz(bassMidi), length: beat * 0.4, cutoff: 400, envAmount: 600) }
                    place(bass, time(bar: b, step: s), 0.45, pump: true)
                }
            }
            guard e >= 1 else { continue }
            for s in [0, 8] { hitKick(time(bar: b, step: s), sound: kick) }
            hitKick(time(bar: b, step: 10), gain: 0.6, sound: kick)
            place(snare, time(bar: b, step: 4), 0.6, reverb: 0.6)
            place(snare, time(bar: b, step: 12), 0.6, reverb: 0.6)
            for s in stride(from: 0, to: 16, by: 2) { place(hat, time(bar: b, step: s), 0.12, pan: 0.25) }
        }
    }

    mutating func writeCinematic() {
        room = 0.93
        reverbLevel = 1.3
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            if b % barsPerChord == 0 {
                for (i, n) in (chord(d) + [chord(d)[0] - 12]).enumerated() {
                    let strings = cached("str\(n)") {
                        Synth.tone(hz(n), length: bar * Double(barsPerChord), wave: .saw, voices: 4, detuneCents: 10, cutoff: 1800, attack: 0.8, release: 1.0, vibrato: 0.003)
                    }
                    place(strings, time(bar: b, step: 0), 0.1, pan: Float(i % 3 - 1) * 0.5, reverb: 0.5)
                }
                let low = preset.root - 24 + degree(d)
                place(cached("low\(low)") { Synth.tone(hz(low), length: bar * Double(barsPerChord), wave: .saw, voices: 2, detuneCents: 6, cutoff: 500, attack: 0.5, release: 0.8) },
                      time(bar: b, step: 0), 0.3)
            }
            // Ostinato that grows with the piece.
            let progress = Double(b) / Double(max(1, bars - 1))
            if e >= 0.6 {
                let notes = chord(d, octave: 1)
                for s in stride(from: 0, to: 16, by: progress > 0.5 ? 2 : 4) {
                    let n = notes[(s / 2) % notes.count]
                    let p = cached("ost\(n)") { Synth.pluck(hz(n), length: beat * 0.4, brightness: 0.7) }
                    place(p, time(bar: b, step: s), 0.14, pan: 0.3, reverb: 0.4)
                }
            }
            if e >= 1 {
                // Taiko-style toms on the big beats, more as it builds.
                let toms = Synth.tom(pitch: 70, decay: 0.9)
                place(toms, time(bar: b, step: 0), 0.9, reverb: 0.4)
                if progress > 0.3 { place(toms, time(bar: b, step: 8), 0.7, reverb: 0.4) }
                if progress > 0.6 {
                    let high = Synth.tom(pitch: 110, decay: 0.5)
                    for s in [12, 14] { place(high, time(bar: b, step: s), 0.5, pan: -0.3, reverb: 0.4) }
                }
            }
        }
    }

    mutating func writeChiptune() {
        let hook = motif(density: 0.75)
        var noise = Synth.Noise(seed: preset.seed &+ 9)
        let snareChip: [Float] = (0..<Synth.samples(0.12)).map { i in noise.next() * Float(exp(-Double(i) / Synth.sr * 30)) }
        var hatChip: [Float] = (0..<Synth.samples(0.03)).map { i in noise.next() * Float(exp(-Double(i) / Synth.sr * 120)) }
        Synth.bitcrush(&hatChip, bits: 4, hold: 3)
        let kickChip = Synth.tone(70, length: 0.08, wave: .triangle, release: 0.02, decayPerSecond: 20)
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            // Triangle bass in 8ths, octave jumps.
            let bassMidi = preset.root - 12 + degree(d)
            for s in stride(from: 0, to: 16, by: 2) {
                let n = bassMidi + (s % 4 == 2 ? 12 : 0)
                place(cached("tri\(n)") { Synth.tone(hz(n), length: beat / 2 * 0.85, wave: .triangle, release: 0.01) }, time(bar: b, step: s), 0.4)
            }
            // Square arpeggio (the classic fake chord).
            let notes = chord(d, octave: 1)
            for s in 0..<16 where e >= 0.6 {
                let n = notes[s % 3]
                place(cached("arp\(n)") { Synth.tone(hz(n), length: beat / 4 * 0.9, wave: .square(duty: 0.25), release: 0.005) }, time(bar: b, step: s), 0.06, pan: -0.2)
            }
            if e >= 1 {
                for note in hook where (b % 2 == 0 ? note.step < 16 : note.step >= 16) {
                    let midi = preset.root + 12 + degree(note.degree)
                    let lead = cached("sq\(midi)-\(note.length)") {
                        Synth.tone(hz(midi), length: beat / 4 * Double(note.length) * 0.9, wave: .square(duty: 0.5), release: 0.01, vibrato: 0.006)
                    }
                    place(lead, time(bar: b, step: note.step % 16), 0.13, pan: 0.2)
                }
                for s in [0, 8] { hitKick(time(bar: b, step: s), gain: 0.8, sound: kickChip) }
                for s in [4, 12] { place(snareChip, time(bar: b, step: s), 0.35) }
                for s in stride(from: 2, to: 16, by: 4) { place(hatChip, time(bar: b, step: s), 0.2) }
            }
        }
    }

    mutating func writeSuspense() {
        room = 0.95
        reverbLevel = 1.4
        let tick = Synth.hat().map { $0 * 0.8 }
        let pulse = Synth.kick(decay: 0.6, top: 70, bottom: 38, drive: 1.1)
        // Drone across the whole piece.
        let drone = Synth.tone(hz(preset.root - 24), length: end, wave: .saw, voices: 3, detuneCents: 8, cutoff: 260, attack: 2.0, release: 0.5)
        mix.add(drone, at: 0, gain: 0.35, reverb: 0.2)
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            if b % barsPerChord == 0 {
                for (i, n) in chord(d).enumerated() {
                    place(cached("pad\(n)") { Synth.tone(hz(n), length: bar * 2, wave: .triangle, voices: 2, detuneCents: 25, cutoff: 1500, attack: 1.2, release: 1.0) },
                          time(bar: b, step: 0), 0.12, pan: Float(i - 1) * 0.6, reverb: 0.5)
                }
            }
            // Clock ticks; heartbeat pulses when it builds.
            for s in stride(from: 0, to: 16, by: 4) { place(tick, time(bar: b, step: s), s % 8 == 0 ? 0.25 : 0.15, pan: s % 8 == 0 ? -0.4 : 0.4) }
            if e >= 1 {
                hitKick(time(bar: b, step: 0), gain: 0.7, sound: pulse)
                hitKick(time(bar: b, step: 3), gain: 0.45, sound: pulse)
            }
            // A dissonant bell now and then (minor second against the root).
            if b % 2 == 1 {
                place(Synth.bell(hz(preset.root + 13), length: 2, ratio: 2.76), time(bar: b, step: 8), 0.12, pan: 0.5, reverb: 0.7)
            }
        }
    }

    mutating func writeQuirky() {
        let kick = Synth.kick(decay: 0.25, top: 130, bottom: 60, drive: 1.2)
        let snap = Synth.clap().map { $0 * 0.8 }
        let hook = motif(density: 0.7)
        for b in 0..<bars {
            let e = energy(bar: b)
            let d = chordDegree(bar: b)
            // Oom-pah: low pizzicato bass on the beat, staccato chord on the off-beat.
            let bassMidi = preset.root - 24 + degree(d)
            for s in [0, 8] {
                place(cached("bass\(bassMidi)") { Synth.tone(hz(bassMidi), length: beat * 0.25, wave: .square(duty: 0.4), cutoff: 900, release: 0.05) },
                      time(bar: b, step: s), 0.45)
            }
            for s in [4, 12] {
                place(cached("bass5\(bassMidi)") { Synth.tone(hz(bassMidi + 7), length: beat * 0.25, wave: .square(duty: 0.4), cutoff: 900, release: 0.05) },
                      time(bar: b, step: s), 0.35)
                for (i, n) in chord(d).enumerated() {
                    place(cached("pizz\(n)") { Synth.pluck(hz(n), length: beat * 0.18, brightness: 0.8, damping: 0.985) },
                          time(bar: b, step: s + 2), 0.16, pan: Float(i - 1) * 0.4)
                }
            }
            if e >= 0.6 {
                for note in hook where (b % 2 == 0 ? note.step < 16 : note.step >= 16) {
                    let midi = preset.root + 12 + degree(note.degree)
                    place(cached("mallet\(midi)") { Synth.bell(hz(midi), length: 0.5, ratio: 4) }, time(bar: b, step: note.step % 16), 0.2, pan: 0.2, reverb: 0.15)
                }
            }
            if e >= 1 {
                hitKick(time(bar: b, step: 0), gain: 0.6, sound: kick)
                place(snap, time(bar: b, step: 4), 0.4)
                place(snap, time(bar: b, step: 12), 0.4)
            }
        }
    }

    mutating func writeAmbient() {
        room = 0.95
        reverbLevel = 1.5
        for b in 0..<bars where b % barsPerChord == 0 {
            let d = chordDegree(bar: b)
            for (i, n) in (chord(d) + [chord(d)[1] + 12]).enumerated() {
                place(cached("pad\(n)") { Synth.tone(hz(n), length: bar * 2.2, wave: .triangle, voices: 3, detuneCents: 9, cutoff: 2600, attack: 1.5, release: 1.5) },
                      time(bar: b, step: 0), 0.13, pan: Float(i) * 0.4 - 0.6, reverb: 0.6)
            }
            place(Synth.sineBass(hz(preset.root - 24 + degree(d)), length: bar * 2), time(bar: b, step: 0), 0.3)
            // Bell sparkles.
            for k in 0..<3 {
                let pick = Int(random() * 4)
                let pan = Float(random() - 0.5)
                let n = preset.root + 24 + degree(d + [0, 2, 4, 6][pick])
                place(Synth.bell(hz(n), length: 2.5), time(bar: b, step: k * 5 + 2), 0.08, pan: pan, reverb: 0.8)
            }
        }
    }

    /// Lo-fi vinyl crackle and hiss.
    mutating func addTexture(_ out: inout [[Float]]) {
        guard preset.style == .lofi, let n = out.first?.count else { return }
        var noise = Synth.Noise(seed: preset.seed &+ 77)
        var low = Biquad.lowPass(frequency: 5000, sampleRate: Synth.sr)
        for i in 0..<n {
            var x = Float(low.process(Double(noise.next()))) * 0.006
            if noise.next() > 0.9993 { x += noise.next() * 0.12 }
            out[0][i] += x
            out[1][i] += x
        }
    }
}
