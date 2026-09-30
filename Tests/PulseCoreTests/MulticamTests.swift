import XCTest
@testable import PulseCore

final class MulticamTests: XCTestCase {
    let group = UUID()

    func asset(_ name: String, role: MediaRole, offset: Seconds, duration: Seconds = 120, video: Bool = true, audio: Bool = true) -> MediaAsset {
        MediaAsset(name: name, path: "/tmp/\(name).mov", kind: video ? .video : .audio, role: role,
                   metadata: MediaMetadata(duration: duration, width: video ? 1920 : 0, height: video ? 1080 : 0, frameRate: 30,
                                           hasVideo: video, hasAudio: audio, audioTrackCount: audio ? 1 : 0),
                   syncOffset: offset, syncGroupID: group)
    }

    func testGroupsNeedTwoVideoAnglesAndMapSessionTime() {
        let a = asset("Cam A", role: .camera, offset: 0)
        let b = asset("Cam B", role: .camera, offset: 2.5)
        let mic = asset("Mic", role: .microphone, offset: 1, video: false)
        let loner = MediaAsset(name: "Other", path: "/tmp/o.mov", kind: .video, metadata: MediaMetadata(duration: 10, hasVideo: true))
        let groups = MulticamGroup.groups(in: [a, b, mic, loner])
        XCTAssertEqual(groups.count, 1)
        let g = groups[0]
        XCTAssertEqual(g.videoAngles.count, 2)
        XCTAssertEqual(g.preferredAudioAngle?.assetID, mic.id)
        XCTAssertEqual(g.commonVideoRange, TimeRange(start: 2.5, end: 120))
        XCTAssertEqual(g.angle(b.id)?.sourceTime(atSession: 10), 7.5)
        XCTAssertNil(MulticamGroup.groups(in: [a, mic]).first, "one video angle isn't multicam")
    }

