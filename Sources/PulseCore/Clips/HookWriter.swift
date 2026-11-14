import Foundation

/// Five on-screen opening lines for the first two seconds of a short (#542): a question, a claim, the
/// stakes, a tease and the clip's own best words. The first two seconds decide whether a viewer stays, and a
/// line of text is read before a sentence is heard.
///
/// Written here, on the Mac, from the clip's own words, tags and timing. Every line is true to the clip:
/// a tease only counts down to a payoff that is really there, a quote is something that was really said.
public enum HookWriter {
    public enum Kind: String, CaseIterable, Sendable {
        case question, claim, stakes, tease, quote

        public var displayName: String {
            switch self {
            case .question: return "A question"
            case .claim: return "A claim"
            case .stakes: return "The stakes"
            case .tease: return "A tease"
            case .quote: return "Their own words"
            }
        }

        public var symbolName: String {
            switch self {
            case .question: return "questionmark.bubble"
            case .claim: return "exclamationmark.bubble"
            case .stakes: return "flame"
            case .tease: return "hourglass"
            case .quote: return "quote.bubble"
            }
        }
    }

    public struct Line: Hashable, Identifiable, Sendable {
        public var kind: Kind
        public var text: String
        public var id: String { kind.rawValue }
    }

    /// The longest line that still reads in a glance on a phone.
    public static let maximumLength = 34
    /// The name of the text clip a chosen line becomes, so a second choice replaces the first.
    public static let clipName = "Hook Line"

    static let questions: [ClipTag: [String]] = [
        .funny: ["WHY IS THIS SO FUNNY?", "HOW DID IT GO THIS WRONG?"],
        .reaction: ["WHAT JUST HAPPENED?", "DID YOU SEE THAT?"],
        .highEnergy: ["HOW DID HE PULL THAT OFF?", "CAN HE ACTUALLY DO IT?"],
        .hype: ["CAN HE CLUTCH THIS?", "IS THIS THE PLAY OF THE YEAR?"],
        .fail: ["WHAT WAS HE THINKING?", "HOW DO YOU MISS THAT?"],
        .story: ["YOU KNOW HOW THIS ENDS?", "WANT TO HEAR THE WORST PART?"],
        .rage: ["HOW IS THAT FAIR?", "WHO DESIGNED THIS?"],
        .question: ["DOES ANYONE KNOW THE ANSWER?"],
        .gaming: ["HOW DID THAT WORK?", "IS THAT EVEN ALLOWED?"],
        .conversation: ["DID HE REALLY SAY THAT?", "IS HE RIGHT?"],
        .emotional: ["WERE YOU READY FOR THIS?"],
    ]

    static let claims: [ClipTag: [String]] = [
        .funny: ["THE FUNNIEST MOMENT OF THE STREAM", "I HAVE NEVER LAUGHED THIS HARD"],
        .reaction: ["NOBODY SAW THIS COMING", "THE REACTION SAYS IT ALL"],
        .highEnergy: ["THIS IS AS GOOD AS IT GETS", "THE WHOLE LOBBY LOST IT"],
        .hype: ["THE BEST PLAY I HAVE EVER MADE", "THIS ONE GOES IN THE MONTAGE"],
        .fail: ["THE WORST DECISION OF THE NIGHT", "THIS COULD NOT HAVE GONE WORSE"],
        .story: ["THIS STORY ONLY GETS WORSE", "THE STRANGEST THING THAT HAPPENED"],
        .rage: ["THIS GAME OWES ME AN APOLOGY", "I HAVE NEVER BEEN THIS MAD"],
        .question: ["NOBODY HAS A GOOD ANSWER"],
        .gaming: ["THIS SHOULD NOT HAVE WORKED", "A PLAY YOU ONLY SEE ONCE"],
        .conversation: ["THE WILDEST TAKE OF THE NIGHT", "HE WAS NOT WRONG"],
        .emotional: ["THIS ONE HIT DIFFERENT"],
    ]

    static let stakes: [ClipTag: [String]] = [
        .funny: ["ONE JOKE FROM LOSING IT", "TRY NOT TO LAUGH"],
        .reaction: ["ONE SECOND CHANGES EVERYTHING", "HE HAD ONE JOB"],
        .highEnergy: ["EVERYTHING RIDES ON THIS", "NO SECOND CHANCES"],
        .hype: ["ONE SHOT TO WIN IT", "LOSE THIS AND IT'S OVER"],
        .fail: ["ONE MISTAKE AND IT'S OVER", "ALL HE HAD TO DO WAS NOT MISS"],
        .story: ["IT STARTED AS A NORMAL DAY", "ONE CHOICE STARTED ALL OF THIS"],
        .rage: ["ONE MORE DEATH AND HE QUITS", "HIS LAST NERVE IS ON THE LINE"],
        .question: ["GET THIS WRONG AND IT'S OVER"],
        .gaming: ["LAST LIFE. NO BACKUP.", "ONE ROUND DECIDES IT"],
        .conversation: ["HE BET EVERYTHING ON THIS TAKE"],
        .emotional: ["HE DID NOT EXPECT TO CARE"],
    ]

