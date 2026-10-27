import XCTest
@testable import PulseCore

final class Batch36Tests: XCTestCase {
    // MARK: #498 — the editor assistant

    func testAssistantReadsEveryKindOfRequest() {
        XCTAssertEqual(EditorAssistant.parse("cut the first 10 seconds"), .trimStart(10))
        XCTAssertEqual(EditorAssistant.parse("Cut the intro"), .trimStart(5))
        XCTAssertEqual(EditorAssistant.parse("drop the last 1:30"), .trimEnd(90))
        XCTAssertEqual(EditorAssistant.parse("trim the ending"), .trimEnd(5))
        XCTAssertEqual(EditorAssistant.parse("make the hook punchier"), .punchierHook)
        XCTAssertEqual(EditorAssistant.parse("open with the best moment"), .punchierHook)
        XCTAssertEqual(EditorAssistant.parse("tighten the pauses"), .tightenPauses(minimum: 0.3))
        XCTAssertEqual(EditorAssistant.parse("really tight jump cuts"), .tightenPauses(minimum: 0.15))
        XCTAssertEqual(EditorAssistant.parse("make it 20 % shorter"), .shorter(by: 0.2))
        XCTAssertEqual(EditorAssistant.parse("make it a lot shorter"), .shorter(by: 0.4))
        XCTAssertEqual(EditorAssistant.parse("it's too long"), .shorter(by: 0.25))
        XCTAssertEqual(EditorAssistant.parse("please add captions"), .captions(on: true))
        XCTAssertEqual(EditorAssistant.parse("turn the captions off"), .captions(on: false))
        XCTAssertEqual(EditorAssistant.parse("captions like TikTok"), .captionStyle("tiktok"))
        XCTAssertEqual(EditorAssistant.parse("add music"), .music(on: true))
        XCTAssertEqual(EditorAssistant.parse("mute the music"), .music(on: false))
        XCTAssertEqual(EditorAssistant.parse("turn the music down"), .musicLevel(deltaDB: -3))
        XCTAssertEqual(EditorAssistant.parse("music louder"), .musicLevel(deltaDB: 3))
        XCTAssertEqual(EditorAssistant.parse("fewer zooms"), .zooms(more: false))
        XCTAssertEqual(EditorAssistant.parse("more punch-ins"), .zooms(more: true))
        XCTAssertEqual(EditorAssistant.parse("remove the zooms"), .removeZooms)
        XCTAssertEqual(EditorAssistant.parse("make it more entertaining"), .moreEntertaining)
        XCTAssertEqual(EditorAssistant.parse("add a progress bar"), .progressBar(on: true))
        XCTAssertEqual(EditorAssistant.parse("remove the progress bar"), .progressBar(on: false))
        XCTAssertEqual(EditorAssistant.parse("add a marker called Big Play"), .addMarker("Big Play"))
        XCTAssertEqual(EditorAssistant.parse("speed up 1.5x"), .speed(1.5))
        XCTAssertEqual(EditorAssistant.parse("slow it down"), .speed(0.75))
        XCTAssertEqual(EditorAssistant.parse("fill the gaps with room tone"), .roomTone)
        XCTAssertEqual(EditorAssistant.parse("close the gaps"), .closeGaps)
        XCTAssertEqual(EditorAssistant.parse("remove the AI edits"), .removeAI)
        XCTAssertEqual(EditorAssistant.parse("undo"), .undo)
        XCTAssertEqual(EditorAssistant.parse("Redo that"), .redo)
        XCTAssertEqual(EditorAssistant.parse("paint it blue"), .unknown("paint it blue"))
        XCTAssertEqual(EditorAssistant.parse("   "), .unknown("   "))
        XCTAssertFalse(EditorAssistant.describe(.trimStart(10)).isEmpty)
        XCTAssertEqual(EditorAssistant.describe(.shorter(by: 0.2)), "Make it about 20 % shorter")
        XCTAssertFalse(EditorAssistant.examples.isEmpty)
        for example in EditorAssistant.examples {
            if case .unknown = EditorAssistant.parse(example) { XCTFail("example not understood: \(example)") }
        }
    }

    // MARK: #183 — render load along the ruler

