import Foundation

/// A recording as a language model reads it (#1281): its words as numbered lines with timecodes and an
/// energy mark, the moments the signal-based picker scored highest, and the length that was asked for.
public struct EditBrief: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        /// 1, 2, 3… The model answers in these numbers, not in times: a line number can't be half right.
        public var number: Int
        public var range: TimeRange
        public var text: String
        /// 0 (quiet) to 9 (the loudest, busiest stretch of this recording).
        public var energy: Int
        /// Seconds of talk left out of the brief before this line, to fit the model's reading room.
        public var skippedBefore: Seconds = 0
    }

    public struct Pick: Hashable, Sendable {
        public var range: TimeRange
        public var score: Int
        public var tags: [ClipTag]
        public var payoff: Seconds
    }

    public var lines: [Line]
    public var picks: [Pick]
    public var duration: Seconds
    public var profile: ContentProfile
    public var minimumLength: Seconds
    public var maximumLength: Seconds
    public var targetLength: Seconds
    /// Talk left out because the whole transcript would not fit, in seconds. Never left out silently: the
    /// brief says where, and the app says so before anything is sent.
    public var leftOut: Seconds
    /// The part of that which falls after the last line sent.
    public var leftOutAtEnd: Seconds = 0

    /// How many words the brief sends.
    public var wordCount: Int { lines.reduce(0) { $0 + $1.text.split(separator: " ").count } }

    /// The first and last line that fall in `range`, when any do.
    public func lineNumbers(in range: TimeRange) -> ClosedRange<Int>? {
        let inside = lines.filter { $0.range.end > range.start + 0.05 && $0.range.start < range.end - 0.05 }
        guard let first = inside.first, let last = inside.last else { return nil }
        return first.number...last.number
    }

    /// What the model is sent.
    public var text: String {
        func minutes(_ seconds: Seconds) -> String {
            let whole = Int((seconds / 60).rounded())
            return whole >= 120 ? "\(whole / 60) h \(whole % 60) min" : "\(max(1, whole)) min"
        }
        var out: [String] = []
        out.append("Recording: \(minutes(duration)) long. Kind: \(profile.displayName).")
        out.append("Wanted: a video of \(minutes(minimumLength)) to \(minutes(maximumLength)); aim for about \(minutes(targetLength)).")
        out.append("Energy marks (e0 to e9) come from the recording's sound and picture: e0 is quiet, e9 is the loudest, busiest stretch of this recording.")
        if leftOut > 1 {
            out.append("The whole transcript did not fit, so \(minutes(leftOut)) of the quietest talk is left out. Each gap is marked where it falls. You cannot keep what you were not shown.")
        }
        if !picks.isEmpty {
            out.append("")
            out.append("Moments a signal-based picker scored highest. It hears loudness and laughter, not meaning: use it as a hint, not as the plan.")
            for pick in picks {
                guard let span = lineNumbers(in: pick.range) else { continue }
                let tags = pick.tags.prefix(3).map(\.rawValue).joined(separator: ", ")
                out.append("- lines \(span.lowerBound)-\(span.upperBound) (\(Timecode.short(pick.range.start))-\(Timecode.short(pick.range.end))) score \(pick.score)\(tags.isEmpty ? "" : ": \(tags)")")
            }
        }
        out.append("")
        out.append("Transcript:")
        for line in lines {
            if line.skippedBefore > 1 { out.append("[… \(minutes(line.skippedBefore)) of quiet talk left out …]") }
            out.append("[\(line.number)] \(Timecode.short(line.range.start))-\(Timecode.short(line.range.end)) e\(line.energy)  \(line.text)")
        }
        if leftOutAtEnd > 1 { out.append("[… \(minutes(leftOutAtEnd)) of quiet talk left out …]") }
        return out.joined(separator: "\n")
    }
}

/// What the model answered, before it is checked: line numbers and words, exactly as it gave them.
public struct EditPlanDraft: Hashable, Sendable {
    public struct Cut: Hashable, Sendable {
        public var fromLine: Int
        public var toLine: Int
        public var why: String

