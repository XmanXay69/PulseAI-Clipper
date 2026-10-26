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

extension CaptionTrack {
    static let fillerOnly: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "ah", "hmm", "mhm", "mm"]

    /// Sentence case for every word (#239): the first word of a sentence capitalised, shouting lowered; "I",
    /// short all-caps words (GG, OBS, NPC) and words with digits stay. Returns words changed.
    @discardableResult
    public mutating func applySentenceCase() -> Int {
        var changed = 0
        var startOfSentence = true
        for i in words.indices {
            let text = words[i].text
            let letters = text.filter(\.isLetter)
            guard !letters.isEmpty else { continue }
            let hasDigits = text.contains(where: \.isNumber)
            let acronym = letters.count >= 2 && letters.count <= 3 && letters == letters.uppercased() && !startOfSentence
            var new = text
            if !acronym && !hasDigits {
                new = text.lowercased()
                let lowered = new
                if startOfSentence || lowered == "i" || lowered.hasPrefix("i'") || lowered.hasPrefix("i’") {
                    if let first = new.firstIndex(where: \.isLetter) {
                        new.replaceSubrange(first...first, with: String(new[first]).uppercased())
                    }
                }
            }
            if new != text {
                words[i].text = new
                changed += 1
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            startOfSentence = trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || trimmed.hasSuffix("…")
        }
        return changed
    }

    /// Removes "um", "uh" and friends from the captions (#239) — the audio keeps them. Returns words removed.
    @discardableResult
    public mutating func stripFillers() -> Int {
        let before = words.count
        words.removeAll { CaptionTrack.fillerOnly.contains(TranscriptWord.normalize($0.text)) }
        return before - words.count
    }

    /// Moves only the words from `after` on (#241) — fixes a transcript that drifts late after a re-cut.
    @discardableResult
    public mutating func shiftTiming(by delta: Seconds, after: Seconds) -> Int {
        guard delta != 0 else { return 0 }
        var count = 0
        for i in words.indices where words[i].start >= after {
            let d = max(delta, -words[i].start)
            words[i].start += d
            words[i].end += d
            count += 1
        }
        return count
    }
}

extension SafeAreaPlatform {
    /// Where captions sit clear of this platform's own UI (#245): just above the bottom zone it covers.
    public var captionCenterY: Double { (1 - insets.bottom - 0.09).clamped(0.5, 0.8) }
}

extension CaptionStyle {
    /// Captions above the platform's caption and button zone (#245).
    public mutating func position(for platform: SafeAreaPlatform) { positionY = platform.captionCenterY }
}

extension CaptionTrack {
    /// Fresh captions from a new transcript that keep your fixes (#258): a word you retyped keeps its text
    /// where a word still sits at that time, hidden words stay hidden, and emphasis you set by hand stays.
    /// `previous` is the transcript the old captions came from (to tell your edits from re-transcription);
    /// without it, any word that differs from the new transcript counts as yours.
    public static func rebuilt(from transcript: Transcript, range: TimeRange, assetID: UUID, keeping old: CaptionTrack, previous: Transcript? = nil,
                               emphasize: Bool) -> CaptionTrack {
        var fresh = make(from: transcript, range: range, assetID: assetID, style: old.style, emphasize: emphasize)
        fresh.isEnabled = old.isEnabled
        fresh.profanity = old.profanity
        fresh.showSpeakerLabels = old.showSpeakerLabels
        fresh.speakerStyles = old.speakerStyles
        for (k, v) in old.speakerNames { fresh.speakerNames[k] = v }
        let transcriptWords = (previous ?? transcript).words(in: range)
        var kept = 0
        for oldWord in old.words {
            // The transcript's own word at this time: if the old caption differs from it, you changed it.
            let original = transcriptWords.first { abs($0.start - oldWord.start) < 0.15 }
            let edited = original.map { TranscriptWord.normalize($0.text) != TranscriptWord.normalize(oldWord.text) } ?? false
            let manualEmphasis = oldWord.isEmphasized && !oldWord.emphasisIsAI
            guard edited || oldWord.isHidden || manualEmphasis,
                  let i = fresh.words.firstIndex(where: { abs($0.start - oldWord.start) < 0.15 }) else { continue }
            if edited { fresh.words[i].text = oldWord.text }
            if oldWord.isHidden { fresh.words[i].isHidden = true }
            if manualEmphasis {
                fresh.words[i].isEmphasized = true
                fresh.words[i].emphasisIsAI = false
            }
            kept += 1
        }
        fresh.aiGenerated = kept == 0 && old.aiGenerated
        return fresh
    }
}
