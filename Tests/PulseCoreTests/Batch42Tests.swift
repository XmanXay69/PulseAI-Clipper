import XCTest
@testable import PulseCore

final class Batch42Tests: XCTestCase {
    // MARK: #248 — translated captions keep the timing and both languages stay

    private func track() -> CaptionTrack {
        let words = [
            CaptionWord(text: "Okay", start: 0, end: 0.3, speaker: 0), CaptionWord(text: "chat,", start: 0.3, end: 0.6, speaker: 0),
            CaptionWord(text: "we", start: 0.6, end: 0.8, speaker: 0), CaptionWord(text: "won.", start: 0.8, end: 1.2, speaker: 0),
            CaptionWord(text: "No", start: 1.4, end: 1.6, speaker: 1), CaptionWord(text: "way!", start: 1.6, end: 2.0, speaker: 1),
            CaptionWord(text: "Thanks", start: 4.0, end: 4.4, speaker: 1), CaptionWord(text: "everyone", start: 4.4, end: 5.0, speaker: 1),
        ]
        return CaptionTrack(sourceAssetID: UUID(), words: words, style: .bold)
    }

    func testSentencesBreakOnPunctuationSpeakersAndPauses() {
        let sentences = CaptionTranslator.sentences(in: track())
        XCTAssertEqual(sentences.map(\.text), ["Okay chat, we won.", "No way!", "Thanks everyone"])
        XCTAssertEqual(sentences.map(\.speaker), [0, 1, 1])
        XCTAssertEqual(sentences[2].range.start, 4.0, accuracy: 1e-9)
        XCTAssertEqual(sentences[2].range.end, 5.0, accuracy: 1e-9)
    }

    func testTranslatedTrackSpreadsWordsOverEachSentence() throws {
        let original = track()
        let sentences = CaptionTranslator.sentences(in: original)
        let translated = try XCTUnwrap(CaptionTranslator.track(from: original, sentences: sentences, translations: ["Vale chat, ganamos.", "¡No puede ser!", "Gracias a todos"]))
        XCTAssertEqual(translated.sourceAssetID, original.sourceAssetID)
        XCTAssertEqual(translated.style, original.style)
        XCTAssertTrue(translated.aiGenerated)
        let first = translated.words.filter { $0.start < 1.3 }
        XCTAssertEqual(first.map(\.text), ["Vale", "chat,", "ganamos."])
        XCTAssertEqual(first.first?.start ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(first.last?.end ?? -1, 1.2, accuracy: 0.05)
        XCTAssertEqual(translated.words.last?.speaker, 1)
        XCTAssertNil(CaptionTranslator.track(from: original, sentences: sentences, translations: ["only one"]), "counts must match")
        XCTAssertEqual(CaptionTranslator.name(for: "es"), "Spanish")
    }

    func testSwitchingLanguagesKeepsTheOriginal() {
        var timeline = Timeline.empty(name: "T", canvas: .vertical1080)
        let original = track()
        timeline.captions = original
        var spanish = original
        spanish.words = [CaptionWord(text: "Hola", start: 0, end: 1)]
        timeline.addCaptionTranslation(spanish, language: "es")
        XCTAssertEqual(timeline.captionLanguages, [nil, "es"])
        XCTAssertEqual(timeline.captions?.words.count, 8, "adding doesn't switch")
        timeline.switchCaptions(to: "es")
        XCTAssertEqual(timeline.captionLanguage, "es")
        XCTAssertEqual(timeline.captions?.words.first?.text, "Hola")
        XCTAssertEqual(timeline.captionTranslations["original"]?.words.count, 8)
        XCTAssertEqual(timeline.captionLanguages, [nil, "es"], "the original still counts as a language")
        timeline.switchCaptions(to: nil)
        XCTAssertNil(timeline.captionLanguage)
        XCTAssertEqual(timeline.captions?.words.count, 8)
        XCTAssertEqual(timeline.captionTranslations["es"]?.words.first?.text, "Hola")
        let decoded = try! JSONDecoder().decode(Timeline.self, from: JSONEncoder().encode(timeline))
        XCTAssertEqual(decoded.captionTranslations.keys.sorted(), ["es"])
    }

    func testTranslationPromptParsesCountedSentences() throws {
        XCTAssertEqual(try TranslationPrompt.parse(["sentences": ["a", "b"]], expected: 2), ["a", "b"])
        XCTAssertThrowsError(try TranslationPrompt.parse(["sentences": ["a"]], expected: 2))
        XCTAssertThrowsError(try TranslationPrompt.parse([:], expected: 1))
        let prompt = TranslationPrompt.user(sentences: ["Hi there"], from: "en", to: "Spanish")
        XCTAssertTrue(prompt.contains("1. Hi there"))
        XCTAssertTrue(prompt.contains("exactly 1 strings"))
    }
}
