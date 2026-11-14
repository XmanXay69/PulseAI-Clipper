import Foundation

/// One recording cut one way, with what the coach and the retention guess make of it (#627).
public struct StyleTrial: Identifiable, Sendable {
    /// The playbook's id, or `AISettings.ownStyle` for PULSE's own way.
    public var id: String
    public var name: String
    /// The options that built it, so the pick can be built for real with the same ones.
    public var options: LongFormOptions
    public var timeline: Timeline
    public var review: EditReview
    public var retention: RetentionPredictor.Curve
    public var facts: Facts

    /// What the edit is made of, counted off the timeline.
    public struct Facts: Hashable, Sendable {
        public var length: Seconds
        public var cuts: Int
        public var zooms: Int
        public var popUps: Int
        public var soundEffects: Int
        public var hasCaptions: Bool
        public var hasMusic: Bool
        /// Longest stretch with no cut, zoom or pop-up.
        public var longestHold: Seconds

        public init(_ timeline: Timeline) {
            length = timeline.duration
            let picture = timeline.tracks.first { $0.kind == .video }?.clips.filter(\.isEnabled) ?? []
            cuts = max(0, picture.count - 1)
            zooms = PlaybookCoach.zoomArrivals(in: timeline).count
            popUps = timeline.allClips.filter { clip in
                guard clip.isEnabled, case .text = clip.content else { return false }
                return true
            }.count
            soundEffects = timeline.allClips.filter { $0.isEnabled && $0.role == .soundEffect }.count
            hasCaptions = timeline.captions.map { $0.isEnabled && !$0.words.isEmpty } ?? false
            hasMusic = timeline.allClips.contains { $0.isEnabled && $0.role == .music }
            longestHold = PlaybookCoach.staticStretches(in: timeline).map(\.duration).max() ?? 0
        }

        /// "12 min · a cut every 9 s · 14 zooms · 6 pop-ups · captions · music"
        public var summary: String {
            var parts = [Timecode.duration(length)]
            if cuts > 0 { parts.append("a cut every \(Int((length / Double(cuts + 1)).rounded())) s") }
            parts.append(zooms == 1 ? "1 zoom" : "\(zooms) zooms")
            if popUps > 0 { parts.append(popUps == 1 ? "1 pop-up" : "\(popUps) pop-ups") }
            if soundEffects > 0 { parts.append(soundEffects == 1 ? "1 sound effect" : "\(soundEffects) sound effects") }
            parts.append(hasCaptions ? "captions" : "no captions")
            parts.append(hasMusic ? "music" : "no music")
            return parts.joined(separator: " · ")
        }
    }

    public var score: Int { review.prediction.score }
}

/// Builds the same recording in two (or more) styles so they can be weighed against each other before one
/// is built for real. The trials are drafts: the picture, zooms, captions, pop-ups and markers the long-form
/// editor decides on its own, without the music search, B-roll or audio levelling the full edit adds.
public enum StyleComparison {
    /// How the pair compares, in words.
    public struct Verdict: Hashable, Sendable {
        /// The id of the trial that comes out ahead; nil when they are too close to call.
        public var winner: String?
        public var headline: String
        public var reasons: [String]
    }

    /// `playbook` nil builds PULSE's own way from `base`. A playbook keeps `base`'s length, extras and wording
    /// and takes everything else from the style.
    public static func trial(_ playbook: EditorPlaybook?, asset: MediaAsset, analysis: MediaAnalysis, base: LongFormOptions = LongFormOptions(),
                             sounds: LongFormSounds = LongFormSounds(), taste: TasteProfile = TasteProfile(),
                             signals precomputed: EngagementSignals? = nil, calibration: CoachCalibration? = nil) -> StyleTrial {
        var options = playbook?.styled(base) ?? base
        if playbook == nil { options.style = nil }
        let timeline = LongFormEditor.build(asset: asset, analysis: analysis, options: options, sounds: sounds, taste: taste).timeline
        let signals = precomputed ?? EngagementModel.compute(analysis: analysis)
        let rules = playbook?.rules ?? PacingRules.standard(for: EditFormat.of(timeline))
        let review = EditCoach.review(timeline, analysis: analysis, signals: signals, calibration: calibration, rules: rules)
        let retention = RetentionPredictor.predict(edit: timeline, signals: signals, assetID: asset.id)
        return StyleTrial(id: playbook?.id ?? AISettings.ownStyle, name: playbook?.name ?? "PULSE's own", options: options, timeline: timeline,
                          review: review, retention: retention, facts: StyleTrial.Facts(timeline))
    }

    /// Which of two trials comes out ahead and why. The coach's score decides; within three points the
    /// retention guess does; within a point of that too, it's a draw and the reasons say how they differ.
    public static func verdict(_ a: StyleTrial, _ b: StyleTrial) -> Verdict {
        let scoreGap = a.score - b.score
        let keptA = Double(a.retention.average), keptB = Double(b.retention.average)
        let keptGap = (keptA - keptB) * 100
        var winner: StyleTrial?
        let headline: String
        if abs(scoreGap) >= 3 {
            let (ahead, behind) = scoreGap > 0 ? (a, b) : (b, a)
            winner = ahead
            headline = "\(ahead.name) scores \(ahead.score) against \(behind.score) for \(behind.name)"
        } else if abs(keptGap) >= 1 {
            let (ahead, behind) = keptGap > 0 ? (a, b) : (b, a)
            winner = ahead
            headline = "Close on score (\(a.score) and \(b.score)); \(ahead.name) is predicted to hold viewers longer than \(behind.name)"
        } else {
            headline = "Too close to call: \(a.score) and \(b.score), and the same share predicted to keep watching"
        }
        var reasons: [String] = []
        // The coach factors that differ most, in the winner's favour first.
        let factorsB = Dictionary(b.review.prediction.factors.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        let gaps = a.review.prediction.factors.compactMap { factor -> (name: String, a: Double, b: Double)? in
            guard let other = factorsB[factor.name] else { return nil }
            return (factor.name, factor.value, other)
        }.filter { abs($0.a - $0.b) >= 0.08 }.sorted { abs($0.a - $0.b) > abs($1.a - $1.b) }
        for item in gaps.prefix(3) {
            let ahead = item.a > item.b ? a : b
            reasons.append("\(item.name): \(ahead.name) is stronger (\(percent(max(item.a, item.b))) against \(percent(min(item.a, item.b))))")
        }
        reasons.append("Predicted average watched: \(percent(keptA)) for \(a.name), \(percent(keptB)) for \(b.name)")
        if abs(a.facts.length - b.facts.length) >= 30 {
            let longer = a.facts.length > b.facts.length ? a : b
            let shorter = a.facts.length > b.facts.length ? b : a
            reasons.append("\(longer.name) runs \(Timecode.duration(longer.facts.length)); \(shorter.name) \(Timecode.duration(shorter.facts.length))")
        }
        if abs(a.facts.longestHold - b.facts.longestHold) >= 5 {
            let calmer = a.facts.longestHold > b.facts.longestHold ? a : b
            reasons.append("\(calmer.name) holds a shot for up to \(Int(calmer.facts.longestHold.rounded())) s; the other changes the picture more often")
        }
        return Verdict(winner: winner?.id, headline: headline, reasons: reasons)
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}
