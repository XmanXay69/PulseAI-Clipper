import XCTest
@testable import PulseCore

/// Roadmap batch 13: speaker leveling (#266), edit report (#107), review page (#471), handle on the end screen
/// (#374), tempo (#135), colour primaries (#203), compact timeline (#182).
final class Batch13Tests: XCTestCase {
    func testGuestsAreLeveledToTheHost() {
        // Host (speaker 0) around −18 dB, guest (speaker 1) around −26 dB, a third voice too rare to touch.
        let hop = 0.1
        let n = 1200
        var rms = [Float](repeating: -40, count: n)
        var words: [TranscriptWord] = []
        var t = 0.0
        var i = 0
        while t < 110 {
            let speaker = i % 3 == 2 ? 1 : 0
            words.append(TranscriptWord(text: "w", start: t, end: t + 0.3, speaker: speaker))
            let level: Float = speaker == 0 ? -18 : -26
            for k in Int(t / hop)..<min(n, Int((t + 0.4) / hop)) { rms[k] = level }
            t += 0.5
            i += 1
        }
        words.append(TranscriptWord(text: "hi", start: 115, end: 115.3, speaker: 2))
        let audio = AudioFeatureSeries(hop: hop, rmsDB: rms, peakDB: rms, zeroCrossingRate: [Float](repeating: 0, count: n), spectralFlux: [Float](repeating: 0, count: n))
        let gains = SpeakerLeveler.gains(words: words, audio: audio)
        XCTAssertEqual(gains[1] ?? 0, 8, accuracy: 0.6, "\(gains)")
        XCTAssertNil(gains[0], "the host is the reference")
        XCTAssertNil(gains[2], "too few words to judge")
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.tracks[3].clips[0].sourceIn = 0
        timeline.tracks[0].clips[0].sourceIn = 0
        let added = SpeakerLeveler.apply(&timeline, assetID: Fixtures.assetID, words: words, gains: gains)
        XCTAssertGreaterThan(added, 10)
        let volume = timeline.tracks[3].clips[0].audio.volume
        XCTAssertEqual(volume.value(at: 0.1), 1, accuracy: 1e-6, "host first")
        XCTAssertEqual(volume.value(at: 1.1), pow(10, (gains[1] ?? 0) / 20), accuracy: 1e-6, "the guest's words at 1.0 s are louder")
        XCTAssertEqual(volume.value(at: 1.6), 1, accuracy: 1e-6, "back to the host")
        XCTAssertTrue(volume.keyframes.allSatisfy { $0.aiGenerated && $0.interpolation == .hold })
        XCTAssertEqual(SpeakerLeveler.apply(&timeline, assetID: Fixtures.assetID, words: words, gains: [:]), 0)
    }

