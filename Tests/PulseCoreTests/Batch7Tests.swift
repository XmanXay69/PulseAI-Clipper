import XCTest
@testable import PulseCore

/// Roadmap batch 7: timeline diff (#472), tips (#450), thumbnail text (#362), target file size (#344),
/// music level (#296), settings fields.
final class Batch7Tests: XCTestCase {
    func testTimelineDiffNamesWhatChanged() {
        let before = Fixtures.simpleTimeline(clipDuration: 30)
        var after = before
        after.tracks[0].clips[0].sourceDuration = 20
        after.tracks[3].clips[0].sourceDuration = 20
        after.tracks[0].clips[0].color.saturation = 0.3
        after.tracks[1].clips.append(TimelineClip(name: "Title", content: .text(TextElement(text: "HI")), start: 1, sourceDuration: 2))
        after.markers.append(Marker(time: 3, name: "M", color: .blue))
        let lines = TimelineDiff.summarize(before: before, after: after)
        XCTAssertTrue(lines.contains { $0.hasPrefix("Length 00:30 → 00:20") && $0.contains("−10.0 s") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("1 clip added: Title") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("2 clips trimmed") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("1 clip with a different look") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("Markers 0 → 1") }, "\(lines)")
        XCTAssertEqual(TimelineDiff.summarize(before: before, after: before), ["No differences"])
    }

    func testTipsRotateDaily() {
        XCTAssertGreaterThanOrEqual(HomeTips.all.count, 20)
        XCTAssertEqual(Set(HomeTips.all).count, HomeTips.all.count)
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(HomeTips.tip(for: today), HomeTips.tip(for: today.addingTimeInterval(3600)))
        XCTAssertNotEqual(HomeTips.tip(for: today), HomeTips.tip(for: today.addingTimeInterval(86_400)))
    }

    func testThumbnailTextSuggestions() {
        let ideas = ThumbnailHeadline.textSuggestions(from: ["NAH THIS CANNOT BE REAL 😭", "I CAN'T BREATHE 😭", "the worst decision of my life", "NAH THIS CANNOT BE REAL"])
        XCTAssertEqual(ideas.count, 3, "\(ideas)")
        XCTAssertEqual(ideas[0], "NAH CANNOT REAL")
        XCTAssertTrue(ideas.allSatisfy { !$0.contains("😭") && $0.split(separator: " ").count <= 4 })
        XCTAssertTrue(ideas.contains("WORST DECISION LIFE"))
        XCTAssertTrue(ThumbnailHeadline.textSuggestions(from: []).isEmpty)
    }

    func testTargetFileSizeLowersTheBitrate() throws {
        var settings = ExportSettings(preset: .youtube, outputDirectory: "/tmp", quality: .standard)   // 16 Mbps
        XCTAssertEqual(settings.videoBitrate(for: 60), 16_000_000)
        settings.targetFileMB = 50   // 50 MB over 60 s ≈ 6.5 Mbps minus audio
        let capped = settings.videoBitrate(for: 60)
        XCTAssertLessThan(capped, 7_000_000)
        XCTAssertGreaterThan(capped, 6_000_000)
        XCTAssertEqual(Double(capped + settings.audioBitrate) * 60 / 8, 50_000_000, accuracy: 1_500_000)
        settings.targetFileMB = 1
        XCTAssertEqual(settings.videoBitrate(for: 3600), 250_000, "never below the floor")
        XCTAssertEqual(settings.videoBitrate(for: 0), 16_000_000)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "targetFileMB")
        json.removeValue(forKey: "exportThumbnail")
        let decoded = try JSONDecoder().decode(ExportSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.targetFileMB)
        XCTAssertFalse(decoded.exportThumbnail)
    }

    func testMusicLevelScalesTheBeds() {
        let duration: Seconds = 3000
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: Array(stride(from: 150.0, to: 2900, by: 230))),
                                     transcript: Fixtures.transcript(duration: duration), profile: .gameplay)
        var result = LongFormEditor.build(asset: Fixtures.mediaAsset(duration: duration), analysis: analysis)
        let beds = result.musicChapters.map { range in
            MediaAsset(name: "Bed", path: "/tmp/bed.m4a", kind: .audio, role: .music,
                       metadata: MediaMetadata(duration: range.duration, hasVideo: false, hasAudio: true, audioTrackCount: 1))
        }
        var quiet = result.timeline
        LongFormEditor.addMusic(beds, chapters: result.musicChapters, to: &quiet)
        LongFormEditor.addMusic(beds, chapters: result.musicChapters, to: &result.timeline, level: LongFormEditor.musicLevel * 2)
        let quietLevel = quiet.allClips.filter { $0.role == .music }.map { $0.audio.volume.value(at: 1) }.max() ?? 0
        let loudLevel = result.timeline.allClips.filter { $0.role == .music }.map { $0.audio.volume.value(at: 1) }.max() ?? 0
        XCTAssertGreaterThan(quietLevel, 0)
        XCTAssertEqual(loudLevel, quietLevel * 2, accuracy: 0.01)
        XCTAssertLessThanOrEqual(loudLevel, 1)
        XCTAssertEqual(LongFormOptions().musicLevel, 1)
    }

    func testGradeBypassKeepsValuesButRendersNothing() throws {
        var color = ColorAdjustments()
        XCTAssertTrue(color.isIdentity)
        color.saturation = 0.4
        XCTAssertFalse(color.isIdentity)
        XCTAssertTrue(color.hasAdjustments)
        color.bypass = true
        XCTAssertTrue(color.isIdentity, "bypassed")
        XCTAssertTrue(color.hasAdjustments, "values kept")
        XCTAssertEqual(color.saturation, 0.4)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(color)) as! [String: Any]
        json.removeValue(forKey: "bypass")
        let decoded = try JSONDecoder().decode(ColorAdjustments.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.bypass)
        XCTAssertEqual(decoded.saturation, 0.4)
        XCTAssertEqual(try JSONDecoder().decode(ColorAdjustments.self, from: Data("{}".utf8)), ColorAdjustments())
    }

    func testNewSettingsFieldsDecodeWithDefaults() throws {
        let decoded = try JSONDecoder().decode(AISettings.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.favoriteTrackIDs.isEmpty)
        XCTAssertTrue(decoded.blockedTrackIDs.isEmpty)
        XCTAssertEqual(decoded.musicFolder, "")
        XCTAssertEqual(decoded.analysisThreads, 0)
        var settings = AISettings()
        settings.favoriteTrackIDs = ["abc"]
        settings.analysisThreads = 4
        let round = try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round.favoriteTrackIDs, ["abc"])
        XCTAssertEqual(round.analysisThreads, 4)
    }
}
