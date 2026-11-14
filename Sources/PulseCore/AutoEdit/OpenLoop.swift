import Foundation

/// A tease planted near the start of a video and the moment it promises (#582). Kept on the timeline so the
/// promise can be checked after every later edit: the tease must still be there, and so must what it points at.
public struct OpenLoop: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// The text clip that carries the tease.
    public var teaseClipID: UUID
    /// The recording and the instant in it the tease promises (the moment's payoff).
    public var assetID: UUID
    public var payoffSource: Seconds
    /// What the moment was called when the tease was planted.
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), teaseClipID: UUID, assetID: UUID, payoffSource: Seconds, title: String, text: String) {
        self.id = id
        self.teaseClipID = teaseClipID
        self.assetID = assetID
        self.payoffSource = payoffSource
        self.title = title
        self.text = text
    }
}

/// Plants and checks open loops. A viewer told early that something specific is coming has a reason to stay
/// for it, and feels cheated if it never arrives: so a tease is only ever written for a moment that is really
/// in the edit, and the coach says so when a later cut removes it.
public enum OpenLoopBuilder {
    /// The name of the text clip a tease becomes.
    public static let clipName = "Tease"

    public struct Plan: Hashable, Sendable {
        public var text: String
        /// When the tease shows, in timeline seconds.
        public var at: Seconds
        /// When the promised moment lands, in timeline seconds.
        public var payoffAt: Seconds
        public var payoffSource: Seconds
        public var title: String
    }

    public struct Unpaid: Hashable, Sendable {
        public var loop: OpenLoop
        /// When the tease shows.
        public var teaseAt: Seconds
        /// Why it isn't paid off.
        public var reason: String
    }

    /// What the tease calls the moment, by the kind of moment it is. Always true of the strongest later
    /// moment of that kind, which is the one it is planted for.
    static func promise(for tags: [ClipTag]) -> String {
        for tag in tags {
            switch tag {
            case .funny: return "THE FUNNIEST MOMENT"
            case .fail: return "THE WORST FAIL"
            case .rage: return "THE RAGE"
            case .hype: return "THE CLUTCH"
            case .emotional: return "THE MOMENT IT GOT REAL"
            case .story: return "HOW IT ENDS"
            case .highEnergy: return "THE CRAZIEST MOMENT"
            case .reaction, .gaming, .question, .conversation: continue
            }
        }
        return "THE BEST MOMENT"
    }

    /// The tease for this edit: the strongest moment that lands in its second half, promised in the first
    /// half minute. Nil when the edit is too short to need one, when nothing strong lands late, or when the
    /// only such moment is the one the cold open already shows.
    public static func plan(timeline: Timeline, moments: [LongFormSegment], assetID: UUID) -> Plan? {
        let duration = timeline.duration
        guard duration >= 180 else { return nil }
        let program = EditCoach.Program(timeline: timeline, assetID: assetID)
        // Where the cold open's own moment is, so the tease promises something else.
        let hookTitle = timeline.markers.first { $0.name == "Hook" && $0.time < 1 }?.note
        var best: (moment: LongFormSegment, at: Seconds)?
        for moment in moments where moment.title != hookTitle || hookTitle == nil || hookTitle?.isEmpty == true {
            guard let landed = timelineTime(ofSource: moment.payoff, in: program, after: 30) else { continue }
            guard landed >= max(duration * 0.5, 60), landed <= duration - 10 else { continue }
            if moment.potential > (best?.moment.potential ?? 44) { best = (moment, landed) }
        }
        guard let best else { return nil }
        // After the hook has played, never later than the first half minute.
        let hookEnd = timeline.tracks.first { $0.kind == .video }?.clips.first { $0.name == "Hook" }?.end ?? 0
        let at = min(max(hookEnd + 1.5, 6), 26)
        return Plan(text: "COMING UP: \(promise(for: best.moment.tags))", at: at, payoffAt: best.at, payoffSource: best.moment.payoff,
                    title: best.moment.title)
    }

