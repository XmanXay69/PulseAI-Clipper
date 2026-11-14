import Foundation

/// A video's real audience retention, as YouTube Studio exports it (#936): the share of viewers still
/// watching at each point of the video. Kept on the edit it belongs to, drawn over its timeline, and read
/// for what the audience left during (#937).
public struct RetentionGraph: Codable, Hashable, Sendable {
    public struct Point: Codable, Hashable, Sendable {
        /// Where in the video, 0…1.
        public var position: Double
        /// Share of viewers watching, 1 = everyone who started. Can pass 1 where people rewatch.
        public var watching: Double

        public init(position: Double, watching: Double) {
            self.position = position
            self.watching = watching
        }
    }

    public var points: [Point]
    public var importedAt: Date
    /// The file it came from.
    public var source: String
    /// How long the edit was when the graph was imported: the graph describes that cut of it.
    public var videoDuration: Seconds

    public init(points: [Point], importedAt: Date = Date(), source: String = "", videoDuration: Seconds = 0) {
        self.points = points.sorted { $0.position < $1.position }
        self.importedAt = importedAt
        self.source = source
        self.videoDuration = videoDuration
    }

    /// Share watching at a position 0…1, between the nearest two points.
    public func watching(atPosition position: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if position <= first.position { return first.watching }
        if position >= last.position { return last.watching }
        var lo = 0, hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if points[mid].position <= position { lo = mid } else { hi = mid }
        }
        let a = points[lo], b = points[hi]
        let span = b.position - a.position
        return span <= 0 ? a.watching : a.watching + (b.watching - a.watching) * (position - a.position) / span
    }

    /// Share watching at `time` of a video `duration` long.
    public func watching(at time: Seconds, duration: Seconds) -> Double {
        watching(atPosition: duration > 0 ? (time / duration).clamped(0, 1) : 0)
    }

    /// Average share watching across the video: what YouTube calls average percentage viewed.
    public var averageViewed: Double {
        guard points.count > 1 else { return points.first?.watching ?? 1 }
        var area = 0.0
        for (a, b) in zip(points, points.dropFirst()) { area += (a.watching + b.watching) / 2 * (b.position - a.position) }
        let span = points[points.count - 1].position - points[0].position
        return span > 0 ? area / span : points[0].watching
    }

    /// The edit has changed length since the graph was imported, so the two no longer line up.
    public func isStale(for duration: Seconds) -> Bool {
        videoDuration > 0 && abs(duration - videoDuration) > max(2, videoDuration * 0.02)
    }
}

/// Reads YouTube Studio's audience-retention export.
///
/// In YouTube Studio: Analytics → a video → Engagement → Audience retention → See more → the download arrow →
/// CSV. The file has a position column and a retention column, a hundred or so rows. Any CSV shaped like
/// that reads: the position may be a percentage, a fraction or a timecode, and the retention a percentage or
/// a fraction.
public enum RetentionImporter {
    /// Nil when the text has no position and retention columns, or fewer than three usable rows. `duration`
    /// is needed only when the position column is a timecode.
    public static func parse(_ text: String, duration: Seconds? = nil, source: String = "") -> RetentionGraph? {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 4 else { return nil }
        let header = ChatReplayParser.splitCSV(lines.removeFirst().replacingOccurrences(of: "\u{FEFF}", with: "")).map { $0.lowercased() }
        guard let positionColumn = header.firstIndex(where: { $0.contains("position") || $0.contains("elapsed") || $0 == "time" || $0.contains("timestamp") }),
              let retentionColumn = header.firstIndex(where: { $0.contains("absolute") })
                ?? header.firstIndex(where: { ($0.contains("retention") || $0.contains("watching") || $0.contains("audience")) && !$0.contains("relative") }),
              positionColumn != retentionColumn else { return nil }
        var raw: [(position: Double, isTime: Bool, watching: Double)] = []
        for line in lines {
            let columns = ChatReplayParser.splitCSV(line)
            guard columns.count > max(positionColumn, retentionColumn) else { continue }
            guard let watching = number(columns[retentionColumn]) else { continue }
            let cell = columns[positionColumn].trimmingCharacters(in: .whitespaces)
            if cell.contains(":") {
                guard let seconds = timecode(cell) else { continue }
                raw.append((seconds, true, watching))
            } else if let value = number(cell) {
                raw.append((value, false, watching))
            }
        }
        guard raw.count >= 3 else { return nil }
        // Positions: timecodes need the video's length; otherwise percent when any value passes 1, else a fraction.
        let timed = raw.contains { $0.isTime }
        let positionScale: Double
        if timed {
            guard let length = duration ?? raw.map(\.position).max(), length > 0 else { return nil }
            positionScale = length
        } else {
            positionScale = (raw.map(\.position).max() ?? 0) > 1.0001 ? 100 : 1
        }
        // Retention: percent when any value passes 3 (300 % is far beyond any rewatch spike), else a fraction.
        let watchingScale: Double = (raw.map(\.watching).max() ?? 0) > 3 ? 100 : 1
        let points = raw.map { RetentionGraph.Point(position: ($0.position / positionScale).clamped(0, 1), watching: max(0, $0.watching / watchingScale)) }
        return RetentionGraph(points: points, source: source, videoDuration: duration ?? 0)
    }

    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// "1:05" or "1:02:03" in seconds.
    static func timecode(_ text: String) -> Seconds? {
        let parts = text.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}

/// What was on screen while viewers left (#937).
public enum RetentionFeature: String, Codable, CaseIterable, Sendable {
    /// The picture has been held for twelve seconds or more: no cut, zoom or pop-up.
    case heldShot
    /// Nobody talking and nothing loud.
    case deadAir
    /// The recording itself was flat here.
    case lowEnergy
    /// Within three seconds after a cut, a zoom landing or a pop-up.
    case freshPicture