        public init(fromLine: Int, toLine: Int, why: String = "") {
            self.fromLine = fromLine
            self.toLine = toLine
            self.why = why
        }
    }

    public struct Section: Hashable, Sendable {
        public var title: String
        public var role: String
        public var fromLine: Int
        public var toLine: Int
        public var payoffLine: Int
        public var why: String
        public var cuts: [Cut]

        public init(title: String, role: String = "build", fromLine: Int, toLine: Int, payoffLine: Int, why: String = "", cuts: [Cut] = []) {
            self.title = title
            self.role = role
            self.fromLine = fromLine
            self.toLine = toLine
            self.payoffLine = payoffLine
            self.why = why
            self.cuts = cuts
        }
    }

    public var summary: String
    public var hookLine: Int
    public var hookWhy: String
    public var sections: [Section]
    /// Which model wrote it, as the provider reported.
    public var writtenBy: String

    public init(summary: String, hookLine: Int, hookWhy: String = "", sections: [Section], writtenBy: String = "") {
        self.summary = summary
        self.hookLine = hookLine
        self.hookWhy = hookWhy
        self.sections = sections
        self.writtenBy = writtenBy
    }
}

/// The model's plan after checking, in the recording's own times: what the existing editor builds from.
public struct EditPlan: Hashable, Sendable {
    public struct Section: Hashable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var role: String
        public var why: String
        /// The stretches of the recording this section keeps, in order: one, or several when the model cut
        /// something out of its middle.
        public var ranges: [TimeRange]
        public var payoff: Seconds
        /// What was dropped from inside it, in the model's words.
        public var cutNotes: [String]
    }

    public var summary: String
    public var sections: [Section]
    /// The instant the video opens on, when the model named one that is in the plan.
    public var hookPayoff: Seconds?
    public var hookWhy: String
    /// What PULSE changed in the model's answer, or wants you to know about it, in words.
    public var notes: [String]
    public var writtenBy: String

    /// How much of the recording the plan keeps.
    public var keptLength: Seconds { sections.flatMap(\.ranges).merged().reduce(0) { $0 + $1.duration } }

    /// True when the sections don't run in the order they were recorded: the model rearranged the story.
    public var isReordered: Bool {
        let starts = sections.compactMap { $0.ranges.first?.start }
        return zip(starts, starts.dropFirst()).contains { $0 > $1 }
    }

    /// The plan as storyboard moments, in the model's order: each kept stretch one moment, named by its
    /// section, scored and tagged from what the picker knew about that stretch.
    public func segments(picks: [EditBrief.Pick] = []) -> [LongFormSegment] {
        var out: [LongFormSegment] = []
        for section in sections {
            for (index, range) in section.ranges.enumerated() {
                let near = picks.filter { $0.range.overlaps(range) }
                let score = near.map(\.score).max() ?? 60
                var tags: [ClipTag] = []
                for tag in near.sorted(by: { $0.score > $1.score }).flatMap(\.tags) where !tags.contains(tag) && tags.count < 3 { tags.append(tag) }
                let holdsPayoff = range.contains(section.payoff)
                out.append(LongFormSegment(range: range, payoff: holdsPayoff ? section.payoff : range.start + range.duration * 0.7,
                                           potential: score, title: section.ranges.count > 1 ? "\(section.title) (\(index + 1))" : section.title, tags: tags))
            }
        }
        return out
    }
}

/// A language model plans the edit (#1281): it reads the whole transcript and the signals and writes the
/// structure (where the video opens, which stretches it keeps and in what order, what is dropped inside
/// them), and the existing editor carries that out.
///
/// The signal-based picker hears loudness, laughter and pace. It cannot know that a quiet sentence at minute
/// four is what makes minute forty funny. A model that reads the words can. What it cannot do is cut video,
/// so its plan is only line numbers and reasons; everything it says is checked here before a frame is
/// touched, and what was changed in its answer is said in words.
public enum EditPlanner {
    /// Roles a section may have. Anything else the model writes is read as "build".
    public static let roles = ["setup", "build", "payoff", "aside"]
    /// The shortest stretch worth keeping, and the shortest worth cutting out of one.
    static let shortestSection: Seconds = 4, shortestCut: Seconds = 2

