import XCTest
@testable import PulseCore

/// #396: random sequences of edits must never leave overlapping clips, negative source times, pieces shorter
/// than the minimum, or linked video/audio pieces that drift apart. #394: Edit My VOD must stay fast on a
/// stream-length recording.
final class TimelineFuzzTests: XCTestCase {
    let asset = UUID()
    let sourceLength: Seconds = 3600

    func seeded() -> Timeline {
        var t = Timeline(name: "fuzz", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .text, name: "T1"), Track(kind: .audio, name: "A1")])
        var at: Seconds = 0
        for i in 0..<12 {
            let g = UUID()
            let length = Double(10 + (i * 7) % 25)
            let sourceIn = Double(i) * 200
            t.tracks[0].clips.append(TimelineClip(name: "v\(i)", content: .media(assetID: asset), start: at, sourceIn: sourceIn, sourceDuration: length, linkGroup: g, role: .main))
            t.tracks[2].clips.append(TimelineClip(name: "a\(i)", content: .media(assetID: asset), start: at, sourceIn: sourceIn, sourceDuration: length, linkGroup: g, role: .microphone))
            if i % 3 == 0 { t.tracks[1].clips.append(TimelineClip(name: "t\(i)", content: .text(TextElement(text: "x")), start: at + 2, sourceDuration: 1.5)) }
            at += length
        }
        return t
    }

    func check(_ t: Timeline, step: String, sourceLength: Seconds? = nil) {
        let sourceLength = sourceLength ?? self.sourceLength
        for track in t.tracks {
            let clips = track.clips.sorted { $0.start < $1.start }
            for (a, b) in zip(clips, clips.dropFirst()) {
                XCTAssertLessThanOrEqual(a.end, b.start + 0.002, "\(step): “\(a.name)” overlaps “\(b.name)” on \(track.name)")
            }
            for c in clips {
                XCTAssertGreaterThanOrEqual(c.duration, Timeline.minimumClipDuration - 0.002, "\(step): “\(c.name)” too short (\(c.duration))")
                XCTAssertGreaterThanOrEqual(c.sourceIn, -0.002, "\(step): “\(c.name)” reads before the start of the file")
                XCTAssertGreaterThanOrEqual(c.start, -0.002, "\(step): “\(c.name)” starts before 0")
                if c.content.assetID != nil { XCTAssertLessThanOrEqual(c.sourceOut, sourceLength + 0.002, "\(step): “\(c.name)” reads past the file") }
            }
        }
        // Linked video/audio pieces stay in sync (same start, same source) — the editor's core promise.
        let video = t.tracks[0].clips.filter { $0.role != .graphic }
        for v in video {
            guard let g = v.linkGroup, let a = t.tracks[2].clips.first(where: { $0.linkGroup == g }) else { continue }
            XCTAssertEqual(v.start, a.start, accuracy: 0.002, "\(step): linked pieces drifted (“\(v.name)”)")
            XCTAssertEqual(v.sourceIn, a.sourceIn, accuracy: 0.002, "\(step): linked pieces read different source (“\(v.name)”)")
        }
    }

    func testRandomEditSequencesKeepTheTimelineSound() {
        for seed in UInt64(1)...UInt64(40) {
            var rng = SeededGenerator(seed: seed)
            var t = seeded()
            check(t, step: "seed \(seed) start")
            for step in 0..<25 {
                let duration = max(t.duration, 1)
                let at = Double.random(in: 0..<duration, using: &rng)
                let op = Int.random(in: 0..<8, using: &rng)
                let label = "seed \(seed) step \(step) op \(op) at \(String(format: "%.2f", at))"
                switch op {
                case 0: _ = try? t.split(at: at)
                case 1: t.rippleDelete(range: TimeRange(start: at, end: min(duration, at + Double.random(in: 0.2...6, using: &rng))))
                case 2: _ = try? t.freezeFrame(at: at, hold: Double.random(in: 0.5...3, using: &rng))
                case 3:
                    let s = Double.random(in: 0..<(sourceLength - 10), using: &rng)
                    _ = t.removeSourceRanges([TimeRange(start: s, end: s + Double.random(in: 0.3...5, using: &rng))], assetID: asset, reason: .silence, aiGenerated: true)
                case 4: _ = EditQualityCheck.closeGaps(&t)
                case 5:
                    if let clip = t.tracks[0].clips.randomElement(using: &rng), clip.role != .graphic {
                        _ = EditQualityCheck.rippleExtend(&t, clipID: clip.id, head: Double.random(in: 0...0.4, using: &rng), tail: Double.random(in: 0...0.4, using: &rng))
                    }
                case 6:
                    let text = TimelineClip(name: "txt", content: .text(TextElement(text: "hi")), start: at, sourceDuration: 1.2)
                    _ = try? t.insert(text, onTrack: t.tracks[1].id, mode: Bool.random(using: &rng) ? .overwrite : .insert)
                default:
                    _ = EditPolish.removeMicroFragments(&t)
                }
                check(t, step: label)
            }
        }
    }

    func testEditMyVodStaysFastOnATwoHourStream() {
        let duration: Seconds = 7200
        let spikes = stride(from: 150.0, to: duration - 100, by: 170).map { $0 }
        let silences = stride(from: 60.0, to: duration - 50, by: 97).map { TimeRange(start: $0, end: $0 + 4) }
        var words: [TranscriptWord] = []
        var t = 0.5, i = 0
        while t < duration - 1 {
            if !silences.contains(where: { $0.contains(t) }) {
                words.append(TranscriptWord(text: (i + 1) % 8 == 0 ? "okay." : "so", start: t, end: t + 0.32))
                i += 1
            }
            t += 0.4
        }
        for s in spikes { for k in 0..<4 { words.append(TranscriptWord(text: "hahaha", start: s + 1 + Double(k) * 0.5, end: s + 1.3 + Double(k) * 0.5)) } }
        let transcript = Transcript(language: "en", words: words.sorted { $0.start < $1.start }, source: .demo)
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration, audio: Fixtures.audio(duration: duration, spikes: spikes, silences: silences),
                                     transcript: transcript,
                                     webcam: WebcamEstimate(region: NormRect(x: 0.72, y: 0.62, width: 0.25, height: 0.3), face: NormRect(x: 0.8, y: 0.68, width: 0.1, height: 0.15), persistence: 0.9, profile: .gameplayWithFacecam),
                                     profile: .gameplayWithFacecam)
        var options = LongFormOptions()
        options.extras = EditExtras(facecamPunchIns: true, brollClips: true, speakerAware: true, titleCards: true, instantReplays: true)
        options.tighten = true
        let started = Date()
        let result = LongFormEditor.build(asset: Fixtures.mediaAsset(duration: duration), analysis: analysis, options: options)
        let seconds = Date().timeIntervalSince(started)
        print("PERF Edit My VOD on a 2-hour stream: \(String(format: "%.1f", seconds)) s · \(result.report)")
        XCTAssertLessThan(seconds, 90, "a 2-hour stream must edit in well under a couple of minutes even in a debug build")
        XCTAssertGreaterThanOrEqual(result.timeline.duration, 8 * 60, result.report)
        check(result.timeline, step: "2-hour build", sourceLength: duration)
    }
}
