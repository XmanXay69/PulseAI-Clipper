import Foundation

/// Lexicon of spoken cues that correlate with entertaining moments.
public enum EngagementLexicon {
    /// Multi-word phrases (normalized, space separated) → weight.
    public static let phrases: [String: Float] = [
        "no way": 1.6, "oh my god": 1.6, "oh my gosh": 1.2, "what the": 1.5, "let's go": 1.5, "lets go": 1.5,
        "oh no": 1.3, "are you kidding": 1.4, "you're kidding": 1.2, "i can't believe": 1.5, "i cant believe": 1.5,
        "what just happened": 1.8, "did you see": 1.2, "holy crap": 1.5, "holy shit": 1.6, "shut up": 1.0,
        "no no no": 1.4, "yes yes yes": 1.4, "i'm dead": 1.4, "im dead": 1.4, "i'm crying": 1.3, "for real": 0.8,
        "look at this": 1.0, "watch this": 1.1, "you know what": 0.6, "guess what": 1.0, "the worst": 0.9, "the best": 0.8,
    ]

    /// Single words → weight.
    public static let words: [String: Float] = [
        "bro": 0.7, "bruh": 0.8, "dude": 0.6, "yo": 0.5, "wait": 0.7, "what": 0.5, "nah": 0.7, "insane": 1.2, "crazy": 1.0,
        "unbelievable": 1.2, "clutch": 1.4, "omg": 1.4, "wtf": 1.6, "holy": 1.0, "yes": 0.5, "noo": 1.1, "nooo": 1.3,
        "wow": 0.9, "whoa": 1.0, "dead": 0.8, "died": 0.9, "run": 0.6, "help": 0.7, "hilarious": 1.1, "screaming": 1.1,
        "literally": 0.3, "actually": 0.2, "never": 0.4, "worst": 0.8, "best": 0.5, "why": 0.5, "how": 0.3,
        "fuck": 0.9, "fucking": 0.9, "shit": 0.8, "damn": 0.6, "hell": 0.4, "goated": 1.0, "cracked": 1.0, "sheesh": 1.2,
        "gg": 0.8, "ez": 0.8, "rip": 0.8, "yikes": 0.8, "oof": 0.8, "sus": 0.6, "hype": 0.8, "win": 0.6, "won": 0.8, "lost": 0.6,
    ]

    public static let laughter: Set<String> = ["haha", "hahaha", "hahahaha", "ha", "lol", "lmao", "lmfao", "hehe", "laughs", "laughing", "laughter", "rofl", "(laughs)", "[laughter]", "[laughs]"]
    public static let profanity: Set<String> = ["fuck", "fucking", "fucked", "shit", "shitty", "damn", "bitch", "ass", "asshole", "crap", "hell", "wtf"]
    public static let storyMarkers: [String] = ["one time", "so basically", "remember when", "story", "true story", "back when", "this one time", "long story short", "so i was"]
    public static let hypeWords: Set<String> = ["clutch", "lets", "let's", "go", "yes", "won", "win", "insane", "goated", "cracked", "sheesh", "gg"]
    public static let failWords: Set<String> = ["died", "dead", "noo", "nooo", "lost", "rip", "oof", "worst", "fail", "failed"]

    public static func isLaughter(_ normalized: String) -> Bool {
        if laughter.contains(normalized) { return true }
        // "hahahah", "ahahaha"
        let letters = normalized.filter { $0 == "h" || $0 == "a" || $0 == "e" }
        return normalized.count >= 4 && letters.count == normalized.count && normalized.contains("ha")
    }
}

/// Per-step engagement signals derived from audio, transcript and video features.
public struct EngagementSignals: Sendable {
    public var step: Seconds
    public var count: Int
    /// Loudness relative to the local (±30 s) baseline, in robust σ units.
    public var loudness: [Float]
    /// Sudden jump above the previous few seconds (dB, ≥ 0).
    public var surprise: [Float]
    /// Speech rate relative to the recording's typical rate (σ units).
    public var speechRate: [Float]
    /// Keyword / exclamation / question cues.
    public var keywords: [Float]
    public var laughter: [Float]
    public var questions: [Float]
    public var profanity: [Float]
    public var motion: [Float]
    public var cuts: [Float]
    /// Fraction of the step that has speech (0…1), from word timings.
    public var speech: [Float]
    /// Combined excitement curve (smoothed), 0…~1.
    public var excitement: [Float]
    /// Chat bursts (0…1), when a chat replay was imported; empty otherwise.
    public var chat: [Float] = []

