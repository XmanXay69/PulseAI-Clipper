import Foundation

/// A dialogue-first mix (#761): the voice is the reference, and game sound, music and effects are placed
/// under it so speech always wins. Bad audio loses more viewers than bad cuts, and "I can't hear what they
/// said over the music" is the commonest complaint there is.
///
/// The assistant only moves clip gain and switches ducking on. It never touches the sound itself, and every
/// change is listed in words so it can be judged and undone.
public enum MixAssistant {
    public enum Stem: String, CaseIterable, Sendable {
        case voice, game, music, effects

        public var displayName: String {
            switch self {
            case .voice: return "Voice"
            case .game: return "Game sound"
            case .music: return "Music"
            case .effects: return "Sound effects"
            }
        }
    }

    /// What one clip gets.
    public struct Adjustment: Hashable, Sendable {
        public var clipID: UUID
        /// Decibels added to the clip's gain.
        public var gain: Double
        /// Switch ducking under dialogue on, by this many decibels (nil = leave ducking as it is).
        public var duck: Double?
    }

    public struct Change: Hashable, Identifiable, Sendable {
        public var stem: Stem
        public var text: String
        public var id: String { stem.rawValue + text }
    }

    public struct Plan: Hashable, Sendable {
        public var adjustments: [Adjustment]
        /// What will change and why, one line per stem that needs anything.
        public var changes: [Change]
        /// The voice's level the rest was placed against, in dBFS; nil when there is no voice to mix around.
        public var voiceLevel: Double?

        public var isEmpty: Bool { adjustments.isEmpty }

        /// "Music down 6 dB · game sound ducks under talking"
        public var summary: String { changes.map(\.text).joined(separator: " ") }
    }

    /// Where each stem belongs relative to the voice, in decibels below it.
    static let musicUnder = 20.0, gameUnder = 10.0, effectsUnder = 4.0
    /// A comfortable speaking level, and how far from it the voice may sit before it is moved.
    static let voiceTarget = -18.0

    /// Which stem a clip is. A recording's own sound is the voice unless a separate microphone clip plays over
    /// it, in which case it is the game.
    static func stem(of clip: TimelineClip, micRanges: [TimeRange]) -> Stem {
        switch clip.role {
        case .music: return .music
        case .soundEffect: return .effects
        case .microphone: return .voice
        default:
            let covered = micRanges.reduce(0.0) { $0 + max(0, min($1.end, clip.end) - max($1.start, clip.start)) }
            return covered > clip.duration * 0.5 ? .game : .voice
        }
    }