    public var displayName: String {
        switch self {
        case .heldShot: return "a held shot"
        case .deadAir: return "dead air"
        case .lowEnergy: return "a flat stretch"
        case .freshPicture: return "a change of picture"
        }
    }

    public var plural: String {
        switch self {
        case .heldShot: return "held shots"
        case .deadAir: return "dead air"
        case .lowEnergy: return "flat stretches"
        case .freshPicture: return "the seconds after a change of picture"
        }
    }
}

/// How fast this channel's viewers leave during each kind of second, added up over every video whose real
/// retention was imported. A lift of 2 means they left twice as fast as their own average.
public struct RetentionProfile: Codable, Hashable, Sendable {
    public struct Tally: Codable, Hashable, Sendable {
        public var seconds: Double = 0
        public var loss: Double = 0

        public init() {}
    }

    public var videos: Int = 0
    public var overall = Tally()
    public var features: [String: Tally] = [:]
    /// The edits already counted, so importing a video's graph a second time doesn't count it twice.
    public var counted: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videos = c.decode(Int.self, forKey: .videos, default: 0)
        overall = c.decode(Tally.self, forKey: .overall, default: Tally())
        features = c.decode([String: Tally].self, forKey: .features, default: [:])
        counted = c.decode([String].self, forKey: .counted, default: [])
    }

    /// At least this many videos and this many seconds of a feature before anything is concluded from it.
    public static let minimumVideos = 2
    public static let minimumSeconds: Double = 45

    /// How much faster (or slower) viewers left during `feature` than on average; nil without enough to go on.
    public func lift(_ feature: RetentionFeature) -> Double? {
        guard videos >= RetentionProfile.minimumVideos, let tally = features[feature.rawValue], tally.seconds >= RetentionProfile.minimumSeconds,
              overall.seconds > 0, overall.loss > 0 else { return nil }
        return (tally.loss / tally.seconds) / (overall.loss / overall.seconds)
    }

    /// What the numbers say, in sentences, strongest first.
    public var insights: [String] {
        var found: [(lift: Double, text: String)] = []
        for feature in RetentionFeature.allCases {
            guard let lift = lift(feature) else { continue }
            if lift >= 1.25 {
                found.append((lift, String(format: "Your viewers leave %.1f× faster during %@", lift, feature.plural)))
            } else if lift <= 0.8 {
                found.append((1 / lift, String(format: "Your viewers leave %.1f× slower during %@", 1 / lift, feature.plural)))
            }
        }
        return found.sorted { $0.lift > $1.lift }.map { $0.text + " (from \(videos) videos)." }
    }

    /// The pacing rules as this audience would have them: held shots are given less room where viewers leave
    /// during them, and more where they demonstrably don't mind. Never more than a third either way.
    public func adjusted(_ rules: PacingRules) -> PacingRules {
        guard let lift = lift(.heldShot) else { return rules }
        var out = rules
        let scale = (1 / lift).clamped(0.67, 1.33)
        out.maxStaticStretch = (rules.maxStaticStretch * scale).rounded()
        out.openingStaticStretch = (rules.openingStaticStretch * scale).rounded()
        return out
    }

    /// The profile with one more video's seconds added. A video named by `video` is only ever counted once.
    public func adding(_ observation: RetentionLearning.Observation, video: String? = nil) -> RetentionProfile {
        if let video, counted.contains(video) { return self }
        var out = self
        if let video { out.counted.append(video) }
        out.videos += 1
        out.overall.seconds += observation.overall.seconds
        out.overall.loss += observation.overall.loss
        for (key, tally) in observation.features {
            var total = out.features[key] ?? Tally()
            total.seconds += tally.seconds
            total.loss += tally.loss
            out.features[key] = total
        }
        return out
    }
}

/// Reads a real retention graph against the edit it belongs to (#937): which seconds the audience left
/// during, and what was on screen then.
public enum RetentionLearning {
    public struct Observation: Hashable, Sendable {
        public var overall = RetentionProfile.Tally()
        public var features: [String: RetentionProfile.Tally] = [:]
    }

    /// A stretch where viewers left much faster than through the rest of the video.
    public struct Leak: Hashable, Sendable {
        public var time: Seconds
        /// Share of the audience lost over the ten seconds from `time` (0.08 = eight in a hundred of everyone who started).
        public var lost: Double
        public var cause: RetentionFeature?
    }