    public func index(at time: Seconds) -> Int {
        Int((time / step).rounded(.down)).clamped(0, Swift.max(count - 1, 0))
    }

    public func indices(in range: TimeRange) -> ClosedRange<Int> {
        let a = index(at: range.start)
        let b = Swift.max(a, index(at: range.end - step / 2))
        return a...b
    }

    public func mean(_ series: [Float], in range: TimeRange) -> Float {
        guard count > 0 else { return 0 }
        let r = indices(in: range)
        var s: Float = 0
        for i in r { s += series[i] }
        return s / Float(r.count)
    }

    public func max(_ series: [Float], in range: TimeRange) -> Float {
        guard count > 0 else { return 0 }
        var m: Float = -.greatestFiniteMagnitude
        for i in indices(in: range) { m = Swift.max(m, series[i]) }
        return m
    }

    public func sum(_ series: [Float], in range: TimeRange) -> Float {
        guard count > 0 else { return 0 }
        var s: Float = 0
        for i in indices(in: range) { s += series[i] }
        return s
    }
}

public enum EngagementModel {
    /// All the signals of an analysis (including an imported chat replay).
    public static func compute(analysis: MediaAnalysis, step: Seconds = 0.5) -> EngagementSignals {
        compute(duration: analysis.duration, audio: analysis.audio, transcript: analysis.transcript, visual: analysis.visual, chat: analysis.chat, step: step)
    }