    /// The last time `source` plays in the edit after `after` seconds (a cold open shows the best moment
    /// early; the promise is about where it plays in full).
    static func timelineTime(ofSource source: Seconds, in program: EditCoach.Program, after: Seconds) -> Seconds? {
        program.segments.filter { $0.sourceRange.contains(source) }.map { $0.timelineTime(atSource: source) }.filter { $0 >= after }.max()
    }

    /// Puts the tease on screen for three seconds, small and high in the frame, and records what it promises.
    /// One tease per edit: planting again replaces the last one.
    @discardableResult
    public static func plant(_ plan: Plan, in timeline: inout Timeline, assetID: UUID) -> OpenLoop {
        remove(from: &timeline)
        var style = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 56, weight: .bold, textCase: .uppercase, color: .white,
                              strokeColor: .black, strokeWidth: 6, shadowOpacity: 0.45, shadowRadius: 6, shadowOffsetY: 4)
        style.letterSpacing = 0.5
        var clip = TimelineClip(name: clipName, content: .text(TextElement(text: plan.text, style: style, animationIn: .fadeIn, animationOut: .fadeIn,
                                                                           animationDuration: 0.25, maxWidth: 0.7)),
                                start: plan.at, sourceDuration: 3, aiGenerated: true)
        clip.transform.positionY = AnimatedDouble(0.12)
        let trackID = timeline.freeTrack(kind: .text, for: TimeRange(start: plan.at, end: plan.at + 3))
        if let index = timeline.trackIndex(id: trackID) {
            timeline.tracks[index].clips.append(clip)
            timeline.tracks[index].clips.sort { $0.start < $1.start }
        }
        let loop = OpenLoop(teaseClipID: clip.id, assetID: assetID, payoffSource: plan.payoffSource, title: plan.title, text: plan.text)
        timeline.openLoops = [loop]
        timeline.modifiedAt = Date()
        return loop
    }

    /// Takes the tease off and forgets its promise.
    public static func remove(from timeline: inout Timeline) {
        let ids = Set((timeline.openLoops ?? []).map(\.teaseClipID))
        for index in timeline.tracks.indices {
            timeline.tracks[index].clips.removeAll { ids.contains($0.id) || ($0.name == clipName && $0.aiGenerated) }
        }
        timeline.openLoops = nil
    }

    /// The teases whose promise the edit no longer keeps: the moment was cut, or it now plays before the
    /// tease (or so soon after that there was nothing to wait for). A tease deleted by hand is simply gone.
    public static func unpaid(in timeline: Timeline) -> [Unpaid] {
        guard let loops = timeline.openLoops, !loops.isEmpty else { return [] }
        var out: [Unpaid] = []
        for loop in loops {
            guard let tease = timeline.allClips.first(where: { $0.id == loop.teaseClipID && $0.isEnabled }) else { continue }
            let program = EditCoach.Program(timeline: timeline, assetID: loop.assetID)
            let plays = program.segments.filter { $0.isEnabled && $0.sourceRange.contains(loop.payoffSource) }
                .map { $0.timelineTime(atSource: loop.payoffSource) }
            if plays.isEmpty {
                out.append(Unpaid(loop: loop, teaseAt: tease.start, reason: "the moment it promises was cut"))
            } else if !plays.contains(where: { $0 >= tease.end + 20 }) {
                out.append(Unpaid(loop: loop, teaseAt: tease.start, reason: "the moment it promises now plays before or right after the tease"))
            }
        }
        return out
    }

    /// When the tease's moment lands in the edit now, if it does.
    public static func payoffTime(of loop: OpenLoop, in timeline: Timeline) -> Seconds? {
        let program = EditCoach.Program(timeline: timeline, assetID: loop.assetID)
        return program.segments.filter { $0.sourceRange.contains(loop.payoffSource) }.map { $0.timelineTime(atSource: loop.payoffSource) }.max()
    }
}
