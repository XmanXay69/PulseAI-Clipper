import XCTest
@testable import PulseCore
@testable import PulseEngine

final class AnalysisCheckpointTests: XCTestCase {
    func testStagesRoundTripAndAChangedFileStartsOver() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-ckpt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("stream.mp4")
        try Data(repeating: 1, count: 1000).write(to: media)
        let asset = MediaAsset(name: "stream", path: media.path, kind: .video)

        let checkpoint = AnalysisCheckpoint(directory: dir, asset: asset, mediaURL: media, voiceURL: nil, settings: "a")
        let transcript = Transcript(language: "en", words: [TranscriptWord(text: "clutch", start: 1, end: 1.4)], source: .whisper)
        let audio = AudioFeatureSeries(hop: 0.1, rmsDB: [-20, -10], peakDB: [-14, -4], zeroCrossingRate: [0.1, 0.1], spectralFlux: [0, 1])
        checkpoint.save(transcript, .transcription)
        checkpoint.save(audio, .audio)
        let again = AnalysisCheckpoint(directory: dir, asset: asset, mediaURL: media, voiceURL: nil, settings: "a")
        XCTAssertEqual(again.load(.transcription) as Transcript?, transcript)
        XCTAssertEqual((again.load(.audio) as AudioFeatureSeries?)?.rmsDB.values, [-20, -10])
        XCTAssertNil(again.load(.video) as VisualFeatureSeries?)

        // Different settings or an edited file don't reuse old results.
        XCTAssertNil(AnalysisCheckpoint(directory: dir, asset: asset, mediaURL: media, voiceURL: nil, settings: "b").load(.transcription) as Transcript?)
        try Data(repeating: 2, count: 2000).write(to: media)
        XCTAssertNil(AnalysisCheckpoint(directory: dir, asset: asset, mediaURL: media, voiceURL: nil, settings: "a").load(.transcription) as Transcript?)

        again.clear()
        XCTAssertNil(again.load(.audio) as AudioFeatureSeries?)
    }
}