    // MARK: The brief

    /// Builds what the model reads. `excitement` is the recording's energy curve with its step; `budget` is
    /// roughly how many characters of transcript may be sent. When the transcript is longer than that, the
    /// quietest stretches away from every picked moment are left out, and the brief says where.
    public static func brief(analysis: MediaAnalysis, options: LongFormOptions, picks moments: [LongFormSegment] = [],
                             excitement: [Float] = [], step: Seconds = 1, budget: Int = 600_000) -> EditBrief? {
        guard let transcript = analysis.transcript, !transcript.words.isEmpty else { return nil }
        // Lines: whole sentences, joined until they are worth a line, split when one runs on.
        var lines: [EditBrief.Line] = []
        var current: [TranscriptWord] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            lines.append(EditBrief.Line(number: lines.count + 1, range: TimeRange(start: first.start, end: max(last.end, first.start + 0.1)),
                                        text: current.map(\.text).joined(separator: " "), energy: 0))
            current = []
        }
        for word in transcript.words {
            if let first = current.first, let last = current.last {
                // A long silence always starts a new line; so does a line that has run on.
                if word.start - last.end > 2.5 || word.end - first.start > 14 { flush() }
            }
            current.append(word)
            if let first = current.first, word.endsSentence, word.end - first.start >= 5 { flush() }
        }
        flush()

        // Energy per line, on this recording's own scale.
        let ceiling = max(excitement.sorted().dropLast(max(0, excitement.count / 100)).last ?? 0, 0.0001)
        func level(_ range: TimeRange) -> Double {
            guard !excitement.isEmpty, step > 0 else { return 0 }
            let from = min(excitement.count - 1, max(0, Int(range.start / step)))
            let to = min(excitement.count - 1, max(from, Int(range.end / step)))
            let slice = excitement[from...to]
            return Double(slice.reduce(0, +)) / Double(slice.count)
        }
        for index in lines.indices {
            lines[index].energy = Int((level(lines[index].range) / Double(ceiling) * 9).rounded()).clamped(0, 9)
        }

        let picks = moments.sorted { $0.potential > $1.potential }.prefix(24).sorted { $0.range.start < $1.range.start }
            .map { EditBrief.Pick(range: $0.range, score: $0.potential, tags: $0.tags, payoff: $0.payoff) }

