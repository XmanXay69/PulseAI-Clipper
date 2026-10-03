import Foundation

public enum ClipLengthPreset: String, Codable, CaseIterable, Sendable {
    case short15
    case medium30
    case long60
    case custom

    public var seconds: Seconds? {
        switch self {
        case .short15: return 15
        case .medium30: return 30
        case .long60: return 60
        case .custom: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .short15: return "15 sec"
        case .medium30: return "30 sec"
        case .long60: return "60 sec"
        case .custom: return "Custom"
        }
    }
}

public struct ClipGenerationSettings: Codable, Hashable, Sendable {
    /// Target clip length (10…90 s). The generator may land ±15–20% to find natural boundaries.
    public var targetDuration: Seconds
    /// 0 = only the strongest moments, 1 = many candidates.
    public var aggressiveness: Double
    /// Candidates below this AI Potential are hidden.
    public var minimumPotential: Int
    /// Explicit cap; nil = scaled with recording length.
    public var maxCandidates: Int?
    /// Varies title picks on regenerate.
    public var seed: Int

    public init(targetDuration: Seconds = 30, aggressiveness: Double = 0.5, minimumPotential: Int = 20, maxCandidates: Int? = nil, seed: Int = 0) {
        self.targetDuration = targetDuration.clamped(10, 90)
        self.aggressiveness = aggressiveness.clamped(0, 1)
        self.minimumPotential = minimumPotential
        self.maxCandidates = maxCandidates
        self.seed = seed
    }
}

/// Inputs for clip generation (everything optional except duration so it degrades gracefully:
/// audio-only works, transcript-only works, both is best).
public struct ClipGenerationInput: Sendable {
    public var assetID: UUID
    public var duration: Seconds
    public var audio: AudioFeatureSeries?
    public var transcript: Transcript?
    public var visual: VisualFeatureSeries?
    public var profile: ContentProfile
    public var chat: ChatLog?

    public init(assetID: UUID, duration: Seconds, audio: AudioFeatureSeries?, transcript: Transcript?, visual: VisualFeatureSeries?, profile: ContentProfile = .unknown,
                chat: ChatLog? = nil) {
        self.chat = chat
        self.assetID = assetID
        self.duration = duration
        self.audio = audio
        self.transcript = transcript
        self.visual = visual
        self.profile = profile
    }

    public init(analysis: MediaAnalysis) {
        self.init(assetID: analysis.assetID, duration: analysis.duration, audio: analysis.audio, transcript: analysis.transcript, visual: analysis.visual, profile: analysis.profile,
                  chat: analysis.chat)
    }
}

/// Finds entertaining moments and shapes them into HOOK → CONTEXT → PAYOFF → END clips.
public struct ClipGenerator: Sendable {
    public var input: ClipGenerationInput
    public var settings: ClipGenerationSettings
    public let signals: EngagementSignals
    let sentences: [TranscriptSentence]
    let excitementP95: Float
    let excitementP99: Float
    let silenceThreshold: Float

    public init(input: ClipGenerationInput, settings: ClipGenerationSettings) {
        self.input = input
        self.settings = settings
        self.signals = EngagementModel.compute(duration: input.duration, audio: input.audio, transcript: input.transcript, visual: input.visual, chat: input.chat,
                                               gameplay: input.profile == .gameplay || input.profile == .gameplayWithFacecam)
        self.sentences = input.transcript?.sentences() ?? []
        self.excitementP95 = max(SeriesMath.percentile(signals.excitement, 0.95), 0.05)
        self.excitementP99 = max(SeriesMath.percentile(signals.excitement, 0.99), 0.08)
        if let audio = input.audio, audio.count > 0 {
            let floor = SeriesMath.percentile(audio.rmsDB.values, 0.1)
            let speech = SeriesMath.percentile(audio.rmsDB.values, 0.9)
            silenceThreshold = min(floor + max((speech - floor) * 0.25, 6), -28)
        } else {
            silenceThreshold = -50
        }
    }

    /// Default number of candidates for a recording: ~13 per hour at medium aggressiveness.
    public var candidateBudget: Int {
        if let cap = settings.maxCandidates { return max(1, cap) }
        let hours = input.duration / 3600
        let perHour = 6 + 14 * settings.aggressiveness
        return Int((hours * perHour).rounded()).clamped(3, 60)
    }

    // MARK: Generate