    /// Five lines, one of each kind, in the order they are usually worth trying. `words` are the clip's words
    /// in source time, `range` the clip in source time, `payoff` its biggest moment. `banner` is what the game
    /// put on screen at the payoff, when it was read.
    public static func lines(words: [TranscriptWord], range: TimeRange, payoff: Seconds, tags: [ClipTag], banner: String? = nil,
                             seed: Int = 0) -> [Line] {
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 542))
        let inside = words.filter { $0.start >= range.start - 0.05 && $0.end <= range.end + 0.05 }
        let ordered = tags.isEmpty ? [ClipTag.reaction] : tags
        func pick(_ table: [ClipTag: [String]], fallback: String) -> String {
            for tag in ordered {
                guard var pool = table[tag], !pool.isEmpty else { continue }
                pool.shuffle(using: &rng)
                return pool[0]
            }
            return fallback
        }

        // The question: one that was really asked in the clip, when it is short enough to read.
        var question = pick(questions, fallback: "WHAT JUST HAPPENED?")
        if let asked = spokenQuestion(inside) { question = asked }

        // The stakes: the game's own banner when there is one ("ONE KILL FROM THE WIN" beats a template).
        var stake = pick(stakes, fallback: "ONE SECOND CHANGES EVERYTHING")
        if let banner = banner?.trimmingCharacters(in: .whitespaces), !banner.isEmpty {
            let line = fit("WATCH FOR THE \(banner.uppercased())")
            if line.count <= maximumLength { stake = line }
        }

        // The tease counts down to the payoff that is really there.
        let wait = Int((payoff - range.start).rounded())
        let tease: String
        switch wait {
        case ..<3: tease = "DON'T BLINK"
        case 3..<60: tease = "WAIT \(wait) SECONDS"
        default: tease = "WAIT FOR THE END"
        }

        // Their own words: the most quotable sentence near the payoff.
        var quote = TitleGenerator.bestQuote(words: inside, payoff: payoff).map { fit($0) } ?? ""
        if quote.isEmpty || quote.count > maximumLength { quote = fit(lastWords(inside, before: payoff)) }
        if quote.isEmpty { quote = "YOU NEED TO SEE THIS" }

        var lines = [Line(kind: .question, text: question), Line(kind: .claim, text: pick(claims, fallback: "NOBODY SAW THIS COMING")),
                     Line(kind: .stakes, text: stake), Line(kind: .tease, text: tease), Line(kind: .quote, text: quote)]
        // No two alike: a quote that repeats the question gives way to the words just before the payoff.
        var seen = Set<String>()
        for i in lines.indices where !seen.insert(lines[i].text).inserted {
            lines[i].text = lines[i].kind == .quote ? "YOU NEED TO SEE THIS" : lines[i].text + "!"
            seen.insert(lines[i].text)
        }
        return lines
    }

    /// A question someone asks in the clip, short enough to put on screen, nearest the start.
    static func spokenQuestion(_ words: [TranscriptWord]) -> String? {
        var sentence: [TranscriptWord] = []
        for word in words {
            sentence.append(word)
            guard word.endsSentence else { continue }
            defer { sentence = [] }
            guard word.text.hasSuffix("?"), sentence.count >= 2, sentence.count <= 7 else { continue }
            let line = fit(sentence.map(\.text).joined(separator: " "))
            if line.count <= maximumLength { return line }
        }
        return nil
    }

    /// The last few words said before `time`, for a clip with no quotable sentence.
    static func lastWords(_ words: [TranscriptWord], before time: Seconds) -> String {
        let spoken = words.filter { $0.end <= time + 0.3 }.suffix(5)
        var out: [String] = []
        for word in spoken.reversed() {
            let candidate = ([word.text] + out).joined(separator: " ")
            if candidate.count > maximumLength { break }
            out.insert(word.text, at: 0)
        }
        return out.joined(separator: " ")
    }

    /// Upper case, no trailing full stop or comma, single spaces.
    static func fit(_ text: String) -> String {
        var line = text.uppercased().split(separator: " ").joined(separator: " ")
        while let last = line.last, last == "." || last == "," || last == ";" || last == ":" { line.removeLast() }
        return line
    }

    /// Puts `line` on screen over the opening of a short, replacing a line chosen earlier. Big, outlined and
    /// high in the frame, clear of the captions, popping in at once and gone after `duration`.
    public static func apply(_ line: Line, to timeline: inout Timeline, duration: Seconds = 2) {
        remove(from: &timeline)
        let length = min(duration, max(0.5, timeline.duration - 0.1))
        guard timeline.duration > 0.6 else { return }
        var style = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 84, weight: .black, textCase: .uppercase, color: .white,
                              strokeColor: .black, strokeWidth: 10, shadowOpacity: 0.5, shadowRadius: 8, shadowOffsetY: 6)
        style.letterSpacing = 0.5
        var clip = TimelineClip(name: clipName, content: .text(TextElement(text: line.text, style: style, animationIn: .pop, animationOut: .fadeIn,
                                                                           animationDuration: 0.18, maxWidth: 0.86)),
                                start: 0.05, sourceDuration: length, aiGenerated: true)
        clip.transform.positionY = AnimatedDouble(0.22)
        let trackID = timeline.freeTrack(kind: .text, for: TimeRange(start: 0.05, end: 0.05 + length))
        if let index = timeline.trackIndex(id: trackID) {
            timeline.tracks[index].clips.append(clip)
            timeline.tracks[index].clips.sort { $0.start < $1.start }
        }
        timeline.modifiedAt = Date()
    }

    /// Takes the chosen hook line off again.
    public static func remove(from timeline: inout Timeline) {
        for index in timeline.tracks.indices {
            timeline.tracks[index].clips.removeAll { $0.name == clipName && $0.aiGenerated }
        }
    }

    /// The line on the short now, if one was chosen.
    public static func current(in timeline: Timeline) -> String? {
        for clip in timeline.allClips where clip.name == clipName && clip.aiGenerated {
            if case .text(let element) = clip.content { return element.text }
        }
        return nil
    }
}
