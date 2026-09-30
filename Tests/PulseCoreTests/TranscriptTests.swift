import XCTest
@testable import PulseCore

final class TranscriptTests: XCTestCase {
    func testParseSRTDistributesWordsAndDetectsSpeakers() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        STREAMER: No way that just happened!

        2
        00:00:03,500 --> 00:00:05,000
        <i>Are you kidding me?</i>
        """
        let t = try TranscriptParser.parse(data: Data(srt.utf8), fileExtension: "srt")
        XCTAssertEqual(t.words.count, 9)
        XCTAssertEqual(t.words.first!.text, "No")
        XCTAssertEqual(t.words.first!.start, 1, accuracy: 1e-9)
        XCTAssertEqual(t.words[4].end, 3, accuracy: 1e-6)
        XCTAssertEqual(t.speakers.first?.name, "STREAMER")
        XCTAssertEqual(t.words.last!.text, "me?")
    }

    func testParseVTTWithVoiceSpans() throws {
        let vtt = """
        WEBVTT

        00:00.000 --> 00:02.000 align:start
        <v Alex>Hello there.

        00:02.500 --> 00:04.000
        <v Sam>Hi Alex!
        """
        let t = try TranscriptParser.parse(data: Data(vtt.utf8), fileExtension: "vtt")
        XCTAssertEqual(t.words.count, 4)
        XCTAssertEqual(t.speakerName(t.words[0].speaker), "Alex")
        XCTAssertEqual(t.speakerName(t.words[2].speaker), "Sam")
    }

    func testParseWhisperCppTokens() throws {
        let json = """
        {"result": {"language": "en"},
         "transcription": [
          {"offsets": {"from": 0, "to": 1500}, "text": " Hello world.",
           "tokens": [
             {"text": "[_BEG_]", "offsets": {"from": 0, "to": 0}},
             {"text": " Hel", "offsets": {"from": 0, "to": 300}, "p": 0.9},
             {"text": "lo", "offsets": {"from": 300, "to": 600}, "p": 0.9},
             {"text": " world", "offsets": {"from": 700, "to": 1300}, "p": 0.8},
             {"text": ".", "offsets": {"from": 1300, "to": 1400}, "p": 0.99}
           ]}
         ]}
        """
        let t = try TranscriptParser.parse(data: Data(json.utf8), fileExtension: "json")
        XCTAssertEqual(t.words.map(\.text), ["Hello", "world."])
        XCTAssertEqual(t.words[0].end, 0.6, accuracy: 1e-9)
        XCTAssertEqual(t.language, "en")
    }

    func testParseOpenAIWords() throws {
        let json = """
        {"language": "english", "words": [{"word": "Wait", "start": 0.0, "end": 0.4}, {"word": "what", "start": 0.5, "end": 0.9}]}
        """
        let t = try TranscriptParser.parse(data: Data(json.utf8), fileExtension: "json")
        XCTAssertEqual(t.words.count, 2)
        XCTAssertEqual(t.source, .whisper)
    }

    func testNativeRoundTrip() throws {
        let original = Fixtures.transcript(duration: 30)
        let data = try ProjectStore.makeEncoder().encode(original)
        let parsed = try TranscriptParser.parse(data: data, fileExtension: "json")
        XCTAssertEqual(parsed.words.count, original.words.count)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try TranscriptParser.parse(data: Data("hello".utf8), fileExtension: "txt"))
        XCTAssertThrowsError(try TranscriptParser.parse(data: Data("{}".utf8), fileExtension: "json"))
    }

    func testSentencesAndSearch() {
        let t = Transcript(words: [
            TranscriptWord(text: "Bro", start: 0, end: 0.3),
            TranscriptWord(text: "watch", start: 0.4, end: 0.7),
            TranscriptWord(text: "this.", start: 0.8, end: 1.0),
            TranscriptWord(text: "No", start: 2.5, end: 2.7),
            TranscriptWord(text: "way!", start: 2.8, end: 3.1),
        ], source: .demo)
        let sentences = t.sentences()
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[1].text, "No way!")
        let hits = t.search("no way")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].time, 2.5)
        XCTAssertEqual(t.wordIndices(in: TimeRange(start: 0.35, end: 1.0)), 1..<3)
        XCTAssertEqual(t.wordIndex(at: 2.9), 4)
    }

    func testFillerDetection() {
        let words = ["So", "um", "I", "I", "think", "you", "know", "like", "it's", "fine", "and", "I", "like", "pizza"]
        var t: [TranscriptWord] = []
        for (i, w) in words.enumerated() {
            t.append(TranscriptWord(text: w, start: Double(i) * 0.4, end: Double(i) * 0.4 + 0.3))
        }
        let transcript = Transcript(words: t, source: .demo)
        let found = FillerWordDetector.detect(in: transcript)
        let texts = found.map(\.text)
        XCTAssertTrue(texts.contains("um"))
        XCTAssertTrue(texts.contains("I"), "repeated I should be flagged")
        XCTAssertTrue(texts.contains("you know"))
        // "I like pizza" — keep that "like".
        XCTAssertFalse(found.contains { $0.firstWord == 12 })
        let cuts = FillerWordDetector.cutRanges(for: found.filter { $0.kind == .hesitation }, in: transcript)
        XCTAssertEqual(cuts.count, 1)
        XCTAssertGreaterThanOrEqual(cuts[0].start, t[0].end - 1e-9)
    }

    func testSilenceDetectionUsesAudioAndProtectsWords() {
        let audio = Fixtures.audio(duration: 30, silences: [TimeRange(start: 10, end: 13), TimeRange(start: 20, end: 20.3)])
        let silences = SilenceDetector.detect(audio: audio, transcript: nil, in: TimeRange(start: 0, end: 30), preset: .balanced)
        XCTAssertEqual(silences.count, 1, "0.3 s pause is below the balanced threshold")
        XCTAssertEqual(silences[0].start, 10 + SilencePreset.balanced.padding, accuracy: 0.11)
        XCTAssertEqual(silences[0].end, 13 - SilencePreset.balanced.padding, accuracy: 0.11)

        // A word inside the quiet region protects it.
        let transcript = Transcript(words: [TranscriptWord(text: "psst", start: 11.2, end: 11.6)], source: .demo)
        let protected = SilenceDetector.detect(audio: audio, transcript: transcript, in: TimeRange(start: 0, end: 30), preset: .aggressive)
        XCTAssertTrue(protected.allSatisfy { !$0.contains(11.4) })
    }

    func testSilenceFromTranscriptOnly() {
        let t = Transcript(words: [TranscriptWord(text: "a", start: 0, end: 1), TranscriptWord(text: "b", start: 4, end: 5)], source: .demo)
        let s = SilenceDetector.detect(audio: nil, transcript: t, in: TimeRange(start: 0, end: 5), preset: .conservative)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].start, 1.3, accuracy: 1e-9)
        XCTAssertEqual(s[0].end, 3.7, accuracy: 1e-9)
    }

    func testAudioSyncFindsOffset() {
        var reference = [Float](repeating: -40, count: 600)
        for i in stride(from: 13, to: 600, by: 37) { reference[i] = -5 }
        for i in stride(from: 5, to: 600, by: 53) { reference[i] = -12 }
        // `other` started recording 2.0 s (20 hops) after the reference.
        let other = Array(reference[20...]) + [Float](repeating: -40, count: 20)
        let result = AudioSync.estimateOffset(reference: reference, other: other, hop: 0.1, maxOffset: 5)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.offset, 2.0, accuracy: 0.11)
        XCTAssertGreaterThan(result!.confidence, 0.5)
    }
}