    public func generate() -> [ClipCandidate] {
        let d = settings.targetDuration
        guard input.duration >= min(d * 0.5, 8) else { return [] }
        if input.duration <= d * 1.1 {
            // The whole recording is already short-form length.
            return [makeCandidate(range: TimeRange(start: 0, end: input.duration), payoff: peakTime(in: TimeRange(start: 0, end: input.duration)))]
        }
        let thresholdPercentile = 0.7 - 0.3 * settings.aggressiveness
        let threshold = SeriesMath.percentile(signals.excitement, thresholdPercentile)
        let minDistance = max(1, Int(d * 0.7 / signals.step))
        let peakIndices = SeriesMath.peaks(signals.excitement, threshold: threshold, minDistance: minDistance)
        let budget = candidateBudget
        var candidates: [ClipCandidate] = []
        for idx in peakIndices.prefix(budget * 3) {
            let peak = (Double(idx) + 0.5) * signals.step
            let range = window(forPayoff: peak)
            guard range.duration >= min(d * 0.5, 8) else { continue }
            candidates.append(makeCandidate(range: range, payoff: peak))
        }
        // Non-maximum suppression: keep the better of overlapping clips.
        candidates.sort { $0.scores.weighted > $1.scores.weighted }
        var kept: [ClipCandidate] = []
        for c in candidates where !kept.contains(where: { $0.range.iou(c.range) > 0.3 || $0.range.contains(c.payoffTime) }) {
            kept.append(c)
            if kept.count >= budget { break }
        }
        return kept
            .filter { $0.potential >= settings.minimumPotential }
            .sorted { $0.potential > $1.potential }
    }

    /// Candidate for a user-chosen range (e.g. "Create clip from sentence").
    public func candidate(for range: TimeRange) -> ClipCandidate {
        makeCandidate(range: range.clamped(to: TimeRange(start: 0, end: input.duration)), payoff: peakTime(in: range))
    }

    /// Recomputes a candidate around the same payoff, with a new length (Shorten / Extend / Regenerate).
    public func reshape(_ candidate: ClipCandidate, targetDuration: Seconds? = nil, generation: Int? = nil) -> ClipCandidate {
        var copy = self
        if let targetDuration { copy.settings.targetDuration = targetDuration.clamped(10, 90) }
        let gen = generation ?? candidate.generation
        copy.settings.seed = settings.seed &+ gen
        var reshaped = copy.makeCandidate(range: copy.window(forPayoff: candidate.payoffTime), payoff: candidate.payoffTime)
        reshaped.id = candidate.id
        reshaped.isFavorite = candidate.isFavorite
        reshaped.generation = gen
        reshaped.status = candidate.status
        reshaped.timelineID = candidate.timelineID
        return reshaped
    }

    func peakTime(in range: TimeRange) -> Seconds {
        guard signals.count > 0 else { return range.midpoint }
        var best = signals.index(at: range.start)
        for i in signals.indices(in: range) where signals.excitement[i] > signals.excitement[best] { best = i }
        return (Double(best) + 0.5) * signals.step
    }

    // MARK: Boundaries

    /// Chooses natural start/end points around a payoff so the clip reads HOOK → CONTEXT → PAYOFF → END.
    func window(forPayoff payoff: Seconds) -> TimeRange {
        let d = settings.targetDuration
        let setupShare = d <= 20 ? 0.5 : 0.6
        let idealStart = payoff - setupShare * d
        var start = idealStart

        // Prefer starting at a sentence start that follows a pause.
        if !sentences.isEmpty {
            let lo = idealStart - 0.35 * d
            let hi = min(idealStart + 0.25 * d, payoff - min(3, d * 0.2))
            var bestScore = Double.greatestFiniteMagnitude
            for (i, s) in sentences.enumerated() where s.start >= lo && s.start <= hi {
                let pauseBefore = i > 0 ? s.start - sentences[i - 1].end : 1
                var cost = abs(s.start - idealStart)
                if pauseBefore >= 0.35 { cost -= 0.12 * d }
                if s.text.hasSuffix("?") { cost -= 0.05 * d } // questions make good hooks
                if cost < bestScore {
                    bestScore = cost
                    start = s.start
                }
            }
        } else if let audio = input.audio, audio.count > 0 {
            // Audio-only: start just after a quiet moment.
            start = speechOnset(near: idealStart, radius: 0.25 * d, audio: audio)
        }
        start = max(0, start - 0.12)

        // End: after the payoff + reaction, at a sentence end, near start + d.
        let idealEnd = start + d
        let minEnd = max(payoff + min(2.5, d * 0.15), start + 0.7 * d)
        let maxEnd = min(input.duration, start + 1.18 * d)
        var end = min(idealEnd, input.duration)
        if !sentences.isEmpty {
            var bestScore = Double.greatestFiniteMagnitude
            for (i, s) in sentences.enumerated() where s.end >= minEnd && s.end <= maxEnd {
                let pauseAfter = i + 1 < sentences.count ? sentences[i + 1].start - s.end : 1
                var cost = abs(s.end - idealEnd)
                if pauseAfter >= 0.4 { cost -= 0.1 * d }
                if s.text.hasSuffix("!") || s.text.hasSuffix("?") { cost -= 0.03 * d }
                if cost < bestScore {
                    bestScore = cost
                    end = s.end
                }
            }
        }
        end = max(end, min(minEnd, input.duration))
        end = trimTrailingSilence(start: start, end: end, payoff: payoff)
        end = extendThroughReaction(end: end, start: start)
        end = min(end + 0.25, input.duration)
        if end - start < 0.6 * d {
            end = min(input.duration, start + 0.6 * d)
        }
        return TimeRange(start: start, end: end)
    }