        // Too long to send whole: keep every line near a picked moment, then the liveliest of the rest, and
        // mark each gap. Lines keep their place; only whole lines are left out.
        var leftOut = 0.0, leftOutAtEnd = 0.0
        let size = lines.reduce(0) { $0 + $1.text.count + 28 }
        if size > budget {
            var keep = Set<Int>()
            var used = 0
            func take(_ index: Int) {
                guard !keep.contains(index) else { return }
                keep.insert(index)
                used += lines[index].text.count + 28
            }
            let near = picks.map { $0.range.expanded(by: 45) }
            for index in lines.indices where near.contains(where: { $0.overlaps(lines[index].range) }) && used < budget { take(index) }
            for index in lines.indices.sorted(by: { lines[$0].energy != lines[$1].energy ? lines[$0].energy > lines[$1].energy : $0 < $1 }) {
                if used >= budget { break }
                take(index)
            }
            var kept: [EditBrief.Line] = []
            var gap = 0.0
            for index in lines.indices {
                if keep.contains(index) {
                    var line = lines[index]
                    line.number = kept.count + 1
                    line.skippedBefore = gap
                    kept.append(line)
                    gap = 0
                } else {
                    gap += lines[index].range.duration
                    leftOut += lines[index].range.duration
                }
            }
            lines = kept
            leftOutAtEnd = gap
        }
        guard !lines.isEmpty else { return nil }
        return EditBrief(lines: lines, picks: picks, duration: analysis.duration, profile: analysis.profile,
                         minimumLength: options.minimumLength, maximumLength: options.maximumLength,
                         targetLength: options.targetLength(forSource: analysis.duration), leftOut: leftOut, leftOutAtEnd: leftOutAtEnd)
    }

    // MARK: What the model is asked

    public static let system = """
    You are the story editor for a video cut from a long recording: a live stream, a play session, a long take. \
    You read the recording's transcript and decide what the finished video is: where it opens, which stretches it \
    keeps and in what order, and what is dropped from inside the stretches it keeps.

    An editing program carries out your plan exactly. It cuts the recording to the lines you name, takes out \
    dead air inside them, and adds captions, zooms and sound. It cannot judge content, so that judgement is \
    yours. You answer in line numbers, never in times.

    What makes a plan good:
    - Someone who never saw the recording can follow the video. Keep the line that sets something up when you \
    keep the line that pays it off, even when the set-up is quiet and far away.
    - Each section is a whole thought: it starts where the thought starts and ends after it lands, not on the \
    loudest second.
    - Fewer complete sections beat many fragments.
    - The kept length is inside the range that was asked for.
    - Sections run in recording order unless another order tells the story better, such as stating the goal \
    before the attempts. Rearrange only when you can say why.
    - Inside a section, cut what a viewer would skip: tangents, repeats, waiting, reading out messages that go \
    nowhere. Do not cut pauses or filler words; the program does that.
    - The hook is the single line the video opens on before anything else: the most arresting moment that still \
    makes sense with no context. It must be a line inside one of your sections.

    The energy marks and the picker's moments come from sound and picture only. They are hints. A quiet line \
    can matter more than a loud one, and you are here because you can tell.

    Use only line numbers that appear in the transcript. Write titles of at most 40 characters, plain, no \
    emoji. Write each reason in one short sentence that the person editing can agree or disagree with.
    """

    /// The answer's shape, for providers that take a JSON schema.
    public static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string", "description": "One or two sentences: what this video is."],
            "hook_line": ["type": "integer", "description": "The line the video opens on."],
            "hook_why": ["type": "string"],
            "sections": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "role": ["type": "string", "enum": roles] as [String: Any],
                        "from_line": ["type": "integer"],
                        "to_line": ["type": "integer"],
                        "payoff_line": ["type": "integer", "description": "The line where this section lands."],
                        "why": ["type": "string"],
                        "cuts": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": ["from_line": ["type": "integer"], "to_line": ["type": "integer"], "why": ["type": "string"]],
                                "required": ["from_line", "to_line", "why"],
                                "additionalProperties": false,
                            ] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": ["title", "role", "from_line", "to_line", "payoff_line", "why", "cuts"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
        ] as [String: Any],
        "required": ["summary", "hook_line", "hook_why", "sections"],
        "additionalProperties": false,
    ]

    /// The same shape in words, for providers that only promise "a JSON object".
    public static let shapeInWords = """
    Reply with one JSON object and nothing else: {"summary": string, "hook_line": integer, "hook_why": string, \
    "sections": [{"title": string, "role": "setup" | "build" | "payoff" | "aside", "from_line": integer, \
    "to_line": integer, "payoff_line": integer, "why": string, "cuts": [{"from_line": integer, "to_line": integer, \
    "why": string}]}]}. "cuts" may be an empty list.
    """

    /// Reads the model's JSON. Numbers that arrive as strings or decimals are taken; a section with no usable
    /// line numbers is skipped; an answer with no sections at all is refused.
    public static func parse(_ json: [String: Any], writtenBy: String) throws -> EditPlanDraft {
        func int(_ value: Any?) -> Int? {
            if let number = value as? Int { return number }
            if let number = value as? Double, number.isFinite { return Int(number.rounded()) }
            if let number = value as? NSNumber { return number.intValue }
            if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        guard let list = json["sections"] as? [[String: Any]] else { throw AIProviderError.badResponse("no sections") }
        var sections: [EditPlanDraft.Section] = []
        for item in list {
            guard let from = int(item["from_line"]), let to = int(item["to_line"]) else { continue }
            let cuts = (item["cuts"] as? [[String: Any]] ?? []).compactMap { cut -> EditPlanDraft.Cut? in
                guard let a = int(cut["from_line"]), let b = int(cut["to_line"]) else { return nil }
                return EditPlanDraft.Cut(fromLine: a, toLine: b, why: cut["why"] as? String ?? "")
            }
            sections.append(EditPlanDraft.Section(title: item["title"] as? String ?? "", role: item["role"] as? String ?? "build",
                                                  fromLine: from, toLine: to, payoffLine: int(item["payoff_line"]) ?? to,
                                                  why: item["why"] as? String ?? "", cuts: cuts))
        }
        guard !sections.isEmpty else { throw AIProviderError.badResponse("a plan with no sections") }
        return EditPlanDraft(summary: json["summary"] as? String ?? "", hookLine: int(json["hook_line"]) ?? sections[0].fromLine,
                             hookWhy: json["hook_why"] as? String ?? "", sections: sections, writtenBy: writtenBy)
    }

    // MARK: Checking the answer

    /// Turns the model's line numbers into stretches of the recording and makes the plan safe to build from.
    /// Nothing the model wrote is trusted as it stands: numbers outside the transcript are pulled in, stretches
    /// too short to be anything are dropped, a stretch kept twice is kept once, a plan far over the length
    /// asked for loses its asides, and a hook outside the plan is replaced. Each change is a note.
    public static func resolve(_ draft: EditPlanDraft, brief: EditBrief) -> EditPlan {
        var notes: [String] = []
        let count = brief.lines.count
        func line(_ number: Int) -> EditBrief.Line { brief.lines[number.clamped(1, count) - 1] }
        func energy(at time: Seconds) -> Int { brief.lines.first { $0.range.end >= time }?.energy ?? 0 }
        func name(_ title: String, _ index: Int) -> String {
            let clean = title.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if clean.isEmpty { return "Section \(index + 1)" }
            return clean.count > 60 ? String(clean.prefix(59)).trimmingCharacters(in: .whitespaces) + "…" : clean
        }

        var sections: [EditPlan.Section] = []
        var taken: [TimeRange] = []
        var outside = 0
        for (index, wanted) in draft.sections.enumerated() {
            let title = name(wanted.title, index)
            if !(1...count).contains(wanted.fromLine) || !(1...count).contains(wanted.toLine) { outside += 1 }
            let a = min(wanted.fromLine, wanted.toLine).clamped(1, count), b = max(wanted.fromLine, wanted.toLine).clamped(1, count)
            // A little air either side, so a first word and a last laugh aren't clipped.
            let whole = TimeRange(start: max(0, line(a).range.start - 0.3), end: min(brief.duration, line(b).range.end + 0.4))
            // Lines left out of the brief sit between kept ones: a section never reaches across a gap it was not shown.
            var ranges: [TimeRange] = []
            var start = whole.start
            for number in a...b where number > a && line(number).skippedBefore > 1 {
                ranges.append(TimeRange(start: start, end: line(number - 1).range.end + 0.4))
                start = max(0, line(number).range.start - 0.3)
            }
            ranges.append(TimeRange(start: start, end: whole.end))

            // What the model cut from inside it.
            var cutNotes: [String] = []
            for cut in wanted.cuts {
                let ca = min(cut.fromLine, cut.toLine).clamped(a, b), cb = max(cut.fromLine, cut.toLine).clamped(a, b)
                let gone = TimeRange(start: line(ca).range.start - 0.1, end: line(cb).range.end + 0.1)
                guard gone.duration >= shortestCut else { continue }
                var next: [TimeRange] = []
                var applied = false
                for range in ranges {
                    guard let hit = range.intersection(gone), hit.duration >= shortestCut else { next.append(range); continue }
                    applied = true
                    if hit.start - range.start >= 3 { next.append(TimeRange(start: range.start, end: hit.start)) }
                    if range.end - hit.end >= 3 { next.append(TimeRange(start: hit.end, end: range.end)) }
                }
                ranges = next
                if applied {
                    let reason = cut.why.trimmingCharacters(in: .whitespacesAndNewlines)
                    cutNotes.append("\(Timecode.short(gone.start))–\(Timecode.short(gone.end))" + (reason.isEmpty ? "" : ": \(reason)"))
                }
            }

            // Not twice: what an earlier section already keeps is taken out of this one.
            var fresh: [TimeRange] = []
            var repeated = false
            for range in ranges {
                var pieces = [range]
                for earlier in taken {
                    pieces = pieces.flatMap { piece -> [TimeRange] in
                        guard let hit = piece.intersection(earlier), hit.duration > 0.2 else { return [piece] }
                        repeated = true
                        var left: [TimeRange] = []
                        if hit.start - piece.start >= shortestSection { left.append(TimeRange(start: piece.start, end: hit.start)) }
                        if piece.end - hit.end >= shortestSection { left.append(TimeRange(start: hit.end, end: piece.end)) }
                        return left
                    }
                }
                fresh += pieces
            }
            ranges = fresh.filter { $0.duration >= shortestSection }
            if repeated { notes.append(ranges.isEmpty ? "Left out “\(title)”: an earlier section already keeps those lines." : "Trimmed “\(title)”: part of it was already kept by an earlier section.") }
            guard !ranges.isEmpty else {
                if !repeated { notes.append("Left out “\(title)”: under \(Int(shortestSection)) seconds once cut.") }
                continue
            }
            taken += ranges
            let lands = line(wanted.payoffLine.clamped(a, b)).range.end - 0.2
            let payoff = ranges.contains { $0.contains(lands) } ? lands : (ranges.last.map { $0.start + $0.duration * 0.7 } ?? lands)
            sections.append(EditPlan.Section(id: UUID(), title: title, role: roles.contains(wanted.role) ? wanted.role : "build",
                                             why: wanted.why.trimmingCharacters(in: .whitespacesAndNewlines), ranges: ranges, payoff: payoff,
                                             cutNotes: cutNotes))
        }
        if outside > 0 {
            notes.append("\(outside) section\(outside == 1 ? "" : "s") named lines that aren't in the transcript; \(outside == 1 ? "it was" : "they were") pulled back to the nearest real line.")
        }

        // Far over the length asked for: asides go first, last one first. Nothing else is dropped for length;
        // the storyboard shows the total and you decide.
        func length(_ list: [EditPlan.Section]) -> Seconds { list.flatMap(\.ranges).merged().reduce(0) { $0 + $1.duration } }
        while length(sections) > brief.maximumLength * 1.15, let index = sections.lastIndex(where: { $0.role == "aside" }), sections.count > 1 {
            notes.append("Left out the aside “\(sections[index].title)”: the plan ran past the \(Int(brief.maximumLength / 60)) minutes asked for.")
            sections.remove(at: index)
        }
        let kept = length(sections)
        if kept > brief.maximumLength * 1.15 {
            notes.append("The plan keeps \(Timecode.short(kept)), more than the \(Int(brief.maximumLength / 60)) minutes asked for. Untick what matters least.")
        } else if kept < min(brief.minimumLength, brief.targetLength) * 0.7, kept > 0 {
            notes.append("The plan keeps \(Timecode.short(kept)), less than the \(Int(brief.minimumLength / 60)) minutes asked for. Tick more moments below if you want it longer.")
        }

        // The opening: the model's line, when the plan really keeps it.
        var hook: Seconds?
        var hookWhy = draft.hookWhy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sections.isEmpty {
            let wanted = line(draft.hookLine).range
            let at = wanted.end - 0.2
            if (1...count).contains(draft.hookLine), sections.contains(where: { $0.ranges.contains { $0.contains(at) } }) {
                hook = at
            } else if let strongest = sections.first(where: { $0.role == "payoff" })
                        ?? sections.max(by: { energy(at: $0.payoff) < energy(at: $1.payoff) }) {
                hook = strongest.payoff
                hookWhy = ""
                notes.append("The opening line the model chose isn't in its own plan, so the video opens on “\(strongest.title)” instead.")
            }
        }
        // The section that holds the opening lands on it.
        if let hook, let index = sections.firstIndex(where: { $0.ranges.contains { $0.contains(hook) } }) { sections[index].payoff = hook }
        if brief.leftOut > 1 {
            notes.append("\(Timecode.short(brief.leftOut)) of the quietest talk was not sent, so the model could not consider it.")
        }
        return EditPlan(summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines), sections: sections, hookPayoff: hook,
                        hookWhy: hookWhy, notes: notes, writtenBy: draft.writtenBy)
    }
}
