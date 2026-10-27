import Foundation

/// Translates caption text (#248). Implemented by the cloud providers and by any OpenAI-compatible local
/// server; nothing in PULSE's own code sends text anywhere without the privacy policy allowing it.
public protocol TranslationProvider: AIProvider {
    /// One translated sentence per input sentence, in order, in `language` (a BCP-47 code such as "es").
    func translate(sentences: [String], from source: String?, to language: String) async throws -> [String]
}

/// Builds a translated caption track that keeps the original's timing (#248): sentences are translated
/// whole, and each translation's words are spread over the sentence's span, so the captions still land
/// on the beats of the speech.
public enum CaptionTranslator {
    public struct Sentence: Hashable, Sendable {
        public var range: TimeRange
        public var text: String
        public var speaker: Int?
    }

    /// Languages offered in the menu: code → name.
    public static let languages: [(code: String, name: String)] = [
        ("es", "Spanish"), ("pt", "Portuguese"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("nl", "Dutch"),
        ("pl", "Polish"), ("tr", "Turkish"), ("ru", "Russian"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"),
        ("hi", "Hindi"), ("ar", "Arabic"), ("id", "Indonesian"), ("en", "English"),
    ]

    public static func name(for code: String) -> String {
        languages.first { $0.code == code }?.name ?? Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    /// Groups the track's visible words into sentences: a break at sentence punctuation, a pause over
    /// 0.8 s, a change of speaker, or 24 words.
    public static func sentences(in track: CaptionTrack) -> [Sentence] {
        var out: [Sentence] = []
        var current: [CaptionWord] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            out.append(Sentence(range: TimeRange(start: first.start, end: max(last.end, first.start + 0.1)),
                                text: current.map(\.text).joined(separator: " "), speaker: first.speaker))
            current = []
        }
        for word in track.words where !word.isHidden {
            if let last = current.last {
                let gap = word.start - last.end
                let punctuated = last.text.hasSuffix(".") || last.text.hasSuffix("!") || last.text.hasSuffix("?")
                if punctuated || gap > 0.8 || word.speaker != last.speaker || current.count >= 24 { flush() }
            }
            current.append(word)
        }
        flush()
        return out
    }

    /// The translated track: the original's style, speakers and asset, new words spread over each sentence.
    public static func track(from original: CaptionTrack, sentences: [Sentence], translations: [String]) -> CaptionTrack? {
        guard sentences.count == translations.count, !sentences.isEmpty else { return nil }
        var words: [CaptionWord] = []
        for (sentence, text) in zip(sentences, translations) {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let placed = TranscriptParser.distribute(text: cleaned, over: sentence.range, speaker: sentence.speaker)
            for w in placed {
                words.append(CaptionWord(text: w.text, start: w.start, end: w.end, speaker: sentence.speaker))
            }
        }
        guard !words.isEmpty else { return nil }
        var track = original
        track.words = words.sorted { $0.start < $1.start }
        track.aiGenerated = true
        return track
    }
}