    /// Endings land after the reaction, not in the middle of it: if people are still laughing or the
    /// moment is still peaking at the cut, keep going until it settles (up to 4 s / 1.25× the target),
    /// and never stop halfway through a word.
    func extendThroughReaction(end: Seconds, start: Seconds) -> Seconds {
        guard signals.count > 0 else { return end }
        let limit = min(input.duration, end + 4, max(end, start + 1.25 * settings.targetDuration - 0.3))
        let hot = { (t: Seconds) -> Bool in
            let i = self.signals.index(at: t)
            return self.signals.laughter[i] > 0 || self.signals.excitement[i] > self.excitementP95 * 0.8
        }
        var e = end
        if hot(e - 0.25) {
            while e < limit && hot(e) { e += signals.step }
            e = min(e + 0.3, limit)
        }
        if let word = input.transcript?.words.first(where: { $0.start < e - 0.02 && $0.end > e }) {
            e = max(e, min(word.end + 0.12, max(limit, word.end + 0.12)))
        }
        return e
    }

    func speechOnset(near time: Seconds, radius: Seconds, audio: AudioFeatureSeries) -> Seconds {
        let a = audio.index(at: max(0, time - radius))
        let b = audio.index(at: min(input.duration, time + radius))
        guard b > a + 2 else { return time }
        var best = time
        var bestCost = Double.greatestFiniteMagnitude
        for i in (a + 1)...b where audio.rmsDB[i - 1] < silenceThreshold && audio.rmsDB[i] >= silenceThreshold {
            let t = Double(i) * audio.hop
            let cost = abs(t - time)
            if cost < bestCost {
                bestCost = cost
                best = t
            }
        }
        return best
    }

    /// Cuts dead air after the last word/sound so clips don't end on awkward silence.
    func trimTrailingSilence(start: Seconds, end: Seconds, payoff: Seconds) -> Seconds {
        var lastActivity = start
        if let transcript = input.transcript {
            if let last = transcript.words(in: TimeRange(start: start, end: end)).last { lastActivity = max(lastActivity, last.end) }
        }
        if let audio = input.audio, audio.count > 0 {
            var i = audio.index(at: end)
            let floorIndex = audio.index(at: max(start, payoff))
            while i > floorIndex, audio.rmsDB[i] < silenceThreshold { i -= 1 }
            lastActivity = max(lastActivity, Double(i + 1) * audio.hop)
        } else if input.transcript == nil {
            return end
        }
        lastActivity = max(lastActivity, payoff + 1)
        return end - lastActivity > 0.6 ? lastActivity + 0.35 : end
    }

    // MARK: Scoring

    func makeCandidate(range: TimeRange, payoff: Seconds) -> ClipCandidate {
        let scores = score(range: range, payoff: payoff)
        let tags = inferTags(range: range, payoff: payoff, scores: scores)
        let potential = Int((pow(scores.weighted, 0.8) * 100).rounded()).clamped(1, 99)
        let words = input.transcript.map { Array($0.words(in: range)) } ?? []
        let copy = TitleGenerator.generate(words: words, payoff: payoff, tags: tags, seed: settings.seed &+ Int(range.start))
        let snippet = TitleGenerator.snippet(words: words, around: payoff)
        let hook = HookAnalyzer.analyze(range: range, payoff: payoff, signals: signals, transcript: input.transcript, hookScore: scores.hook)
        return ClipCandidate(assetID: input.assetID, range: range, payoffTime: payoff, targetDuration: settings.targetDuration,
                             potential: potential, scores: scores, tags: tags, title: copy.titles.first ?? "Clip at \(Timecode.short(range.start))",
                             copy: copy, transcriptSnippet: snippet, hook: hook)
    }