    func testCutAndSwitchKeepSync() throws {
        let a = asset("Cam A", role: .camera, offset: 0)
        let b = asset("Cam B", role: .camera, offset: 2)
        let g = MulticamGroup.groups(in: [a, b])[0]
        var timeline = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 10, end: 40), assetID: a.id)],
                                              group: g, audioAssetID: a.id, canvas: .landscape1080, name: "Podcast")
        XCTAssertEqual(timeline.duration, 30, accuracy: 1e-9)
        XCTAssertEqual(timeline.tracks[0].clips.first?.sourceIn, 10)

        // Live switch at 12 s of the edit (session 22 s) → Cam B from source 20 s.
        let newID = try MulticamEditor.cut(&timeline, at: 12, to: b.id, group: g)
        let clips = timeline.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.count, 2)
        let right = try XCTUnwrap(timeline.clip(id: newID))
        XCTAssertEqual(right.assetID, b.id)
        XCTAssertEqual(right.start, 12, accuracy: 1e-9)
        XCTAssertEqual(right.sourceIn, 20, accuracy: 1e-9)
        XCTAssertEqual(MulticamEditor.sessionTime(of: right, atTimeline: 12, group: g)!, 22, accuracy: 1e-9)
        XCTAssertEqual(timeline.duration, 30, accuracy: 1e-9, "switching never changes length")

        // Switching back merges into one continuous clip again.
        try MulticamEditor.cut(&timeline, at: 12, to: a.id, group: g)
        XCTAssertEqual(timeline.tracks[0].clips.count, 1)
        XCTAssertEqual(timeline.tracks[0].clips[0].sourceDuration, 30, accuracy: 1e-9)
    }

    func testSwitchRefusesAngleThatWasNotRecording() throws {
        let a = asset("Cam A", role: .camera, offset: 0, duration: 100)
        let b = asset("Cam B", role: .camera, offset: 50, duration: 100)
        let g = MulticamGroup.groups(in: [a, b])[0]
        var timeline = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 0, end: 20), assetID: a.id)],
                                              group: g, audioAssetID: nil, canvas: .landscape1080, name: "T")
        let id = timeline.tracks[0].clips[0].id
        XCTAssertThrowsError(try MulticamEditor.switchAngle(&timeline, clipID: id, to: b.id, group: g)) { error in
            XCTAssertEqual(error as? MulticamError, .angleNotAvailable("Cam B"))
        }
        XCTAssertEqual(timeline.tracks[0].clips[0].assetID, a.id)
    }

    func testAutoSwitchFollowsTheLoudestMicWithMinimumShotLength() {
        let a = asset("Host", role: .camera, offset: 0, duration: 60)
        let b = asset("Guest", role: .camera, offset: 0, duration: 60)
        let wide = asset("Wide", role: .gameplay, offset: 0, duration: 60, audio: false)
        let g = MulticamGroup.groups(in: [a, b, wide])[0]
        let hop = 0.1
        // Host talks 0–20 s, guest 20–40 s, both quiet 40–50 s, host again 50–60 s. A 0.5 s guest blip at 10 s.
        var host = [Float](repeating: -60, count: 600)
        var guest = [Float](repeating: -60, count: 600)
        for i in 0..<200 { host[i] = -18 }
        for i in 200..<400 { guest[i] = -18 }
        for i in 500..<600 { host[i] = -18 }
        for i in 100..<105 { guest[i] = -10 }
        let cuts = MulticamEditor.autoSwitch(group: g, levels: [a.id: host, b.id: guest], hop: hop, minimumShot: 2, wideAngle: wide.id)
        XCTAssertFalse(cuts.isEmpty)
        func angle(at t: Seconds) -> UUID? { cuts.first { $0.range.contains(t) }?.assetID }
        XCTAssertEqual(angle(at: 5), a.id)
        XCTAssertEqual(angle(at: 10.2), a.id, "short blips don't cause a cut")
        XCTAssertEqual(angle(at: 30), b.id)
        XCTAssertEqual(angle(at: 45), wide.id, "nobody talking → wide shot")
        XCTAssertEqual(angle(at: 55), a.id)
        XCTAssertTrue(cuts.allSatisfy { $0.range.duration >= 2 - 1e-9 })
        // Contiguous, covering the whole span.
        for (x, y) in zip(cuts, cuts.dropFirst()) { XCTAssertEqual(x.range.end, y.range.start, accuracy: 1e-9) }
        XCTAssertEqual(cuts.first!.range.start, 0, accuracy: 1e-9)
        XCTAssertEqual(cuts.last!.range.end, 60, accuracy: 1e-9)
    }

    func testShortFromScreenRecordingUsesCompanionFacecamAndVoiceInSync() {
        let screen = asset("Screen", role: .gameplay, offset: 0.4, duration: 300)
        let cam = asset("Camera", role: .webcam, offset: 0, duration: 300)
        let candidate = ClipCandidate(assetID: screen.id, range: TimeRange(start: 100, end: 130), payoffTime: 115, targetDuration: 30,
                                      potential: 70, scores: ClipScores(), tags: [.gaming], title: "Clutch", copy: .empty, transcriptSnippet: "")
        var transcript = Fixtures.transcript(duration: 300)
        transcript.words.removeAll { $0.end > 109.5 && $0.start < 114.5 }
        var analysis = MediaAnalysis(assetID: screen.id, duration: 300, audio: Fixtures.audio(duration: 300, silences: [TimeRange(start: 110, end: 114)]),
                                     transcript: transcript, profile: .gameplay)
        analysis.webcam = nil
        var options = ShortBuildOptions.oneClick
        options.punchIns = false
        let timeline = ShortBuilder.build(ShortBuildInput(candidate: candidate, asset: screen, analysis: analysis, companionWebcam: cam, companionVoice: cam),
                                          options: options)
        let facecam = timeline.allClips.filter { $0.assetID == cam.id && $0.role == .webcam }
        let gameplay = timeline.allClips.filter { $0.assetID == screen.id && ($0.role == .gameplay || $0.role == .main) && $0.isVisual }
        let voice = timeline.allClips.filter { $0.assetID == cam.id && $0.role == .microphone }
        XCTAssertFalse(facecam.isEmpty)
        XCTAssertFalse(voice.isEmpty)
        XCTAssertTrue(timeline.layout?.usesWebcam ?? false)
        XCTAssertTrue(facecam.allSatisfy(\.isEnabled))
        // After silence removal every facecam/voice segment still lines up with the gameplay segment at the same time.
        for g in gameplay {
            let mid = (g.start + g.end) / 2
            let session = g.sourceTime(atTimeline: mid) + screen.syncOffset
            for c in (facecam + voice) where c.timelineRange.contains(mid) {
                XCTAssertEqual(c.sourceTime(atTimeline: mid) + cam.syncOffset, session, accuracy: 1e-6)
            }
        }
        XCTAssertLessThan(timeline.duration, 30, "silence removal also cut the linked companion tracks")
    }

    // MARK: Grid layouts

    func testGridSlotsTileTheCanvasWithoutOverlap() {
        for canvas in [CanvasSettings.vertical1080, .landscape1080] {
            for layout in MulticamGridLayout.allCases {
                let slots = layout.slots(count: layout.capacity, canvas: canvas)
                XCTAssertEqual(slots.count, layout.capacity, "\(layout)")
                for s in slots {
                    XCTAssertGreaterThanOrEqual(s.x, -1e-9)
                    XCTAssertGreaterThanOrEqual(s.y, -1e-9)
                    XCTAssertLessThanOrEqual(s.maxX, 1 + 1e-9)
                    XCTAssertLessThanOrEqual(s.maxY, 1 + 1e-9)
                }
                for (i, a) in slots.enumerated() {
                    for b in slots[(i + 1)...] {
                        let overlapW = min(a.maxX, b.maxX) - max(a.x, b.x)
                        let overlapH = min(a.maxY, b.maxY) - max(a.y, b.y)
                        XCTAssertFalse(overlapW > 1e-6 && overlapH > 1e-6, "\(layout) slots overlap")
                    }
                }
            }
        }
        let vertical = MulticamGridLayout.twoUp.slots(count: 2, canvas: .vertical1080)
        XCTAssertLessThan(vertical[0].maxY, vertical[1].y + 1e-9, "2-up stacks on vertical canvases")
        let landscape = MulticamGridLayout.twoUp.slots(count: 2, canvas: .landscape1080)
        XCTAssertLessThan(landscape[0].maxX, landscape[1].x + 1e-9, "2-up is side by side on landscape")
        XCTAssertEqual(MulticamGridLayout.automatic(for: 4), .quad)
    }

    func testApplyGridAddsSyncedLinkedCellsAndCutEndsIt() throws {
        let a = asset("Host", role: .camera, offset: 0)
        let b = asset("Guest", role: .camera, offset: 3)
        let g = MulticamGroup.groups(in: [a, b])[0]
        var timeline = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 10, end: 30), assetID: a.id)],
                                              group: g, audioAssetID: a.id, canvas: .vertical1080, name: "Podcast")
        let shot = timeline.tracks[0].clips[0].id
        try MulticamEditor.applyGrid(&timeline, clipID: shot, angles: [a.id, b.id], layout: .twoUp, group: g)
        let partners = MulticamEditor.gridPartners(of: shot, in: timeline)
        XCTAssertEqual(partners.count, 1)
        let main = try XCTUnwrap(timeline.clip(id: shot)), cell = partners[0]
        XCTAssertEqual(cell.assetID, b.id)
        XCTAssertEqual(cell.start, main.start, accuracy: 1e-9)
        XCTAssertEqual(cell.duration, main.duration, accuracy: 1e-9)
        XCTAssertEqual(cell.sourceIn + b.syncOffset, main.sourceIn + a.syncOffset, accuracy: 1e-9, "cells show the same moment")
        XCTAssertEqual(main.linkGroup, cell.linkGroup)
        XCTAssertLessThan(main.transform.positionY.value, cell.transform.positionY.value, "host on top, guest below")
        XCTAssertEqual(MulticamEditor.gridLayout(of: shot, in: timeline).count, 2)

        // Cutting to the guest 8 s in ends the grid there; the first 8 s keep the grid.
        let right = try MulticamEditor.cut(&timeline, at: 8, to: b.id, group: g)
        XCTAssertTrue(MulticamEditor.gridPartners(of: right, in: timeline).isEmpty)
        XCTAssertEqual(timeline.clip(id: right)?.assetID, b.id)
        XCTAssertEqual(timeline.clip(id: right)?.transform.fit, .fill)
        XCTAssertEqual(MulticamEditor.gridPartners(of: shot, in: timeline).count, 1)
        XCTAssertEqual(MulticamEditor.gridPartners(of: shot, in: timeline).first?.end ?? 0, 8, accuracy: 1e-9)
        XCTAssertEqual(timeline.duration, 20, accuracy: 1e-9)

        // Removing the grid leaves one full-frame angle.
        try MulticamEditor.removeGrid(&timeline, clipID: shot, group: g)
        XCTAssertTrue(MulticamEditor.gridPartners(of: shot, in: timeline).isEmpty)
        XCTAssertNil(timeline.clip(id: shot)?.linkGroup)
    }

    func testGridRefusesAngleMissingDuringTheShot() {
        let a = asset("Cam A", role: .camera, offset: 0, duration: 100)
        let b = asset("Cam B", role: .camera, offset: 50, duration: 100)
        let g = MulticamGroup.groups(in: [a, b])[0]
        var timeline = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 0, end: 20), assetID: a.id)],
                                              group: g, audioAssetID: nil, canvas: .landscape1080, name: "T")
        let shot = timeline.tracks[0].clips[0].id
        XCTAssertThrowsError(try MulticamEditor.applyGrid(&timeline, clipID: shot, angles: [a.id, b.id], layout: .twoUp, group: g))
        XCTAssertTrue(MulticamEditor.gridPartners(of: shot, in: timeline).isEmpty)
    }

    func testAutoSwitchShowsBothSpeakersDuringCrosstalk() {
        let a = asset("Host", role: .camera, offset: 0, duration: 30)
        let b = asset("Guest", role: .camera, offset: 0, duration: 30)
        let g = MulticamGroup.groups(in: [a, b])[0]
        // Host alone 0–10 s, both loud 10–20 s, guest alone 20–30 s.
        var host = [Float](repeating: -60, count: 300), guest = [Float](repeating: -60, count: 300)
        for i in 0..<200 { host[i] = -18 }
        for i in 100..<300 { guest[i] = -18 }
        let cuts = MulticamEditor.autoSwitch(group: g, levels: [a.id: host, b.id: guest], hop: 0.1, gridOnCrosstalk: true)
        let middle = cuts.first { $0.range.contains(15) }
        XCTAssertEqual(Set(middle?.angles ?? []), [a.id, b.id])
        XCTAssertEqual(cuts.first { $0.range.contains(5) }?.angles, [a.id])
        XCTAssertEqual(cuts.first { $0.range.contains(25) }?.angles, [b.id])
        let timeline = MulticamEditor.timeline(cuts: cuts, group: g, audioAssetID: nil, canvas: .vertical1080, name: "Auto")
        XCTAssertTrue(timeline.tracks.contains { $0.name == "Grid 2" && !$0.clips.isEmpty }, "crosstalk became a 2-up grid shot")
    }
}
