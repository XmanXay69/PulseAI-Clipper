import XCTest
@testable import PulseCore

/// Roadmap batch 14: file chapters (#12), one-sided audio (#272), re-transcribed stretches (#42), YouTube links (#1 #467).
final class Batch14Tests: XCTestCase {
    func testFileChaptersBecomeMarkersInTheEdit() {
        let duration: Seconds = 3000
        let spikes = Array(stride(from: 150.0, to: 2900, by: 230))
        var special: [(Seconds, String)] = []
        for s in spikes { for k in 0..<4 { special.append((s + 1 + Double(k) * 0.5, "hahaha")) } }
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration, audio: Fixtures.audio(duration: duration, spikes: spikes),
                                     transcript: Fixtures.transcript(duration: duration, special: special), profile: .gameplay)
        var asset = Fixtures.mediaAsset(duration: duration)
        asset.metadata.chapters = [ChapterMark(time: 151, title: "Warmup"), ChapterMark(time: 2500, title: ""), ChapterMark(time: 2999, title: "Outro")]
        let result = LongFormEditor.build(asset: asset, analysis: analysis, options: LongFormOptions())
        let names = result.timeline.markers.filter { $0.color == .blue }.map(\.name)
        XCTAssertTrue(names.contains("Warmup"), "\(names)")
        XCTAssertFalse(names.contains(""), "an empty title gets a name")
        XCTAssertEqual(result.timeline.markers, result.timeline.markers.sorted { $0.time < $1.time })
        let meta = try? JSONDecoder().decode(MediaMetadata.self, from: JSONEncoder().encode(asset.metadata))
        XCTAssertEqual(meta?.chapters?.count, 3)
    }

    func testOneSidedAudioFoldsToBothEars() {
        var settings = AudioSettings()
        settings.monoSource = .left
        let left: [Float] = (0..<4800).map { sin(Double($0) * 0.05) > 0 ? 0.5 : -0.5 }
        let right = [Float](repeating: 0, count: 4800)
        var channels = [left, right]
        AudioEnhanceChain.process(&channels, sampleRate: 48_000, settings: settings)
        XCTAssertEqual(channels.count, 2)
        XCTAssertGreaterThan(channels[1].map { abs($0) }.max() ?? 0, 0.1, "the silent side got the sound")
        XCTAssertEqual(channels[0], channels[1])
        var plain = AudioSettings()
        var untouched = [left, right]
        AudioEnhanceChain.process(&untouched, sampleRate: 48_000, settings: plain)
        XCTAssertEqual(untouched[1].map { abs($0) }.max() ?? 0, 0, "stereo stays as recorded")
        plain.monoSource = .right
        XCTAssertNotEqual(settings.enhanceFingerprint, plain.enhanceFingerprint)
        XCTAssertNotEqual(settings.enhanceFingerprint, AudioSettings().enhanceFingerprint)
        XCTAssertEqual(try? JSONDecoder().decode(AudioSettings.self, from: Data("{}".utf8)).monoSource, .stereo)
        var meta = MediaMetadata(duration: 1)
        meta.audioOnlyChannel = 0
        XCTAssertEqual(try? JSONDecoder().decode(MediaMetadata.self, from: JSONEncoder().encode(meta)).audioOnlyChannel, 0)
    }

    func testReplacingAStretchOfTranscript() {
        var words: [TranscriptWord] = []
        for i in 0..<20 { words.append(TranscriptWord(text: "w\(i)", start: Double(i), end: Double(i) + 0.8, speaker: 0)) }
        let transcript = Transcript(language: "en", words: words, source: .whisper)
        let fresh = [TranscriptWord(text: "five", start: 5.1, end: 5.9), TranscriptWord(text: "six", start: 6.1, end: 6.9), TranscriptWord(text: "late", start: 9.5, end: 9.9)]
        let merged = transcript.replacingWords(in: TimeRange(start: 5, end: 8), with: fresh)
        let texts = merged.words.map(\.text)
        XCTAssertEqual(texts.prefix(5).map { $0 }, ["w0", "w1", "w2", "w3", "w4"])
        XCTAssertEqual(texts[5], "five")
        XCTAssertEqual(texts[6], "six")
        XCTAssertEqual(texts[7], "w8", "the old words in the stretch are gone, the ones after stay")
        XCTAssertFalse(texts.contains("late"), "fresh words outside the stretch are ignored")
        XCTAssertFalse(texts.contains("w5") || texts.contains("w6") || texts.contains("w7"))
        XCTAssertEqual(merged.source, .whisper)
        XCTAssertEqual(merged.words, merged.words.sorted { $0.start < $1.start })
    }

    func testYouTubeLinksAreRecognised() {
        XCTAssertEqual(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5s"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeURL.videoID(from: " https://youtu.be/dQw4w9WgXcQ\n"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeURL.videoID(from: "https://youtube.com/shorts/abcDEF12345?feature=share"), "abcDEF12345")
        XCTAssertEqual(YouTubeURL.videoID(from: "https://www.youtube.com/live/abcDEF12345"), "abcDEF12345")
        XCTAssertNil(YouTubeURL.videoID(from: "https://www.twitch.tv/videos/123456"))
        XCTAssertNil(YouTubeURL.videoID(from: "just some text"))
    }
}
