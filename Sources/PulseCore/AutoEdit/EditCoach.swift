import Foundation

/// Short-form (TikTok/Shorts/Reels) or long-form (YouTube) — the coach judges them differently.
public enum EditFormat: String, Codable, Sendable {
    case short
    case longForm

    /// Over 3 minutes, or a landscape edit over 90 s, is judged as a YouTube video.
    public static func of(_ timeline: Timeline) -> EditFormat {
        timeline.duration > 180 || (timeline.canvas.aspect > 1.2 && timeline.duration > 90) ? .longForm : .short
    }
}

public enum PerformanceTier: String, Codable, Sendable {
    case viral, strong, solid, needsWork, weak

    public init(score: Int) {
        switch score {
        case 85...: self = .viral
        case 70..<85: self = .strong
        case 55..<70: self = .solid
        case 40..<55: self = .needsWork
        default: self = .weak
        }
    }

    public var displayName: String {
        switch self {
        case .viral: return "Viral potential"
        case .strong: return "Strong"
        case .solid: return "Solid"
        case .needsWork: return "Needs work"
        case .weak: return "Weak"
        }
    }

    public var emoji: String {
        switch self {
        case .viral: return "🔥"
        case .strong: return "🚀"
        case .solid: return "👍"
        case .needsWork: return "🛠"
        case .weak: return "💤"
        }
    }
}

/// How well an edit is likely to do, predicted from the same entertainment signals that find clips
/// (energy, laughter, reactions, pacing, hook, ending) plus how finished the edit is. It's a guide,
/// not a promise: real performance depends on the audience, the title and luck.
public struct PerformancePrediction: Hashable, Sendable {
    public struct Factor: Hashable, Sendable {
        public var name: String
        public var value: Double
        public var note: String
    }

    public var score: Int
    public var factors: [Factor]
    public var format: EditFormat

    public var tier: PerformanceTier { PerformanceTier(score: score) }

    /// The two strongest factors, for "why this scores well".
    public var strengths: [Factor] { factors.filter { $0.value >= 0.7 }.sorted { $0.value > $1.value }.prefix(2).map { $0 } }
}

public struct EditSuggestion: Hashable, Identifiable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case tip, recommended, important
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// What the one-click "Fix" does (none = advice only).
    public enum Fix: Hashable, Sendable {
        case trimStart(Seconds)
        case trimEnd(Seconds)
        case removeDeadAir
        case addCaptions
        case addMusic
        case addZooms
        case addSoundEffects
        /// Copy this timeline range to the very start as a teaser.
        case coldOpen(TimeRange)
        case none

        public var buttonTitle: String? {
            switch self {
            case .trimStart: return "Trim Start"
            case .trimEnd: return "Trim End"
            case .removeDeadAir: return "Tighten"
            case .addCaptions: return "Add Captions"
            case .addMusic: return "Add Music"
            case .addZooms: return "Add Zooms"
            case .addSoundEffects: return "Add SFX"
            case .coldOpen: return "Add Hook"
            case .none: return nil
            }
        }
    }

    public var id: String
    public var title: String
    public var detail: String
    public var severity: Severity
    public var fix: Fix
    public var symbol: String
}

public struct EditReview: Hashable, Sendable {
    public var prediction: PerformancePrediction
    public var suggestions: [EditSuggestion]
}