    func score(range: TimeRange, payoff: Seconds) -> ClipScores {
        let s = signals
        guard s.count > 0 else { return ClipScores() }
        let hookRange = TimeRange(start: range.start, end: min(range.end, range.start + 3))
        let p95 = excitementP95
        let p99 = excitementP99

        var hook = Double(s.mean(s.excitement, in: hookRange) / p95) * 0.7
        if s.mean(s.speech, in: TimeRange(start: range.start, end: range.start + 1.2)) > 0.3 { hook += 0.15 }
        if s.sum(s.keywords, in: hookRange) > 0.8 || s.sum(s.questions, in: hookRange) > 0 { hook += 0.2 }

        let emotion = Double(s.max(s.excitement, in: range) / p99)
        let audio = Double(s.max(s.loudness, in: range).clamped(0, 4) / 4) * 0.7 + Double(min(s.max(s.surprise, in: range) / 12, 1)) * 0.3
        let reactionRange = TimeRange(start: payoff, end: max(payoff + 0.5, range.end))
        let reaction = Double(min((s.sum(s.laughter, in: reactionRange) * 0.6 + s.sum(s.keywords, in: reactionRange) * 0.25) / 2, 1))

        // Story: clean boundaries + enough speech.
        var story = 0.0
        if !sentences.isEmpty {
            let startsClean = sentences.contains { abs($0.start - range.start) < 0.4 }
            let endsClean = sentences.contains { abs($0.end - range.end) < 0.6 }
            story += startsClean ? 0.35 : 0.1
            story += endsClean ? 0.35 : 0.1
            let rate = input.transcript?.speechRate(in: range) ?? 0
            story += min(rate / 2.2, 1) * 0.3
        } else {
            story = 0.35
        }

        let setup = (payoff - range.start) / max(range.duration, 0.1)
        let context: Double
        switch setup {
        case 0.3...0.8: context = 1
        case 0.15..<0.3: context = 0.6
        case 0.8...0.95: context = 0.6
        default: context = 0.25
        }

        let visual = Double(s.mean(s.motion, in: range).clamped(0, 3) / 3) * 0.7 + Double(min(s.sum(s.cuts, in: range) / 4, 1)) * 0.3

        var ending = 0.0
        if sentences.contains(where: { abs($0.end - (range.end - 0.25)) < 0.8 }) || sentences.isEmpty { ending += 0.45 }
        if let a = input.audio, a.count > 0 {
            let tail = TimeRange(start: max(range.start, range.end - 1.5), end: range.end)
            let silentFraction = SilenceDetector.silentFraction(audio: a, in: tail, threshold: silenceThreshold)
            ending += (1 - silentFraction) * 0.3
        } else {
            ending += 0.2
        }
        if range.end - payoff >= 1.5 { ending += 0.25 }

        let entertainment = min(0.45 * emotion + 0.35 * reaction + 0.2 * visual, 1)
        return ClipScores(hook: hook.clamped(0, 1), emotion: emotion.clamped(0, 1), story: story.clamped(0, 1),
                          entertainment: entertainment, audio: audio.clamped(0, 1), visual: visual.clamped(0, 1),
                          reaction: reaction, context: context, ending: ending.clamped(0, 1))
    }

    func inferTags(range: TimeRange, payoff: Seconds, scores: ClipScores) -> [ClipTag] {
        let s = signals
        var tags: [(ClipTag, Double)] = []
        if input.profile == .gameplay || input.profile == .gameplayWithFacecam { tags.append((.gaming, 0.5)) }
        let laughs = Double(s.sum(s.laughter, in: range))
        if laughs >= 1 { tags.append((.funny, 0.6 + laughs * 0.1)) }
        if scores.reaction > 0.35 || s.max(s.surprise, in: range) > 8 { tags.append((.reaction, scores.reaction + 0.3)) }
        if scores.audio > 0.55 { tags.append((.highEnergy, scores.audio)) }
        if Double(s.sum(s.questions, in: range)) >= 2 { tags.append((.question, 0.3)) }
        let profanity = Double(s.sum(s.profanity, in: range))
        if profanity >= 2 && scores.audio > 0.45 { tags.append((.rage, 0.4 + profanity * 0.05)) }
        let words = input.transcript.map { Array($0.words(in: range)).map(\.normalized) } ?? []
        let text = words.joined(separator: " ")
        if EngagementLexicon.storyMarkers.contains(where: { text.contains($0) }) || (scores.story > 0.8 && scores.audio < 0.4 && words.count > Int(range.duration * 2)) {
            tags.append((.story, 0.45))
        }
        if words.filter({ EngagementLexicon.hypeWords.contains($0) }).count >= 2 && scores.audio > 0.4 { tags.append((.hype, 0.5)) }
        if words.filter({ EngagementLexicon.failWords.contains($0) }).count >= 1 && scores.emotion > 0.5 { tags.append((.fail, 0.45)) }
        if input.profile == .podcast || input.profile == .talkingHead { tags.append((.conversation, 0.3)) }
        if tags.isEmpty { tags.append((scores.audio > 0.4 ? .highEnergy : .conversation, 0.2)) }
        var seen = Set<ClipTag>()
        return tags.sorted { $0.1 > $1.1 }.map { $0.0 }.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }
}
