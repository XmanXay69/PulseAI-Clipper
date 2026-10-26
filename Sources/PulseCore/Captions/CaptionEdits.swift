import Foundation

/// Whole-track caption edits: timing, text and style helpers behind the captions workspace buttons.
extension CaptionTrack {
    /// Moves every word by `delta` seconds (±200 ms fixes a transcript that runs early or late) (#240).
    /// Words never start before zero.
    @discardableResult
    public mutating func shiftTiming(by delta: Seconds) -> Int {
        guard delta != 0 else { return 0 }
        for i in words.indices {
            let d = max(delta, -words[i].start)
            words[i].start += d
            words[i].end += d
        }
        return words.count
    }

    /// Replaces text in every word (case-insensitive unless asked), keeping timing (#250). Returns the count.
    @discardableResult
    public mutating func replaceAll(_ find: String, with replacement: String, caseSensitive: Bool = false) -> Int {
        let needle = find.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return 0 }
        var count = 0
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        for i in words.indices where words[i].text.range(of: needle, options: options) != nil {
            words[i].text = words[i].text.replacingOccurrences(of: needle, with: replacement, options: options)
            count += 1
        }
        return count
    }

    static let laughWords: Set<String> = ["haha", "hahaha", "hahahaha", "lol", "lmao", "lmfao", "rofl", "hehe", "hehehe", "ahaha", "bahaha"]

    /// Appends an emoji to laughter words that don't have one yet (#237). Returns how many got one.
    @discardableResult
    public mutating func addLaughEmoji(_ emoji: String = "😂") -> Int {
        var count = 0
        for i in words.indices {
            let n = TranscriptWord.normalize(words[i].text)
            let isLaugh = CaptionTrack.laughWords.contains(n) || (n.count >= 4 && n.allSatisfy { $0 == "h" || $0 == "a" } && n.contains("ha"))
            guard isLaugh, !words[i].text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) else { continue }
            words[i].text += " " + emoji
            count += 1
        }
        return count
    }
}

extension CaptionStyle {
    /// Text-shadow presets that read well on any background (#254).
    public enum ShadowPreset: String, CaseIterable, Sendable {
        case none, soft, hard

        public var displayName: String { rawValue.capitalized }

        public func apply(to style: inout CaptionStyle) {
            switch self {
            case .none:
                style.text.shadowOpacity = 0
                style.text.shadowRadius = 0
            case .soft:
                style.text.shadowOpacity = 0.55
                style.text.shadowRadius = 10
            case .hard:
                style.text.shadowOpacity = 0.9
                style.text.shadowRadius = 2
            }
        }

        public func matches(_ style: CaptionStyle) -> Bool {
            var copy = style
            apply(to: &copy)
            return abs(copy.text.shadowOpacity - style.text.shadowOpacity) < 0.01 && abs(copy.text.shadowRadius - style.text.shadowRadius) < 0.5
        }
    }
}

extension ProjectDocument {
    /// One caption look for the whole project (#259): every other short with captions takes the source
    /// timeline's style. A split-screen or dynamic layout keeps its own caption height, as the presets do.
    @discardableResult
    public mutating func applyCaptionStyle(from sourceTimelineID: UUID) -> Int {
        guard let style = timeline(id: sourceTimelineID)?.captions?.style else { return 0 }
        var count = 0
        for i in timelines.indices where timelines[i].id != sourceTimelineID && timelines[i].captions != nil {
            let keepY = timelines[i].layout == .splitScreen || timelines[i].layout == .dynamic
            let y = timelines[i].captions?.style.positionY ?? style.positionY
            timelines[i].captions?.style = style
            if keepY { timelines[i].captions?.style.positionY = y }
            timelines[i].modifiedAt = Date()
            count += 1
        }
        return count
    }
}

extension ProjectDocument {
    /// "Edit all like this one" (#62): every other short takes this one's layout, background blur, AI framing
    /// setting and caption look. Returns how many changed.
    @discardableResult
    public mutating func applyEditDecisions(from sourceTimelineID: UUID) -> Int {
        guard let source = timeline(id: sourceTimelineID) else { return 0 }
        var count = 0
        for i in timelines.indices where timelines[i].id != sourceTimelineID && EditFormat.of(timelines[i]) == EditFormat.of(source) {
            timelines[i].layout = source.layout
            timelines[i].canvas.backgroundBlur = source.canvas.backgroundBlur
            timelines[i].aiFramingEnabled = source.aiFramingEnabled
            if let style = source.captions?.style, timelines[i].captions != nil { timelines[i].captions?.style = style }
            timelines[i].modifiedAt = Date()
            count += 1
        }
        return count
    }
}