/// Reviews an edit as you work: a performance prediction and concrete suggestions ("the first 2 s are
/// slow", "8 % dead air", "no captions"…), most with a one-click fix.
public enum EditCoach {
    public static func review(_ timeline: Timeline, analysis: MediaAnalysis?, signals precomputed: EngagementSignals? = nil) -> EditReview {
        let format = EditFormat.of(timeline)
        let duration = timeline.duration
        let program = Program(timeline: timeline, assetID: analysis?.assetID ?? timeline.origin?.assetID)
        let signals = precomputed ?? analysis.map {
            EngagementModel.compute(duration: $0.duration, audio: $0.audio, transcript: $0.transcript, visual: $0.visual)
        }
        var suggestions: [EditSuggestion] = []
        var factors: [PerformancePrediction.Factor] = []

        // Signals sampled along the edit (0.5 s steps).
        let step = 0.5
        var samples: [(t: Seconds, excitement: Double, speech: Double, silent: Bool)] = []
        var p95 = 0.3, p99 = 0.5
        if let signals, signals.count > 0, duration > 0 {
            p95 = Double(max(SeriesMath.percentile(signals.excitement, 0.95), 0.05))
            p99 = Double(max(SeriesMath.percentile(signals.excitement, 0.99), 0.08))
            let threshold = silenceThreshold(analysis?.audio)
            var t = step / 2
            while t < duration {
                if let s = program.sourceTime(at: t) {
                    let i = signals.index(at: s)
                    var silent = false
                    if let audio = analysis?.audio, audio.count > 0 {
                        silent = audio.rmsDB[audio.index(at: s)] < threshold && signals.speech[i] < 0.1
                    }
                    samples.append((t, Double(signals.excitement[i]), Double(signals.speech[i]), silent))
                }
                t += step
            }
        }
        let hasSignals = samples.count >= 4

        // Hook: the first 3 seconds.
        var hook = 0.5
        if hasSignals {
            let opening = samples.filter { $0.t < 3 }
            let energy = opening.map(\.excitement).reduce(0, +) / Double(max(opening.count, 1)) / p95
            let talks = (samples.filter { $0.t < 1.2 }.map(\.speech).max() ?? 0) > 0.3
            hook = (energy * 0.75 + (talks ? 0.25 : 0)).clamped(0, 1)
            // A slow start: find where things actually begin.
            let window = min(6, duration * 0.25)
            if let firstGood = samples.first(where: { $0.t < window && !$0.silent && ($0.excitement >= 0.55 * p95 || $0.speech > 0.5) }),
               firstGood.t > 1.2, format == .short {
                let cut = max(0, firstGood.t - 0.35)
                suggestions.append(EditSuggestion(id: "hook-trim", title: "Start \(String(format: "%.1f", cut)) s later",
                                                  detail: "The first seconds are slow. Viewers decide in about 2 seconds whether to keep watching.",
                                                  severity: .important, fix: .trimStart(cut), symbol: "scissors"))
            }
        }
        factors.append(.init(name: "Hook", value: hook, note: hook >= 0.7 ? "Grabs attention right away" : "Opening could hit harder"))

        // Energy & payoff.
        var energy = 0.5, payoff = 0.5
        if hasSignals {
            let sorted = samples.map(\.excitement).sorted(by: >)
            let top = sorted.prefix(max(1, sorted.count * 3 / 10))
            energy = (top.reduce(0, +) / Double(top.count) / p95).clamped(0, 1)
            payoff = ((sorted.first ?? 0) / p99).clamped(0, 1)
            if payoff < 0.6, let signals, signals.count > 0, SeriesMath.percentile(signals.excitement, 0.995) > Float(p95) {
                suggestions.append(EditSuggestion(id: "payoff", title: "Your biggest moment isn't in this edit",
                                                  detail: "The recording has a bigger peak elsewhere. Consider building around it.",
                                                  severity: .tip, fix: .none, symbol: "star"))
            }
            if format == .longForm && hook < 0.6, let best = samples.filter({ $0.t > 20 }).max(by: { $0.excitement < $1.excitement }) {
                let range = TimeRange(start: max(0, best.t - 3.5), end: min(duration, best.t + 2.5))
                suggestions.append(EditSuggestion(id: "cold-open", title: "Open with a fire hook",
                                                  detail: "Tease the best moment (at \(Timecode.short(best.t))) in the first seconds, then start the story.",
                                                  severity: .important, fix: .coldOpen(range), symbol: "flame"))
            }
        }
        factors.append(.init(name: "Energy", value: energy, note: energy >= 0.7 ? "High-energy throughout" : "Some flat stretches"))
        factors.append(.init(name: "Payoff", value: payoff, note: payoff >= 0.7 ? "Lands a big moment" : "No standout peak"))

        // Pacing: dead air in the edit.
        var pacing = 0.6
        if hasSignals {
            let dead = Double(samples.filter(\.silent).count) / Double(samples.count)
            pacing = (1 - max(0, dead - 0.03) * 5).clamped(0, 1)
            if dead > 0.06 {
                suggestions.append(EditSuggestion(id: "dead-air", title: "\(Int((dead * duration).rounded())) s of dead air",
                                                  detail: "Jump-cut the pauses to keep the pace up.",
                                                  severity: dead > 0.12 ? .important : .recommended, fix: .removeDeadAir, symbol: "waveform.path"))
            }
        }
        factors.append(.init(name: "Pacing", value: pacing, note: pacing >= 0.7 ? "Tight, no dead air" : "Pauses slow it down"))

        // Ending.
        var ending = 0.7
        if hasSignals {
            let tail = samples.filter { $0.t > duration - 1.6 }
            let silentTail = Double(tail.filter(\.silent).count) / Double(max(tail.count, 1))
            ending = (1 - silentTail * 0.7).clamped(0, 1)
            if silentTail > 0.6, duration > 4 {
                let quietFrom = samples.last(where: { !$0.silent })?.t ?? duration
                let trim = max(0, duration - quietFrom - 0.4)
                if trim > 0.5 {
                    suggestions.append(EditSuggestion(id: "ending", title: "Ends on silence",
                                                      detail: "End right after the reaction — trimming \(String(format: "%.1f", trim)) s makes it loop better.",
                                                      severity: .recommended, fix: .trimEnd(trim), symbol: "forward.end"))
                }
            }
        }
        factors.append(.init(name: "Ending", value: ending, note: ending >= 0.7 ? "Ends on the payoff" : "Trails off"))

        // Length for the platform.
        let length: Double
        switch format {
        case .short:
            switch duration {
            case ..<8: length = 0.5
            case 8..<15: length = 0.85
            case 15...60: length = 1
            case 60...90: length = 0.7
            default: length = 0.4
            }
            if duration > 75 {
                suggestions.append(EditSuggestion(id: "length", title: "Long for a short (\(Timecode.short(duration)))",
                                                  detail: "Retention drops after a minute on TikTok and Shorts. Aim for 20–60 s.",
                                                  severity: .important, fix: .none, symbol: "timer"))
            }
        case .longForm:
            let minutes = duration / 60
            length = minutes < 6 ? 0.55 : (minutes <= 22 ? 1 : 0.75)
            if minutes < 6 {
                suggestions.append(EditSuggestion(id: "length", title: "Short for a YouTube video",
                                                  detail: "8–20 minutes tends to do best for stream highlights.", severity: .tip, fix: .none, symbol: "timer"))
            }
        }
        factors.append(.init(name: "Length", value: length, note: length >= 0.9 ? "Right length for the platform" : "Length isn't ideal"))

        // Polish: captions, zooms, music and effects — without overdoing it.
        let hasCaptions = timeline.captions.map { $0.isEnabled && !$0.words.isEmpty } ?? false
        let zoomCount = timeline.allClips.reduce(0) { $0 + max(0, $1.transform.zoom.keyframes.count - 1) / 2 }
        let hasMusic = timeline.allClips.contains { $0.role == .music && $0.isEnabled }
        let hasSFX = timeline.allClips.contains { $0.role == .soundEffect && $0.isEnabled }
        let zoomsPerMinute = Double(zoomCount) / max(duration / 60, 0.25)
        var polish = 0.0
        switch format {
        case .short:
            polish = (hasCaptions ? 0.5 : 0) + (zoomCount > 0 ? 0.3 : 0) + (hasMusic || hasSFX ? 0.2 : 0)
            if !hasCaptions {
                suggestions.append(EditSuggestion(id: "captions", title: "Add captions",
                                                  detail: "Most people scroll with the sound off — captions keep them watching.",
                                                  severity: .important, fix: .addCaptions, symbol: "captions.bubble"))
            }
            if zoomCount == 0 && duration > 10 {
                suggestions.append(EditSuggestion(id: "zooms", title: "Punch in on the big moments",
                                                  detail: "A quick zoom on the reaction makes it hit harder.", severity: .recommended, fix: .addZooms, symbol: "plus.magnifyingglass"))
            }
            if !hasMusic && energy < 0.55 {
                suggestions.append(EditSuggestion(id: "music", title: "Add a music bed", detail: "A quiet track under calmer stretches lifts the energy.",
                                                  severity: .tip, fix: .addMusic, symbol: "music.note"))
            }
            if zoomsPerMinute > 10 {
                suggestions.append(EditSuggestion(id: "over-zoom", title: "Ease off the zooms",
                                                  detail: "\(zoomCount) zooms in \(Timecode.short(duration)) feels busy. Keep them for the big beats.",
                                                  severity: .tip, fix: .none, symbol: "minus.magnifyingglass"))
            }
        case .longForm:
            polish = (hasCaptions ? 0.25 : 0) + (zoomCount > 0 ? 0.3 : 0) + (hasMusic ? 0.3 : 0) + (hasSFX ? 0.15 : 0)
            if !hasMusic {
                suggestions.append(EditSuggestion(id: "music", title: "Add background music",
                                                  detail: "A ducked music bed makes a stream edit feel like a produced video.",
                                                  severity: .recommended, fix: .addMusic, symbol: "music.note"))
            }
            if zoomCount == 0 {
                suggestions.append(EditSuggestion(id: "zooms", title: "Add zooms on reactions",
                                                  detail: "Occasional punch-ins on the funniest reactions (not every line).", severity: .recommended, fix: .addZooms, symbol: "plus.magnifyingglass"))
            }
            if !hasSFX {
                suggestions.append(EditSuggestion(id: "sfx", title: "Add a few sound effects",
                                                  detail: "A whoosh between sections and a hit on the big moments — sparingly.", severity: .tip, fix: .addSoundEffects, symbol: "speaker.wave.2"))
            }
            if !hasCaptions {
                suggestions.append(EditSuggestion(id: "captions", title: "Add captions",
                                                  detail: "Subtitles help viewers who watch muted and boost search.", severity: .tip, fix: .addCaptions, symbol: "captions.bubble"))
            }
            if zoomsPerMinute > 4 {
                suggestions.append(EditSuggestion(id: "over-zoom", title: "Ease off the zooms",
                                                  detail: "More than a few zooms a minute starts to feel over-edited.", severity: .tip, fix: .none, symbol: "minus.magnifyingglass"))
            }
        }
        factors.append(.init(name: "Polish", value: polish.clamped(0, 1), note: polish >= 0.7 ? "Captions, zooms and sound in place" : "Missing finishing touches"))

        // Weighted score.
        let weights: [String: Double] = format == .short
            ? ["Hook": 0.24, "Energy": 0.2, "Payoff": 0.16, "Pacing": 0.14, "Ending": 0.08, "Length": 0.08, "Polish": 0.1]
            : ["Hook": 0.18, "Energy": 0.2, "Payoff": 0.1, "Pacing": 0.22, "Ending": 0.05, "Length": 0.1, "Polish": 0.15]
        let raw = factors.reduce(0) { $0 + (weights[$1.name] ?? 0) * $1.value }
        let score = Int((pow(raw.clamped(0, 1), 0.85) * 100).rounded()).clamped(1, 99)
        suggestions.sort { $0.severity != $1.severity ? $0.severity > $1.severity : $0.id < $1.id }
        return EditReview(prediction: PerformancePrediction(score: score, factors: factors, format: format), suggestions: suggestions)
    }

