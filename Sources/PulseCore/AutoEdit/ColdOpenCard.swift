import Foundation

/// A quick "what happened" line over the cold open (#90), before the story starts.
public enum ColdOpenCard {
    public static let clipName = "Cold Open Card"

    public static func text(tags: [ClipTag], seed: Int = 0) -> String {
        if tags.contains(.fail) || tags.contains(.rage) { return ["OH NO…", "THIS WENT WRONG", "WAIT FOR IT…"][abs(seed) % 3] }
        if tags.contains(.question) { return "GUESS WHAT HAPPENED" }
        if tags.contains(.hype) || tags.contains(.highEnergy) || tags.contains(.gaming) { return ["WATCH THIS", "NO WAY", "WAIT FOR IT"][abs(seed) % 3] }
        if tags.contains(.funny) { return ["WAIT FOR IT", "I CAN’T", "WATCH THIS"][abs(seed) % 3] }
        return "WAIT FOR IT"
    }

    /// Over the "Cold Open" teaser on the first video track; false when there is no teaser or a card already.
    @discardableResult
    public static func add(_ timeline: inout Timeline, text: String) -> Bool {
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }),
              let teaser = timeline.tracks[v].clips.first(where: { $0.name == "Cold Open" }),
              let t1 = timeline.tracks.firstIndex(where: { $0.kind == .text }),
              !timeline.tracks[t1].clips.contains(where: { $0.name == clipName }) else { return false }
        let style = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 56, weight: .black, textCase: .uppercase, color: .white,
                              strokeColor: .black, strokeWidth: 7, shadowOpacity: 0.5, shadowRadius: 8, shadowOffsetY: 4)
        var card = TimelineClip(name: clipName, content: .text(TextElement(text: text, style: style, animationIn: .slideUp, animationOut: .fadeIn,
                                                                          animationDuration: 0.18, maxWidth: 0.8)),
                                start: teaser.start + 0.05, sourceDuration: max(0.4, teaser.duration - 0.15), aiGenerated: true)
        card.transform.positionY = AnimatedDouble(0.3)
        timeline.tracks[t1].clips.append(card)
        timeline.tracks[t1].sortClips()
        return true
    }
}
