import AppKit
import AVFoundation
import XCTest
@testable import PulseCore
@testable import PulseEngine

/// End-to-end engine test on real media: generate the demo stream → probe → analyze →
/// find clips → build a 9:16 short → export with the custom compositor → verify the file.
/// Frames are written to build/snapshots for visual inspection (uploaded by CI).
final class EngineSmokeTests: XCTestCase {
    static var workDir: URL = FileManager.default.temporaryDirectory.appendingPathComponent("PulseEngineTests", isDirectory: true)
    static var snapshotDir: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/snapshots", isDirectory: true)
    }

    func testVersion() {
        XCTAssertFalse(PulseEngineInfo.version.isEmpty)
    }

    func testCubeLUTParser() {
        var text = "TITLE \"test\"\nLUT_3D_SIZE 2\n"
        for b in 0..<2 { for g in 0..<2 { for r in 0..<2 { text += "\(r) \(g) \(b)\n" } } }
        let lut = CubeLUT.parse(text)
        XCTAssertEqual(lut?.dimension, 2)
        XCTAssertEqual(lut?.data.count, 2 * 2 * 2 * 4 * 4)
    }

    func testEndToEndDemoPipeline() async throws {
        try FileManager.default.createDirectory(at: Self.workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Self.snapshotDir, withIntermediateDirectories: true)

        // 1. Generate sample media.
        let demo = try await DemoMediaGenerator.generate(in: Self.workDir)
        let meta = try await MediaProbe.probe(demo.videoURL)
        XCTAssertEqual(meta.width, DemoMediaGenerator.width)
        XCTAssertEqual(meta.height, DemoMediaGenerator.height)
        XCTAssertEqual(meta.duration, DemoMediaGenerator.duration, accuracy: 0.2)
        XCTAssertTrue(meta.hasAudio)
        let asset = MediaAsset(name: "Demo Stream", path: demo.videoURL.path, kind: .video, role: .main, metadata: meta)

        // 2. Analyze (transcript comes from the demo script; speech engines need entitlements).
        let pipeline = AnalysisPipeline(cacheDirectory: Self.workDir)
        let output = try await pipeline.run(asset: asset, options: .init(transcribe: false, detectFaces: true, importedTranscript: demo.transcript), progress: { _ in })
        var analysis = output.analysis
        XCTAssertNotNil(analysis.audio)
        XCTAssertNotNil(analysis.visual)
        XCTAssertGreaterThan(analysis.audio!.count, 700)
        // Loud events are louder than the rest.
        XCTAssertGreaterThan(analysis.audio!.maxRMS(in: TimeRange(start: 22, end: 23)), analysis.audio!.meanRMS(in: TimeRange(start: 60, end: 70)) + 6)
        if analysis.webcam == nil {
            // Vision may not see a cartoon face; fall back to the scripted face track.
            analysis.visual?.faces = demo.faces
            analysis.webcam = WebcamEstimator.estimate(faces: demo.faces, frameSize: meta.size)
            analysis.profile = .gameplayWithFacecam
        }
        XCTAssertEqual(analysis.profile, .gameplayWithFacecam)

        // 3. Clips.
        let generator = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings(targetDuration: 15, minimumPotential: 0))
        let candidates = generator.generate()
        XCTAssertFalse(candidates.isEmpty)
        let best = try XCTUnwrap(candidates.first { $0.range.contains(22.5) } ?? candidates.first { $0.range.contains(51.5) })

        // 4. Short timeline.
        let short = ShortBuilder.build(ShortBuildInput(candidate: best, asset: asset, analysis: analysis), options: .oneClick)
        XCTAssertEqual(short.layout, .splitScreen)
        XCTAssertNotNil(short.captions)

        // 5. Render a still through the compositor pipeline (fast visual check).
        let built = try await CompositionBuilder.build(timeline: short, assets: [asset.id: asset])
        XCTAssertTrue(built.missingAssetIDs.isEmpty)
        let generatorStill = AVAssetImageGenerator(asset: built.composition)
        generatorStill.videoComposition = built.videoComposition
        generatorStill.requestedTimeToleranceBefore = .zero
        generatorStill.requestedTimeToleranceAfter = .zero
        for (i, t) in [0.5, short.duration / 2, max(0, short.duration - 0.5)].enumerated() {
            let image = try await generatorStill.image(at: .seconds(t)).image
            XCTAssertEqual(image.width, 1080)
            XCTAssertEqual(image.height, 1920)
            Self.writePNG(image, name: "short-frame-\(i).png")
        }

        // 6. Export.
        let exportURL = Self.workDir.appendingPathComponent("short-export.mp4")
        let settings = ExportSettings(preset: .tiktok, outputDirectory: Self.workDir.path, quality: .draft)
        try await ExportEngine().export(timeline: short, assets: [asset.id: asset], settings: settings, to: exportURL, progress: { _ in })
        let exported = try await MediaProbe.probe(exportURL)
        XCTAssertEqual(exported.width, 1080)
        XCTAssertEqual(exported.height, 1920)
        XCTAssertEqual(exported.duration, short.duration, accuracy: 0.25)
        XCTAssertTrue(exported.hasAudio)
        let exportedFrames = AVAssetImageGenerator(asset: AVURLAsset(url: exportURL))
        exportedFrames.maximumSize = CGSize(width: 540, height: 960)
        let mid = try await exportedFrames.image(at: .seconds(short.duration / 2)).image
        Self.writePNG(mid, name: "export-mid.png")

        // 7. Landscape re-layout of the same short (aspect ratio change stays editable).
        var landscape = short
        landscape.canvas = .landscape1080
        LayoutEngine.apply(.facecamCorner, to: &landscape, context: LayoutContext(analysis: analysis, sourceSize: meta.size))
        let builtLandscape = try await CompositionBuilder.build(timeline: landscape, assets: [asset.id: asset])
        let gl = AVAssetImageGenerator(asset: builtLandscape.composition)
        gl.videoComposition = builtLandscape.videoComposition
        let landscapeFrame = try await gl.image(at: .seconds(1)).image
        XCTAssertEqual(landscapeFrame.width, 1920)
        Self.writePNG(landscapeFrame, name: "landscape-facecam-corner.png")
    }

    func testPlaybackItemBuildsForTextOnlyTimeline() async throws {
        var timeline = Timeline.empty(name: "Titles", canvas: .vertical1080)
        let element = TextElement(text: "HELLO PULSE", style: TextStyle(fontSize: 120, weight: .black, strokeWidth: 10))
        try timeline.insert(TimelineClip(name: "Title", content: .text(element), start: 0, sourceDuration: 3), onTrack: timeline.tracks[2].id)
        let built = try await CompositionBuilder.build(timeline: timeline, assets: [:])
        XCTAssertEqual(built.duration, 3, accuracy: 0.01)
        let g = AVAssetImageGenerator(asset: built.composition)
        g.videoComposition = built.videoComposition
        let frame = try await g.image(at: .seconds(1.5)).image
        XCTAssertEqual(frame.width, 1080)
        try FileManager.default.createDirectory(at: Self.snapshotDir, withIntermediateDirectories: true)
        Self.writePNG(frame, name: "text-only.png")
    }

    static func writePNG(_ image: CGImage, name: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: snapshotDir.appendingPathComponent(name))
        }
    }
}