    static func silenceThreshold(_ audio: AudioFeatureSeries?) -> Float {
        guard let audio, audio.count > 0 else { return -50 }
        let floor = SeriesMath.percentile(audio.rmsDB.values, 0.1)
        let speech = SeriesMath.percentile(audio.rmsDB.values, 0.9)
        return min(floor + max((speech - floor) * 0.25, 6), -28)
    }

    /// Timeline → source mapping for the edit's main picture (or sound, for audio-only edits).
    struct Program {
        var segments: [TimelineClip] = []

        init(timeline: Timeline, assetID: UUID?) {
            let id = assetID ?? timeline.allClips.compactMap(\.assetID).first
            guard let id else { return }
            let candidates = timeline.tracks.filter { $0.kind == .video } + timeline.tracks.filter { $0.kind == .audio }
            for track in candidates {
                let clips = track.clips.filter { $0.assetID == id && $0.isEnabled && $0.role != .webcam }
                if !clips.isEmpty {
                    segments = clips
                    return
                }
            }
        }

        func sourceTime(at t: Seconds) -> Seconds? {
            segments.first { $0.timelineRange.contains(t) }?.sourceTime(atTimeline: t)
        }
    }
}

extension Timeline {
    /// Copies `range` of the edit to the very start as a cold open (a teaser of the best moment), shifting
    /// everything else later. Music and sound effects aren't duplicated.
    public mutating func insertColdOpen(from range: TimeRange) throws {
        guard range.duration > 0.3, range.end <= duration + 0.01 else { throw TimelineEditError.timeOutsideClip }
        var cut = self
        _ = try? cut.split(at: range.start)
        _ = try? cut.split(at: range.end)
        let length = range.duration
        var groupMap: [UUID: UUID] = [:]
        for ti in tracks.indices {
            for ci in tracks[ti].clips.indices { tracks[ti].clips[ci].start += length }
        }
        for ti in tracks.indices where ti < cut.tracks.count {
            let pieces = cut.tracks[ti].clips.filter {
                $0.start >= range.start - TimeRange.epsilon && $0.end <= range.end + TimeRange.epsilon
                    && $0.role != .music && $0.role != .soundEffect
            }
            for piece in pieces {
                var copy = piece
                copy.id = UUID()
                copy.start = piece.start - range.start
                copy.aiGenerated = true
                if let g = piece.linkGroup {
                    let fresh = groupMap[g] ?? UUID()
                    groupMap[g] = fresh
                    copy.linkGroup = fresh
                }
                tracks[ti].clips.append(copy)
            }
            tracks[ti].sortClips()
        }
        for i in markers.indices { markers[i].time += length }
        for i in layoutChanges.indices { layoutChanges[i].time += length }
        markers.append(Marker(time: 0, name: "Cold Open", note: "Teaser of the best moment", color: .orange, aiGenerated: true))
        modifiedAt = Date()
    }
}
