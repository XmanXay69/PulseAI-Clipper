import Foundation

public struct TranscriptWord: Codable, Hashable, Sendable {
    public var text: String
    public var start: Seconds
    public var end: Seconds
    public var confidence: Float?
    public var speaker: Int?

    public init(text: String, start: Seconds, end: Seconds, confidence: Float? = nil, speaker: Int? = nil) {
        self.text = text
        self.start = start
        self.end = max(start, end)
        self.confidence = confidence
        self.speaker = speaker
    }

    public var range: TimeRange { TimeRange(start: start, end: end) }

    /// Lowercased text without surrounding punctuation, for matching.
    public var normalized: String {
        TranscriptWord.normalize(text)
    }

    public static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).union(.symbols))
    }

    public var endsSentence: Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return last == "." || last == "!" || last == "?" || last == "…"
    }

    public var isQuestion: Bool { text.hasSuffix("?") }
    public var isExclamation: Bool { text.hasSuffix("!") }
}

public struct Speaker: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public enum TranscriptSource: String, Codable, Sendable {
    case appleSpeech
    case whisper
    case imported
    case cloud
    case demo

    public var displayName: String {
        switch self {
        case .appleSpeech: return "Apple On-Device Speech"
        case .whisper: return "Whisper (local)"
        case .imported: return "Imported subtitles"
        case .cloud: return "Cloud AI"
        case .demo: return "Sample transcript"
        }
    }

    public var location: ProcessingLocation {
        self == .cloud ? .cloud : .local
    }
}

/// A sentence reconstructed from words (used by the transcript editor and clip boundaries).
public struct TranscriptSentence: Hashable, Sendable, Identifiable {
    public var id: Int { firstWord }
    public var firstWord: Int
    public var lastWord: Int
    public var start: Seconds
    public var end: Seconds
    public var text: String
    public var speaker: Int?

    public var range: TimeRange { TimeRange(start: start, end: end) }
    public var wordCount: Int { lastWord - firstWord + 1 }
}

public struct TranscriptHit: Hashable, Sendable {
    public var wordIndex: Int
    public var time: Seconds
    public var context: String
}

/// Word-level transcript of one media asset. Times are in the asset's source time.
public struct Transcript: Codable, Hashable, Sendable {
    public var language: String?
    public var words: [TranscriptWord]
    public var speakers: [Speaker]
    public var source: TranscriptSource
    public var createdAt: Date

    public init(language: String? = nil, words: [TranscriptWord], speakers: [Speaker] = [], source: TranscriptSource, createdAt: Date = Date()) {
        self.language = language
        self.words = words.sorted { $0.start < $1.start }
        self.speakers = speakers
        self.source = source
        self.createdAt = createdAt
    }

    public var isEmpty: Bool { words.isEmpty }
    public var duration: Seconds { words.last?.end ?? 0 }
    public var fullText: String { words.map(\.text).joined(separator: " ") }

    public func speakerName(_ id: Int?) -> String? {
        guard let id else { return nil }
        return speakers.first { $0.id == id }?.name ?? "Speaker \(id + 1)"
    }

    /// Index of the first word whose end is after `time` (binary search).
    public func firstWordIndex(endingAfter time: Seconds) -> Int {
        var lo = 0
        var hi = words.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if words[mid].end <= time { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Indices of words overlapping `range` (by word midpoint).
    public func wordIndices(in range: TimeRange) -> Range<Int> {
        let lower = firstWordIndex(endingAfter: range.start)
        var upper = lower
        while upper < words.count, words[upper].start < range.end {
            upper += 1
        }
        var result = lower..<upper
        // Drop edge words whose midpoint lies outside the range.
        if let first = result.first, !range.contains((words[first].start + words[first].end) / 2) { result = (first + 1)..<result.upperBound }
        if let last = result.last, result.count > 0, !range.contains((words[last].start + words[last].end) / 2) { result = result.lowerBound..<last }
        return result
    }

    public func words(in range: TimeRange) -> ArraySlice<TranscriptWord> {
        words[wordIndices(in: range)]
    }

    public func text(in range: TimeRange) -> String {
        words(in: range).map(\.text).joined(separator: " ")
    }

    /// The word being spoken at `time`, if any.
    public func wordIndex(at time: Seconds) -> Int? {
        let i = firstWordIndex(endingAfter: time)
        guard i < words.count, words[i].start <= time else { return nil }
        return i
    }

    /// Splits words into sentences using punctuation, speaker changes and long pauses.
    public func sentences(pauseThreshold: Seconds = 0.9, maxWords: Int = 40) -> [TranscriptSentence] {
        guard !words.isEmpty else { return [] }
        var result: [TranscriptSentence] = []
        var first = 0
        func close(_ last: Int) {
            let slice = words[first...last]
            result.append(TranscriptSentence(firstWord: first, lastWord: last, start: slice.first!.start, end: slice.last!.end,
                                             text: slice.map(\.text).joined(separator: " "), speaker: slice.first!.speaker))
            first = last + 1
        }
        for i in words.indices {
            let w = words[i]
            let isLast = i == words.count - 1
            if isLast { close(i); break }
            let next = words[i + 1]
            let pause = next.start - w.end
            if w.endsSentence || pause >= pauseThreshold || next.speaker != w.speaker || (i - first + 1) >= maxWords {
                close(i)
            }
        }
        return result
    }

    /// Case-insensitive phrase search.
    public func search(_ query: String, contextWords: Int = 6) -> [TranscriptHit] {
        let terms = query.lowercased().split(separator: " ").map { TranscriptWord.normalize(String($0)) }.filter { !$0.isEmpty }
        guard !terms.isEmpty, words.count >= terms.count else { return [] }
        let normalized = words.map(\.normalized)
        var hits: [TranscriptHit] = []
        var i = 0
        while i <= normalized.count - terms.count {
            var match = true
            for (k, term) in terms.enumerated() where !normalized[i + k].hasPrefix(term) {
                match = false
                break
            }
            if match {
                let lo = max(0, i - contextWords)
                let hi = min(words.count, i + terms.count + contextWords)
                let context = words[lo..<hi].map(\.text).joined(separator: " ")
                hits.append(TranscriptHit(wordIndex: i, time: words[i].start, context: context))
                i += terms.count
            } else {
                i += 1
            }
        }
        return hits
    }

    /// Words per second in a window (speech rate signal).
    public func speechRate(in range: TimeRange) -> Double {
        guard range.duration > 0 else { return 0 }
        return Double(wordIndices(in: range).count) / range.duration
    }

    /// Replaces the text of a word (transcript editor). Keeps timing.
    public mutating func editWord(at index: Int, text: String) {
        guard words.indices.contains(index) else { return }
        words[index].text = text
    }

    public mutating func renameSpeaker(id: Int, to name: String) {
        if let i = speakers.firstIndex(where: { $0.id == id }) {
            speakers[i].name = name
        } else {
            speakers.append(Speaker(id: id, name: name))
            speakers.sort { $0.id < $1.id }
        }
    }

    /// Shifts all timings (used when syncing separately-recorded audio).
    public func offset(by delta: Seconds) -> Transcript {
        var copy = self
        copy.words = words.map { w in
            var w = w
            w.start += delta
            w.end += delta
            return w
        }
        return copy
    }

    /// Speaker ids that appear in the transcript.
    public var speakerIDs: [Int] {
        Array(Set(words.compactMap(\.speaker))).sorted()
    }
}
