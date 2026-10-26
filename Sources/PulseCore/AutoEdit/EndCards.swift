import Foundation

/// What the last seconds of a short ask for (#71, #76).
public enum EndCTA: String, Codable, CaseIterable, Sendable {
    case none, comment, follow

    public var displayName: String {
        switch self {
        case .none: return "Nothing"
        case .comment: return "Ask for comments"
        case .follow: return "Follow for more"
        }
    }

    public var detail: String {
        switch self {
        case .none: return "The short ends on the payoff."
        case .comment: return "“Tell me in the comments 👇” over the last two seconds."
        case .follow: return "“Follow for part 2” over the last two seconds, with your handle from the Brand Kit."
        }
    }
}

/// Comment-bait endings and follow cards as text clips (#71, #76).
public enum EndCards {
    static let commentLines = ["TELL ME IN THE COMMENTS 👇", "RATE THIS 1–10 👇", "WHAT WOULD YOU DO? 👇", "AGREE OR DISAGREE? 👇", "THOUGHTS? 👇"]
    static let followLines = ["FOLLOW FOR PART 2", "FOLLOW FOR MORE", "MORE ON MY PAGE"]

    /// The line for a short with these tags, or nil for `.none`.
    public static func text(for cta: EndCTA, tags: [ClipTag], handle: String? = nil, seed: Int = 0) -> String? {
        switch cta {
        case .none:
            return nil
        case .comment:
            if tags.contains(.question) { return "WHAT'S YOUR ANSWER? 👇" }
            if tags.contains(.fail) || tags.contains(.rage) { return "WOULD YOU HAVE DONE THE SAME? 👇" }
            return commentLines[abs(seed) % commentLines.count]
        case .follow:
            let h = handle?.trimmingCharacters(in: .whitespaces) ?? ""
            if !h.isEmpty { return "FOLLOW \(h.hasPrefix("@") ? h : "@" + h) FOR MORE" }
            return followLines[abs(seed) % followLines.count]
        }
    }

    /// Puts the line over the last `duration` seconds on the text track, in the upper third so it never sits
    /// on the captions. False when the short is too short (< 6 s) or already has text there.
    @discardableResult
    public static func add(_ timeline: inout Timeline, text: String, duration: Seconds = 2.4) -> Bool {
        guard timeline.duration >= 6, let t1 = timeline.tracks.firstIndex(where: { $0.kind == .text }) else { return false }
        let start = max(0, timeline.duration - duration)
        let window = TimeRange(start: start, end: timeline.duration)
        guard !timeline.tracks[t1].clips.contains(where: { $0.timelineRange.overlaps(window) }) else { return false }
        let style = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 48, weight: .black, textCase: .uppercase, color: .white,
                              strokeColor: .black, strokeWidth: 7, shadowOpacity: 0.5, shadowRadius: 8, shadowOffsetY: 4)
        var card = TimelineClip(name: "End Card", content: .text(TextElement(text: text, style: style, animationIn: .slideUp, animationOut: .fadeIn,
                                                                             animationDuration: 0.25, maxWidth: 0.8)),
                                start: start, sourceDuration: timeline.duration - start, aiGenerated: true)
        card.transform.positionY = AnimatedDouble(0.22)
        timeline.tracks[t1].clips.append(card)
        timeline.tracks[t1].sortClips()
        return true
    }
}