    /// `levels` gives each recording's typical loudness when it is making sound, in dBFS (from its analysis or
    /// its waveform). Clips of a recording that isn't in it are left alone: nothing is guessed.
    public static func plan(timeline: Timeline, levels: [UUID: Double]) -> Plan {
        let tracks = timeline.tracks.filter { $0.kind == .audio && !$0.isMuted }
        let clips = tracks.flatMap(\.clips).filter { $0.isEnabled && !$0.audio.isMuted && $0.assetID != nil }
        let micRanges = clips.filter { $0.role == .microphone }.map(\.timelineRange)
        // Each clip's level as it plays now: the recording's own, moved by the clip's volume and gain.
        var heard: [(clip: TimelineClip, stem: Stem, level: Double)] = []
        for clip in clips {
            guard let assetID = clip.assetID, let level = levels[assetID] else { continue }
            let volume = max(clip.audio.volume.value, 0.0001)
            heard.append((clip, stem(of: clip, micRanges: micRanges), level + 20 * log10(volume) + clip.audio.gainDB))
        }
        let voices = heard.filter { $0.stem == .voice }
        let voiceSeconds = voices.reduce(0.0) { $0 + $1.clip.duration }
        guard voiceSeconds > 0 else { return Plan(adjustments: [], changes: [], voiceLevel: nil) }
        var voice = voices.reduce(0.0) { $0 + $1.level * $1.clip.duration } / voiceSeconds

        var adjustments: [UUID: Adjustment] = [:]
        var changes: [Change] = []
        func add(_ clip: TimelineClip, gain: Double = 0, duck: Double? = nil) {
            var entry = adjustments[clip.id] ?? Adjustment(clipID: clip.id, gain: 0, duck: nil)
            entry.gain += gain
            if let duck { entry.duck = duck }
            adjustments[clip.id] = entry
        }
        func decibels(_ value: Double) -> String { "\(Int(abs(value).rounded())) dB" }

        // The voice first: to a normal speaking level when it is far off, and its clips evened out.
        let shift = abs(voiceTarget - voice) > 5 ? (voiceTarget - voice).clamped(-12, 12) : 0
        var evened = 0
        for item in voices {
            let own = abs(item.level - voice) > 4 ? (voice - item.level).clamped(-9, 9) : 0
            if own != 0 { evened += 1 }
            if shift != 0 || own != 0 { add(item.clip, gain: shift + own) }
        }
        if shift != 0 {
            changes.append(Change(stem: .voice, text: "Voice \(shift > 0 ? "up" : "down") \(decibels(shift)): it sat at \(Int(voice.rounded())) dB, \(shift > 0 ? "quiet" : "hot") for speech."))
        }
        if evened > 0 {
            changes.append(Change(stem: .voice, text: "\(evened) voice clip\(evened == 1 ? "" : "s") evened out with the rest."))
        }
        voice += shift

        // Then everything else, placed under it.
        func place(_ stem: Stem, under: Double, tolerance: Double, duck: Double?) {
            let items = heard.filter { $0.stem == stem }
            guard !items.isEmpty else { return }
            let target = voice - under
            var lowered: [Double] = [], raised: [Double] = [], ducked = 0
            for item in items {
                var gain = 0.0
                if item.level > target + tolerance {
                    gain = (target - item.level).clamped(-24, 0)
                    lowered.append(gain)
                } else if stem == .music, item.level < target - 12 {
                    // A bed nobody can hear isn't doing its job either.
                    gain = (target - 4 - item.level).clamped(0, 12)
                    raised.append(gain)
                }
                let needsDuck = duck != nil && !item.clip.audio.duckUnderDialogue
                if needsDuck { ducked += 1 }
                if gain != 0 || needsDuck { add(item.clip, gain: gain, duck: needsDuck ? duck : nil) }
            }
            var parts: [String] = []
            if let most = lowered.min() {
                parts.append("down \(decibels(most)) to sit \(Int(under)) dB under the voice")
            }
            if let most = raised.max() { parts.append("up \(decibels(most)) so it can be heard") }
            if ducked > 0, let duck { parts.append("set to drop another \(decibels(duck)) while someone talks") }
            if !parts.isEmpty { changes.append(Change(stem: stem, text: "\(stem.displayName) \(parts.joined(separator: " and ")).")) }
        }
        place(.game, under: gameUnder, tolerance: 2, duck: -9)
        place(.music, under: musicUnder, tolerance: 2, duck: -6)
        place(.effects, under: effectsUnder, tolerance: 1, duck: nil)

        let ordered = adjustments.values.sorted { $0.clipID.uuidString < $1.clipID.uuidString }
        return Plan(adjustments: ordered, changes: changes, voiceLevel: voice)
    }

    /// Makes the plan's changes. Returns how many clips were touched.
    @discardableResult
    public static func apply(_ plan: Plan, to timeline: inout Timeline) -> Int {
        let byClip = Dictionary(plan.adjustments.map { ($0.clipID, $0) }, uniquingKeysWith: { first, _ in first })
        var touched = 0
        for ti in timeline.tracks.indices {
            for ci in timeline.tracks[ti].clips.indices {
                guard let change = byClip[timeline.tracks[ti].clips[ci].id] else { continue }
                timeline.tracks[ti].clips[ci].audio.gainDB = (timeline.tracks[ti].clips[ci].audio.gainDB + change.gain).clamped(-48, 24)
                if let duck = change.duck {
                    timeline.tracks[ti].clips[ci].audio.duckUnderDialogue = true
                    timeline.tracks[ti].clips[ci].audio.duckAmountDB = duck
                }
                touched += 1
            }
        }
        if touched > 0 { timeline.modifiedAt = Date() }
        return touched
    }

    /// A recording's typical level when it is making sound, from its analysis: the middle of everything
    /// louder than near-silence. Nil when it is silent throughout.
    public static func level(of audio: AudioFeatureSeries) -> Double? {
        let active = audio.rmsDB.values.filter { $0 > -50 }
        guard active.count >= 5 else { return nil }
        return Double(active.sorted()[active.count / 2])
    }

    /// The same from waveform peaks (0…1 amplitudes), for sounds that were never analyzed.
    public static func level(ofPeaks peaks: [Float]) -> Double? {
        let active = peaks.filter { $0 > 0.003 }
        guard active.count >= 5 else { return nil }
        // A peak sits about 3 dB over the level it came from.
        return 20 * log10(Double(active.sorted()[active.count / 2])) - 3
    }
}