    func testEditReportReadsTheTimeline() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 60)
        timeline.markers = [Marker(time: 5, name: "The clutch", color: .blue), Marker(time: 20, name: "TODO fix zoom", color: .red)]
        timeline.removedSections = [RemovedSection(assetID: Fixtures.assetID, sourceRange: TimeRange(start: 110, end: 114), reason: .silence, aiGenerated: true),
                                    RemovedSection(assetID: Fixtures.assetID, sourceRange: TimeRange(start: 130, end: 131), reason: .fillerWord, text: "um", aiGenerated: true)]
        if let t1 = timeline.tracks.firstIndex(where: { $0.kind == .text }) {
            timeline.tracks[t1].clips.append(TimelineClip(name: "Meme", content: .text(TextElement(text: "BRUH", style: TextStyle())), start: 8, sourceDuration: 1.5, aiGenerated: true))
            timeline.tracks[t1].clips.append(TimelineClip(name: "Title Card", content: .text(TextElement(text: "THEN", style: TextStyle())), start: 30, sourceDuration: 1.5, aiGenerated: true))
        }
        timeline.tracks[0].clips[0].transform.zoom.setKeyframe(at: 1, value: 1, aiGenerated: true)
        timeline.tracks[0].clips[0].transform.zoom.setKeyframe(at: 1.3, value: 1.2, aiGenerated: true)
        timeline.tracks[0].clips[0].transform.zoom.setKeyframe(at: 3, value: 1, aiGenerated: true)
        let report = EditReport.build(timeline: timeline)
        let titles = report.sections.map(\.title)
        XCTAssertEqual(titles, ["Overview", "Chapters", "What was cut", "Added", "To do"], "\(titles)")
        XCTAssertTrue(report.sections[0].lines[0].text.hasPrefix("1m 00s long"), report.sections[0].lines[0].text)
        XCTAssertEqual(report.sections[1].lines.first?.time, 5)
        let cut = report.sections[2].lines
        XCTAssertTrue(cut.contains { $0.text.hasPrefix("Silence: 1 cut, 4s") }, "\(cut.map(\.text))")
        XCTAssertTrue(cut.contains { $0.text.contains("“um”") })
        XCTAssertTrue(cut.contains { $0.time != nil }, "cuts point into the edit")
        let added = report.sections[3].lines.map(\.text)
        XCTAssertTrue(added.contains("1 zoom"), "\(added)")
        XCTAssertTrue(added.contains("1 meme pop-up"))
        XCTAssertTrue(added.contains("1 title card"))
        XCTAssertEqual(report.sections[4].lines.first?.time, 20)
        XCTAssertTrue(report.text.contains("## What was cut"))
    }

    func testReviewPageIsSelfContainedHTML() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 10)
        timeline.name = "Cut <one> & two"
        timeline.notes = "Check the <intro>"
        timeline.markers = [Marker(time: 2, name: "Chapter 1", color: .blue)]
        var asset = Fixtures.mediaAsset()
        asset.name = "VOD & more.mp4"
        let html = ReviewPage.html(timeline: timeline, projectName: "P", assets: [asset], reviewer: "Sam")
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<title>P — Cut &lt;one&gt; &amp; two review</title>"))
        XCTAssertTrue(html.contains("VOD &amp; more.mp4"))
        XCTAssertTrue(html.contains("Check the &lt;intro&gt;"))
        XCTAssertTrue(html.contains("<b>00:00:02:00</b> Chapter 1") || html.contains("00:00:02") , html)
        XCTAssertTrue(html.contains("for Sam"))
        XCTAssertEqual(html.components(separatedBy: "<tr><td>").count - 1, 2, "one row per clip")
        XCTAssertFalse(html.contains("<script"))
    }

    func testEndScreenCarriesYourHandle() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        EditPolish.addEndScreen(&timeline, handle: "xav")
        let subtitle = timeline.tracks.flatMap(\.clips).first { $0.name == "End Screen Subtitle" }
        if case .text(let element)? = subtitle?.content { XCTAssertEqual(element.text, "@xav · more videos →") } else { XCTFail("no subtitle") }
        var plain = Fixtures.simpleTimeline(clipDuration: 30)
        EditPolish.addEndScreen(&plain)
        if case .text(let element)? = plain.tracks.flatMap(\.clips).first(where: { $0.name == "End Screen Subtitle" })?.content { XCTAssertEqual(element.text, "More videos →") }
        var options = LongFormOptions()
        options.socialHandle = "@xav"
        XCTAssertEqual(options.socialHandle, "@xav")
    }

    func testTempoFromBeats() {
        let beats = stride(from: 0.0, to: 20, by: 0.5).map { $0 }   // 120 BPM
        XCTAssertEqual(BeatSync.bpm(beats: beats) ?? 0, 120, accuracy: 1e-9)
        XCTAssertNil(BeatSync.bpm(beats: [0, 1, 2]))
        XCTAssertEqual(BeatSync.bpm(beats: [0, 0.65, 1.3, 1.95, 2.6, 9]) ?? 0, 92.3, accuracy: 0.1, "one outlier doesn't matter")
    }

    func testColourPrimariesAndCompactTimelineDecode() throws {
        var meta = MediaMetadata(duration: 1)
        meta.colorPrimaries = "ITU_R_2020"
        let back = try JSONDecoder().decode(MediaMetadata.self, from: JSONEncoder().encode(meta))
        XCTAssertEqual(back.colorPrimaries, "ITU_R_2020")
        XCTAssertNil(try JSONDecoder().decode(MediaMetadata.self, from: Data(#"{"duration":5,"width":1,"height":1,"frameRate":30,"hasVideo":true,"hasAudio":false,"audioTrackCount":0,"audioChannels":0,"audioSampleRate":0,"fileSize":1}"#.utf8)).colorPrimaries)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).compactTimeline)
    }
}
