import Foundation

/// A caption word placed on the timeline.
public struct TimedCaptionWord: Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var start: Seconds
    public var end: Seconds
    public var isEmphasized: Bool
    public var speaker: Int?
}

/// A group of words shown together.
public struct CaptionPage: Hashable, Sendable {
    public var index: Int
    public var range: TimeRange
    public var lines: [[TimedCaptionWord]]
    public var words: [TimedCaptionWord] { lines.flatMap { $0 } }
    public var text: String { lines.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n") }
}

/// Maps source-time captions through the timeline and paginates them.
public enum CaptionLayoutEngine {
    /// Caption words in timeline time, following every clip that shows the captioned asset.
    public static func timelineWords(_ track: CaptionTrack, in timeline: Timeline) -> [TimedCaptionWord] {
        let clips = timeline.tracks.flatMap(\.clips).filter { $0.assetID == track.sourceAssetID && $0.isEnabled }
        guard !clips.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [TimedCaptionWord] = []
        let words = track.words.filter { !$0.isHidden }
        for clip in clips {
            let src = clip.sourceRange
            // Binary search the first candidate word.
            var lo = 0
            var hi = words.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if words[mid].end <= src.start { lo = mid + 1 } else { hi = mid }
            }
            var i = lo
            while i < words.count, words[i].start < src.end {
                let w = words[i]
                i += 1
                let mid = (w.start + w.end) / 2
                guard src.contains(mid) else { continue }
                let start = clip.timelineTime(atSource: max(w.start, src.start))
                let end = clip.timelineTime(atSource: min(w.end, src.end))
                let key = "\(w.id.uuidString)@\(Int((start * 100).rounded()))"
                guard seen.insert(key).inserted else { continue }
                let display = displayText(w.text, style: track.style, profanity: track.profanity)
                guard !display.isEmpty else { continue }
                result.append(TimedCaptionWord(id: w.id, text: display, start: start, end: max(end, start + 0.05),
                                               isEmphasized: w.isEmphasized, speaker: w.speaker))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    static func displayText(_ text: String, style: CaptionStyle, profanity: ProfanityMode) -> String {
        var t = text
        if profanity != .off, EngagementLexicon.profanity.contains(TranscriptWord.normalize(text)) {
            switch profanity {
            case .off: break
            case .mask:
                let core = TranscriptWord.normalize(text)
                let masked = String(core.prefix(1)) + String(repeating: "*", count: max(core.count - 1, 2))
                t = t.replacingOccurrences(of: core, with: masked, options: .caseInsensitive)
            case .bleepText: t = "[bleep]"
            case .hide: return ""
            }
        }
        return style.text.textCase.apply(t)
    }

    /// Splits timed words into pages according to the style.
    public static func pages(_ words: [TimedCaptionWord], style: CaptionStyle) -> [CaptionPage] {
        guard !words.isEmpty else { return [] }
        let maxWords = style.displayMode == .wordByWord ? 1 : max(1, style.maxWordsPerPage)
        let maxChars = max(4, style.maxCharsPerLine)
        let maxLines = max(1, style.maxLines)
        var groups: [[TimedCaptionWord]] = []
        var current: [TimedCaptionWord] = []
        func charCount(_ ws: [TimedCaptionWord]) -> Int { ws.map(\.text.count).reduce(0, +) + max(ws.count - 1, 0) }
        for (i, w) in words.enumerated() {
            if let last = current.last {
                let gap = w.start - last.end
                let sentenceBreak = last.text.hasSuffix(".") || last.text.hasSuffix("!") || last.text.hasSuffix("?")
                let tooLong = charCount(current + [w]) > maxChars * maxLines
                if current.count >= maxWords || gap > 0.8 || sentenceBreak || tooLong || w.speaker != last.speaker {
                    groups.append(current)
                    current = []
                }
            }
            current.append(w)
            if i == words.count - 1 { groups.append(current) }
        }
        var pages: [CaptionPage] = []
        for (gi, group) in groups.enumerated() {
            // Wrap into lines.
            var lines: [[TimedCaptionWord]] = [[]]
            for w in group {
                let candidate = lines[lines.count - 1] + [w]
                if !lines[lines.count - 1].isEmpty, charCount(candidate) > maxChars, lines.count < maxLines {
                    lines.append([w])
                } else {
                    lines[lines.count - 1].append(w)
                }
            }
            let start = group.first!.start
            let nextStart = gi + 1 < groups.count ? groups[gi + 1].first!.start : Double.infinity
            let end = min(nextStart, group.last!.end + 0.6)
            pages.append(CaptionPage(index: gi, range: TimeRange(start: start, end: max(end, start + 0.1)), lines: lines))
        }
        return pages
    }

    /// Page visible at `time` (binary search over sorted pages).
    public static func page(at time: Seconds, in pages: [CaptionPage]) -> CaptionPage? {
        var lo = 0
        var hi = pages.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = pages[mid].range
            if time < r.start { hi = mid - 1 } else if time >= r.end { lo = mid + 1 } else { return pages[mid] }
        }
        return nil
    }

    /// Index (into `page.words`) of the word being spoken, or the last spoken word.
    public static func activeWordIndex(in page: CaptionPage, at time: Seconds) -> Int? {
        let words = page.words
        var active: Int?
        for (i, w) in words.enumerated() where w.start <= time { active = i }
        return active
    }

    /// Exports visible captions as SRT (one cue per page).
    public static func srt(track: CaptionTrack, timeline: Timeline) -> String {
        let captionPages = Self.pages(timelineWords(track, in: timeline), style: track.style)
        return TranscriptParser.srt(from: captionPages.map { ($0.range, $0.text.replacingOccurrences(of: "\n", with: " ")) })
    }
}

/// Platform UI overlays to keep captions/text clear of.
public enum SafeAreaPlatform: String, Codable, CaseIterable, Sendable {
    case tiktok
    case youtubeShorts
    case instagramReels

    public var displayName: String {
        switch self {
        case .tiktok: return "TikTok"
        case .youtubeShorts: return "YouTube Shorts"
        case .instagramReels: return "Instagram Reels"
        }
    }

    /// Normalized insets (top, bottom, left, right) for a 9:16 frame.
    public var insets: (top: Double, bottom: Double, left: Double, right: Double) {
        switch self {
        case .tiktok: return (0.09, 0.2, 0.04, 0.14)
        case .youtubeShorts: return (0.08, 0.18, 0.04, 0.14)
        case .instagramReels: return (0.1, 0.21, 0.04, 0.14)
        }
    }

    /// The region free of platform UI.
    public var safeRect: NormRect {
        let i = insets
        return NormRect(x: i.left, y: i.top, width: 1 - i.left - i.right, height: 1 - i.top - i.bottom)
    }

    /// Moves a block's center so a block of `height` (normalized) stays inside the safe rect.
    public func clampCenterY(_ y: Double, blockHeight: Double) -> Double {
        let r = safeRect
        let half = blockHeight / 2
        return y.clamped(r.minY + half, max(r.minY + half, r.maxY - half))
    }

    public func clampCenterX(_ x: Double, blockWidth: Double) -> Double {
        let r = safeRect
        let half = blockWidth / 2
        return x.clamped(r.minX + half, max(r.minX + half, r.maxX - half))
    }
}