    /// What is true of each second of the edit. The first thirty seconds are left out: every video loses
    /// viewers fastest there, whatever is on screen.
    static func features(timeline: Timeline, signals: EngagementSignals?, assetID: UUID?) -> [[RetentionFeature]] {
        let seconds = max(0, Int(timeline.duration.rounded(.down)))
        guard seconds > 0 else { return [] }
        var out = [[RetentionFeature]](repeating: [], count: seconds)
        for stretch in PlaybookCoach.staticStretches(in: timeline) {
            // Held: from twelve seconds into a stretch with no change.
            let from = Int((stretch.start + 12).rounded(.up)), to = Int(stretch.end.rounded(.down))
            if from < to { for t in from..<min(to, seconds) { out[t].append(.heldShot) } }
            // Fresh: the three seconds after the change that ended the stretch before this one.
            if stretch.start > 0.05 {
                let start = Int(stretch.start.rounded(.down))
                for t in start..<min(start + 3, seconds) where !out[t].contains(.freshPicture) { out[t].append(.freshPicture) }
            }
        }
        if let signals, signals.step > 0, signals.count > 0 {
            let program = EditCoach.Program(timeline: timeline, assetID: assetID ?? timeline.origin?.assetID)
            for t in 0..<seconds {
                guard let source = program.sourceTime(at: Double(t) + 0.5) else { continue }
                let index = signals.index(at: source)
                if signals.speech[index] <= 0.05, signals.loudness[index] < 0.3 { out[t].append(.deadAir) }
                if signals.excitement[index] < 0.2 { out[t].append(.lowEnergy) }
            }
        }
        return out
    }

    /// Share of the audience lost during each second after the first thirty, relative to who was still there.
    static func losses(graph: RetentionGraph, duration: Seconds) -> [Double] {
        let seconds = max(0, Int(duration.rounded(.down)))
        return (0..<seconds).map { t in
            guard t >= 30 else { return 0 }
            let before = graph.watching(at: Double(t), duration: duration), after = graph.watching(at: Double(t + 1), duration: duration)
            return max(0, before - after) / max(before, 0.02)
        }
    }

    /// One video's tally for the channel profile. Nil when the graph no longer lines up with the edit, or the
    /// video is too short to say anything past its opening.
    public static func observe(timeline: Timeline, graph: RetentionGraph, signals: EngagementSignals?, assetID: UUID? = nil) -> Observation? {
        let duration = timeline.duration
        guard duration >= 60, !graph.isStale(for: duration), graph.points.count >= 3 else { return nil }
        let what = features(timeline: timeline, signals: signals, assetID: assetID)
        let lost = losses(graph: graph, duration: duration)
        var out = Observation()
        for t in 30..<min(what.count, lost.count) {
            out.overall.seconds += 1
            out.overall.loss += lost[t]
            for feature in what[t] {
                var tally = out.features[feature.rawValue] ?? RetentionProfile.Tally()
                tally.seconds += 1
                tally.loss += lost[t]
                out.features[feature.rawValue] = tally
            }
        }
        return out.overall.seconds >= 20 ? out : nil
    }

    /// The stretches of this video where the audience left fastest, worst first, with what was on screen.
    /// Only stretches that lost at least twice the video's typical ten seconds, and at least two in a hundred.
    public static func leaks(timeline: Timeline, graph: RetentionGraph, signals: EngagementSignals?, assetID: UUID? = nil, count: Int = 3) -> [Leak] {
        let duration = timeline.duration
        guard duration >= 60, !graph.isStale(for: duration), graph.points.count >= 3 else { return [] }
        let what = features(timeline: timeline, signals: signals, assetID: assetID)
        var windows: [(time: Seconds, lost: Double)] = []
        var t: Seconds = 30
        while t + 10 <= duration {
            windows.append((t, max(0, graph.watching(at: t, duration: duration) - graph.watching(at: t + 10, duration: duration))))
            t += 5
        }
        guard windows.count >= 3 else { return [] }
        let typical = windows.map(\.lost).sorted()[windows.count / 2]
        var out: [Leak] = []
        for window in windows.sorted(by: { $0.lost > $1.lost }) where out.count < count {
            guard window.lost >= max(typical * 2, 0.02) else { break }
            if out.contains(where: { abs($0.time - window.time) < 20 }) { continue }
            // What most of those ten seconds had in common, a held shot or dead air before a merely flat stretch.
            var tally: [RetentionFeature: Int] = [:]
            for second in Int(window.time)..<min(Int(window.time) + 10, what.count) {
                for feature in what[second] where feature != .freshPicture { tally[feature, default: 0] += 1 }
            }
            let order: [RetentionFeature] = [.heldShot, .deadAir, .lowEnergy]
            let cause = order.first { (tally[$0] ?? 0) >= 5 }
            out.append(Leak(time: window.time, lost: window.lost, cause: cause))
        }
        return out
    }
}