    func testRenderLoadProfilesHeavyAndLightSeconds() {
        let asset = UUID()
        var v1 = Track(kind: .video, name: "V1")
        v1.clips = [TimelineClip(name: "Plain", content: .media(assetID: asset), start: 0, sourceDuration: 10)]
        var v2 = Track(kind: .video, name: "V2")
        var keyed = TimelineClip(name: "Keyed", content: .media(assetID: asset), start: 4, sourceDuration: 3)
        keyed.style.chromaKey = ChromaKey()
        keyed.style.chromaKey?.enabled = true
        keyed.effects = [EffectInstance(kind: .gaussianBlur), EffectInstance(kind: .glow)]
        v2.clips = [keyed]
        var hidden = Track(kind: .video, name: "V3", isHidden: true)
        hidden.clips = [keyed]
        let timeline = Timeline(name: "T", canvas: .vertical1080, tracks: [v1, v2, hidden])
        let spans = RenderLoad.profile(timeline)
        XCTAssertEqual(spans.count, 10)
        XCTAssertEqual(spans[0].cost, 1, accuracy: 1e-9, "one plain layer")
        XCTAssertFalse(spans[0].isHeavy)
        XCTAssertTrue(spans[5].isHeavy, "plain + keyed layer with blur and glow")
        XCTAssertEqual(spans[5].cost, 1 + 1 + 2 + 2.5 + 2.5, accuracy: 1e-9, "hidden tracks don't count")
        XCTAssertFalse(spans[8].isHeavy)
        let merged = RenderLoad.merged(spans)
        XCTAssertEqual(merged.map(\.isHeavy), [false, true, false])
        XCTAssertEqual(merged[1].range, TimeRange(start: 4, end: 7))
        XCTAssertTrue(RenderLoad.profile(Timeline(name: "Empty", canvas: .vertical1080, tracks: [])).isEmpty)
        XCTAssertEqual(RenderLoad.cost(of: TimelineClip(name: "Title", content: .text(TextElement(text: "Hi")), start: 0, sourceDuration: 2)), 0.6, accuracy: 1e-9)
    }

    // MARK: #328 — multicam picture-in-picture

    func testPictureInPictureKeepsTheGameFullAndTheCamSmall() {
        let sync = UUID()
        func asset(_ name: String, role: MediaRole, audio: Bool) -> MediaAsset {
            MediaAsset(name: name, path: "/tmp/\(name).mp4", kind: .video, role: role,
                       metadata: MediaMetadata(duration: 60, width: 1920, height: 1080, frameRate: 30, hasVideo: true, hasAudio: audio, audioTrackCount: audio ? 1 : 0),
                       syncOffset: 0, syncGroupID: sync)
        }
        let game = asset("Game", role: .gameplay, audio: false)
        let host = asset("Host", role: .camera, audio: true)
        let guest = asset("Guest", role: .camera, audio: true)
        let group = MulticamGroup.groups(in: [game, host, guest])[0]
        let cuts = [MulticamCut(range: TimeRange(start: 0, end: 20), assetID: host.id),
                    MulticamCut(range: TimeRange(start: 20, end: 40), assetID: guest.id),
                    MulticamCut(range: TimeRange(start: 40, end: 60), assetID: game.id)]
        let timeline = MulticamEditor.pipTimeline(cuts: cuts, group: group, audioAssetID: host.id, canvas: .landscape1080, name: "PiP")
        let base = timeline.tracks[0].clips
        XCTAssertEqual(base.count, 1)
        XCTAssertEqual(base[0].assetID, game.id)
        XCTAssertEqual(base[0].duration, 60, accuracy: 1e-9, "the game runs underneath the whole way")
        let cams = timeline.tracks[1].clips
        XCTAssertEqual(cams.map(\.assetID), [host.id, guest.id], "a cut to the wide angle shows no cam")
        XCTAssertEqual(cams[0].transform.scale.value, 0.28, accuracy: 1e-9)
        XCTAssertGreaterThan(cams[0].transform.positionX.value, 0.7, "bottom right")
        XCTAssertGreaterThan(cams[0].transform.positionY.value, 0.7)
        XCTAssertEqual(cams[0].style.mask, .roundedRectangle)
        XCTAssertEqual(cams[1].start, 20, accuracy: 1e-9)
        XCTAssertEqual(timeline.audioTracks.flatMap(\.clips).first?.assetID, host.id)
        let topLeft = NormRect.Corner.topLeft.center(inset: 0.04, size: 0.28, aspect: 16.0 / 9.0)
        XCTAssertEqual(topLeft.x, 0.18, accuracy: 1e-9)
        XCTAssertEqual(topLeft.y, 0.04 + 0.28 / 2, accuracy: 1e-9, "a 16:9 cam on a 16:9 canvas is as tall as it is wide, in fractions")
    }
}
