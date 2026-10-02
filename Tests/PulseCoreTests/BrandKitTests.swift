import XCTest
@testable import PulseCore

final class BrandKitTests: XCTestCase {
    func asset(_ name: String, kind: MediaKind, duration: Seconds = 0, w: Int = 400, h: Int = 200, audio: Bool = false) -> MediaAsset {
        MediaAsset(name: name, path: "/tmp/\(name)", kind: kind, role: .graphic,
                   metadata: MediaMetadata(duration: duration, width: w, height: h, frameRate: 30, hasVideo: kind != .audio, hasAudio: audio, audioTrackCount: audio ? 1 : 0))
    }

    func kit() -> BrandKit {
        var k = BrandKit()
        k.enabled = true
        k.logoPath = "/tmp/logo.png"
        k.logoCorner = .topRight
        k.logoSize = 0.2
        k.introPath = "/tmp/intro.mov"
        k.outroPath = "/tmp/outro.mov"
        k.captionPresetName = "Bold"
        k.highlightColor = RGBAColor(hex: "#00FF88")!
        return k
    }

    func testShortsGetALogoInTheCornerButNoIntro() {
        var t = Fixtures.simpleTimeline(clipDuration: 30)
        t.captions = CaptionTrack(sourceAssetID: Fixtures.assetID, words: [CaptionWord(text: "hi", start: 101, end: 101.5)], style: .tiktok)
        let assets = BrandKitAssets(logo: asset("logo.png", kind: .image), intro: asset("intro.mov", kind: .video, duration: 3, audio: true),
                                    outro: asset("outro.mov", kind: .video, duration: 4))
        BrandKitApplier.apply(kit(), assets: assets, to: &t, longForm: false)
        XCTAssertEqual(t.duration, 30, accuracy: 1e-9, "no intro/outro on a short")
        let brand = t.tracks.first { $0.name == "V Brand" }
        let logo = brand?.clips.first
        XCTAssertNotNil(logo)
        XCTAssertEqual(logo?.duration ?? 0, 30, accuracy: 1e-9)
        XCTAssertGreaterThan(logo?.transform.positionX.value(at: 0) ?? 0, 0.75, "right side")
        XCTAssertLessThan(logo?.transform.positionY.value(at: 0) ?? 1, 0.2, "near the top, under the platform bar")
        // It's the top-most video layer.
        let videoTracks = t.tracks.filter { $0.kind == .video }
        XCTAssertEqual(videoTracks.last?.name, "V Brand")
        XCTAssertEqual(t.captions?.style.presetName, "Bold")
        XCTAssertEqual(t.captions?.style.highlightColor, RGBAColor(hex: "#00FF88")!)
        XCTAssertEqual(t.captions?.style.positionY ?? 0, CaptionStyle.tiktok.positionY, accuracy: 1e-9, "keeps the caption position")
    }

    func testYouTubeEditsGetIntroAndOutroAndReapplyingDoesNotStack() {
        var t = Fixtures.simpleTimeline(clipDuration: 300)
        t.markers = [Marker(time: 100, name: "Chapter")]
        let assets = BrandKitAssets(logo: asset("logo.png", kind: .image), intro: asset("intro.mov", kind: .video, duration: 3, audio: true),
                                    outro: asset("outro.mov", kind: .video, duration: 4))
        BrandKitApplier.apply(kit(), assets: assets, to: &t, longForm: true)
        XCTAssertEqual(t.duration, 307, accuracy: 1e-9)
        XCTAssertEqual(t.tracks[0].clips.first?.name, "Intro")
        XCTAssertEqual(t.tracks[0].clips.last?.name, "Outro")
        XCTAssertEqual(t.tracks[0].clips[1].start, 3, accuracy: 1e-9, "the stream starts after the intro")
        XCTAssertEqual(t.markers[0].time, 103, accuracy: 1e-9)
        XCTAssertTrue(t.tracks[3].clips.contains { $0.name == "Intro" }, "intro sound comes along")
        XCTAssertEqual(t.tracks.first { $0.name == "V Brand" }?.clips.first?.duration ?? 0, 307, accuracy: 1e-9)

        BrandKitApplier.apply(kit(), assets: assets, to: &t, longForm: true)
        XCTAssertEqual(t.duration, 307, accuracy: 1e-9, "re-applying replaces, never stacks")
        XCTAssertEqual(t.tracks.filter { $0.name == "V Brand" }.count, 1)
        XCTAssertEqual(t.allClips.filter { $0.name == "Intro" }.count, 2, "one video + one audio")
        XCTAssertEqual(t.markers[0].time, 103, accuracy: 1e-9)
    }

    func testOldSettingsFilesLoadWithAnEmptyKit() throws {
        let json = Data(#"{"sidebarCollapsed": true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(settings.brandKit.enabled)
        XCTAssertFalse(settings.brandKit.hasAnything)
    }
}