    public static func compute(duration: Seconds, audio: AudioFeatureSeries?, transcript: Transcript?, visual: VisualFeatureSeries?,
                               chat: ChatLog? = nil, step: Seconds = 0.5) -> EngagementSignals {
        let n = max(1, Int((duration / step).rounded(.up)))
        var loudnessDB = [Float](repeating: -60, count: n)
        var flux = [Float](repeating: 0, count: n)
        if let audio, audio.count > 0 {
            loudnessDB = AudioFeatureSeries.resample(audio.rmsDB.values, hop: audio.hop, to: step, count: n, mode: .mean)
            flux = AudioFeatureSeries.resample(audio.spectralFlux.values, hop: audio.hop, to: step, count: n, mode: .max)
        }
        // Loudness relative to a rolling ±30 s median, scaled by a global robust spread.
        let baseline = SeriesMath.rollingMedian(loudnessDB, radius: Int(30 / step))
        let spread = Swift.max(SeriesMath.mad(loudnessDB), 3)
        var loudness = [Float](repeating: 0, count: n)
        var surprise = [Float](repeating: 0, count: n)
        for i in 0..<n {
            loudness[i] = (loudnessDB[i] - baseline[i]) / spread
            let lookback = Swift.max(0, i - Int(3 / step))
            if i > lookback {
                var prev: Float = 0
                for j in lookback..<i { prev += loudnessDB[j] }
                prev /= Float(i - lookback)
                surprise[i] = Swift.max(0, loudnessDB[i] - prev)
            }
        }
        let fluxZ = SeriesMath.zScores(flux).map { Swift.max(0, $0) }

        var speechRate = [Float](repeating: 0, count: n)
        var keywords = [Float](repeating: 0, count: n)
        var laughter = [Float](repeating: 0, count: n)
        var questions = [Float](repeating: 0, count: n)
        var profanity = [Float](repeating: 0, count: n)
        var speech = [Float](repeating: 0, count: n)
        if let transcript, !transcript.isEmpty {
            let words = transcript.words
            let norm = words.map(\.normalized)
            var wordCounts = [Float](repeating: 0, count: n)
            for (wi, w) in words.enumerated() {
                let i = Int((w.start / step).rounded(.down)).clamped(0, n - 1)
                wordCounts[i] += 1
                // Speech coverage.
                var t = w.start
                while t < w.end {
                    let k = Int((t / step).rounded(.down)).clamped(0, n - 1)
                    speech[k] = Swift.min(1, speech[k] + Float(Swift.min(step, w.end - t) / step))
                    t += step
                }
                let word = norm[wi]
                if let weight = EngagementLexicon.words[word] { keywords[i] += weight }
                if EngagementLexicon.isLaughter(word) || w.text.lowercased().contains("laugh") { laughter[i] += 1 }
                if EngagementLexicon.profanity.contains(word) { profanity[i] += 1 }
                if w.isQuestion { questions[i] += 1 }
                if w.isExclamation { keywords[i] += 0.6 }
                if w.text.count > 2, w.text == w.text.uppercased(), w.text.rangeOfCharacter(from: .letters) != nil { keywords[i] += 0.4 }
                // Phrase matching (up to 4 words).
                for len in 2...4 where wi + len <= norm.count {
                    let phrase = norm[wi..<(wi + len)].joined(separator: " ")
                    if let weight = EngagementLexicon.phrases[phrase] { keywords[i] += weight }
                }
            }
            // Words per second over ±2 s, relative to the recording's median rate while speaking.
            let radius = Swift.max(1, Int(2 / step))
            var prefix = [Float](repeating: 0, count: n + 1)
            for i in 0..<n { prefix[i + 1] = prefix[i] + wordCounts[i] }
            var rates = [Float](repeating: 0, count: n)
            for i in 0..<n {
                let a = Swift.max(0, i - radius)
                let b = Swift.min(n, i + radius + 1)
                rates[i] = (prefix[b] - prefix[a]) / Float(Double(b - a) * step)
            }
            let speaking = rates.filter { $0 > 0.5 }
            let medianRate = SeriesMath.median(speaking.isEmpty ? rates : speaking)
            let rateSpread = Swift.max(SeriesMath.mad(speaking.isEmpty ? rates : speaking), 0.5)
            speechRate = rates.map { ($0 - medianRate) / rateSpread }
        }

        var motion = [Float](repeating: 0, count: n)
        var cuts = [Float](repeating: 0, count: n)
        if let visual, visual.count > 0 {
            let raw = AudioFeatureSeries.resample(visual.motion.values, hop: visual.hop, to: step, count: n, mode: .max)
            motion = SeriesMath.zScores(raw)
            for cut in visual.sceneCuts {
                let i = Int((cut / step).rounded(.down))
                if i >= 0 && i < n { cuts[i] = 1 }
            }
        }

        // Chat: a burst of messages (especially laugh/hype emotes) is one of the clearest signs a moment landed.
        var chatActivity: [Float] = []
        if let chat, !chat.isEmpty {
            let c = ChatSignals.compute(chat, duration: duration, step: step)
            chatActivity = c.activity
            for i in 0..<n where i < c.laughter.count { laughter[i] += c.laughter[i] }
        }

        var excitement = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let l = loudness[i].clamped(0, 4) / 4
            let s = Swift.min(surprise[i] / 12, 1)
            let f = Swift.min(fluxZ[i] / 4, 1)
            let r = speechRate[i].clamped(0, 3) / 3
            let k = Swift.min(keywords[i] / 2.5, 1)
            let la = Swift.min(laughter[i], 1)
            let m = motion[i].clamped(0, 3) / 3
            excitement[i] = 0.26 * l + 0.16 * s + 0.08 * f + 0.12 * r + 0.2 * k + 0.14 * la + 0.08 * m + 0.04 * cuts[i]
            if i < chatActivity.count { excitement[i] = excitement[i] * 0.75 + chatActivity[i] * 0.45 }
        }
        excitement = SeriesMath.smooth(excitement, sigma: 1.5 / step)

        return EngagementSignals(step: step, count: n, loudness: loudness, surprise: surprise, speechRate: speechRate,
                                 keywords: keywords, laughter: laughter, questions: questions, profanity: profanity,
                                 motion: motion, cuts: cuts, speech: speech, excitement: excitement, chat: chatActivity)
    }
}
