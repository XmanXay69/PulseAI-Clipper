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

    /// Audio "Enhance": renders a quiet, noisy mono recording through the voice preset and checks
    /// the cached file is sample-accurate, stereo when panned, and loudness-normalized.
    func testAudioEnhanceRender() async throws {
        let dir = Self.workDir.appendingPathComponent("enhance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rate = 48_000.0
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let source = dir.appendingPathComponent("voice.caf")
        let frames = Int(rate * 4)
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            var generator = SeededGenerator(seed: 3)
            for i in 0..<frames {
                let t = Double(i) / rate
                let voice = (t > 1 && t < 3) ? 0.05 * sin(2 * Double.pi * 220 * t) : 0
                buffer.floatChannelData![0][i] = Float(voice) + Float.random(in: -0.002...0.002, using: &generator)
            }
            try file.write(from: buffer)
        }
        var settings = AudioSettings()
        settings.applyVoicePreset()
        settings.pan = -0.3
        let range = TimeRange(start: 0.5, end: 3.5)
        let output = try await AudioEnhancer.shared.render(sourceURL: source, range: range, settings: settings, cacheDirectory: dir)
        let again = try await AudioEnhancer.shared.render(sourceURL: source, range: range, settings: settings, cacheDirectory: dir)
        XCTAssertEqual(output, again, "second render should hit the cache")

        let rendered = try AVAudioFile(forReading: output)
        XCTAssertEqual(rendered.processingFormat.channelCount, 2)
        XCTAssertEqual(Double(rendered.length), range.duration * rate, accuracy: 64)
        let buffer = AVAudioPCMBuffer(pcmFormat: rendered.processingFormat, frameCapacity: AVAudioFrameCount(rendered.length))!
        try rendered.read(into: buffer)
        let channels = (0..<2).map { c in Array(UnsafeBufferPointer(start: buffer.floatChannelData![c], count: Int(buffer.frameLength))) }
        let lufs = LoudnessMeter.integratedLUFS(channels, sampleRate: rate)
        XCTAssertEqual(lufs, AudioEnhanceChain.targetLUFS, accuracy: 2.5)
        XCTAssertLessThanOrEqual(LoudnessMeter.samplePeak(channels), 0.9)

        // A different setting produces a different cache entry.
        settings.noiseReduction = 0.8
        let other = try await AudioEnhancer.shared.render(sourceURL: source, range: range, settings: settings, cacheDirectory: dir)
        XCTAssertNotEqual(other, output)
    }

    /// Real speech-to-text: macOS `say` speaks a sentence, whisper.cpp transcribes it with word timings.
    /// Runs when CI (or you) installs whisper.cpp and sets PULSE_WHISPER_MODEL to a ggml model path.
    func testWhisperTranscriptionOfSynthesizedSpeech() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["PULSE_WHISPER_MODEL"], FileManager.default.fileExists(atPath: modelPath),
              let executable = WhisperCppTranscriber.locateExecutable() else {
            throw XCTSkip("whisper.cpp or PULSE_WHISPER_MODEL not available")
        }
        let dir = Self.workDir.appendingPathComponent("whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wav = dir.appendingPathComponent("speech.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", wav.path, "--file-format=WAVE", "--data-format=LEI16@16000",
                         "No way, that was the craziest clutch I have ever seen. Let's go!"]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)

        let transcriber = WhisperCppTranscriber(executable: executable, model: URL(fileURLWithPath: modelPath))
        let transcript = try await transcriber.transcribe(audioURL: wav, language: "en-US", progress: { _ in })
        let text = transcript.fullText.lowercased()
        print("whisper transcript:", transcript.fullText)
        XCTAssertTrue(text.contains("clutch") || text.contains("craziest"), "unexpected transcript: \(transcript.fullText)")
        XCTAssertGreaterThan(transcript.words.count, 6)
        for (a, b) in zip(transcript.words, transcript.words.dropFirst()) {
            XCTAssertLessThanOrEqual(a.start, b.start + 0.01, "word timings must be ordered")
        }
        XCTAssertLessThan(transcript.words.last?.end ?? 99, 10)
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
        // One-click shorts normalize dialogue, so the audio must come from the enhance renders.
        var enhancedSegments = 0
        for track in built.composition.tracks where track.mediaType == .audio {
            for segment in track.segments where segment.sourceURL?.lastPathComponent.hasPrefix("enh-") == true {
                enhancedSegments += 1
            }
        }
        XCTAssertGreaterThan(enhancedSegments, 0, "expected enhanced (normalized) audio in the short")
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

        // 8. True cross-dissolve: during the blend both clips are on screen and moving.
        var dissolve = Timeline.empty(name: "Dissolve", canvas: .landscape1080)
        let videoTrack = dissolve.tracks.first { $0.kind == .video }!.id
        let groupA = UUID(), groupB = UUID()
        let clipA = TimelineClip(name: "A", content: .media(assetID: asset.id), start: 0, sourceIn: 10, sourceDuration: 3, linkGroup: groupA)
        let clipB = TimelineClip(name: "B", content: .media(assetID: asset.id), start: 3, sourceIn: 40, sourceDuration: 3,
                                 transitionIn: ClipTransition(kind: .crossDissolve, duration: 1), linkGroup: groupB)
        try dissolve.insert(clipA, onTrack: videoTrack)
        try dissolve.insert(clipB, onTrack: videoTrack)
        let audioTrack = dissolve.tracks.first { $0.kind == .audio }!.id
        try dissolve.insert(TimelineClip(name: "A audio", content: .media(assetID: asset.id), start: 0, sourceIn: 10, sourceDuration: 3, linkGroup: groupA), onTrack: audioTrack)
        try dissolve.insert(TimelineClip(name: "B audio", content: .media(assetID: asset.id), start: 3, sourceIn: 40, sourceDuration: 3, linkGroup: groupB), onTrack: audioTrack)
        let builtDissolve = try await CompositionBuilder.build(timeline: dissolve, assets: [asset.id: asset])
        let during = builtDissolve.videoComposition.instructions
            .compactMap { $0 as? PulseCompositionInstruction }
            .first { $0.timeRange.containsTime(.seconds(3.5)) }
        let videoTrackIDs = Set(during?.layers.compactMap { layer -> CMPersistentTrackID? in
            if case .video(let trackID, _, _) = layer.content { return trackID }
            return nil
        } ?? [])
        XCTAssertEqual(videoTrackIDs.count, 2, "clip A's handle and clip B should both render during the dissolve")
        // The linked audio crossfades too: A's audio continues on a helper track under B.
        XCTAssertEqual(builtDissolve.composition.tracks.filter { $0.mediaType == .audio }.count, 2)
        XCTAssertEqual(builtDissolve.audioMix.inputParameters.count, 2)
        let gd = AVAssetImageGenerator(asset: builtDissolve.composition)
        gd.videoComposition = builtDissolve.videoComposition
        gd.requestedTimeToleranceBefore = .zero
        gd.requestedTimeToleranceAfter = .zero
        Self.writePNG(try await gd.image(at: .seconds(3.5)).image, name: "dissolve-mid.png")

        // 9. Multicam: the same stream as two synced "angles" 20 s apart; live-cut between them.
        let session = UUID()
        var angleA = asset
        angleA.id = UUID(); angleA.name = "Cam A"; angleA.role = .camera; angleA.syncGroupID = session; angleA.syncOffset = 0
        var angleB = asset
        angleB.id = UUID(); angleB.name = "Cam B"; angleB.role = .camera; angleB.syncGroupID = session; angleB.syncOffset = -20
        let group = try XCTUnwrap(MulticamGroup.groups(in: [angleA, angleB]).first)
        var multicam = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 5, end: 15), assetID: angleA.id)], group: group,
                                               audioAssetID: angleA.id, canvas: .landscape1080, name: "Multicam")
        try MulticamEditor.cut(&multicam, at: 4, to: angleB.id, group: group)
        let cams = multicam.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(cams.map(\.assetID), [angleA.id, angleB.id])
        XCTAssertEqual(cams[1].sourceIn, 29, accuracy: 1e-6, "session 9 s is source 29 s on Cam B")
        let builtMulticam = try await CompositionBuilder.build(timeline: multicam, assets: [angleA.id: angleA, angleB.id: angleB])
        XCTAssertTrue(builtMulticam.missingAssetIDs.isEmpty)
        XCTAssertEqual(builtMulticam.duration, 10, accuracy: 0.05)
        let gm = AVAssetImageGenerator(asset: builtMulticam.composition)
        gm.videoComposition = builtMulticam.videoComposition
        Self.writePNG(try await gm.image(at: .seconds(6)).image, name: "multicam-cam-b.png")

        // 9b. Grid shot: both angles on screen at once in a vertical 2-up.
        var grid = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 25, end: 31), assetID: angleA.id, extraAngles: [angleB.id])],
                                           group: group, audioAssetID: angleA.id, canvas: .vertical1080, name: "Grid")
        XCTAssertEqual(MulticamEditor.gridPartners(of: grid.tracks[0].clips[0].id, in: grid).count, 1)
        try MulticamEditor.applyGrid(&grid, clipID: grid.tracks[0].clips[0].id, angles: [angleA.id, angleB.id], layout: .twoUp, group: group)
        let builtGrid = try await CompositionBuilder.build(timeline: grid, assets: [angleA.id: angleA, angleB.id: angleB])
        XCTAssertTrue(builtGrid.missingAssetIDs.isEmpty)
        let gridLayers = builtGrid.videoComposition.instructions.compactMap { $0 as? PulseCompositionInstruction }
            .first { $0.timeRange.containsTime(.seconds(3)) }?.layers.count ?? 0
        XCTAssertEqual(gridLayers, 2, "both cells render")
        let gg = AVAssetImageGenerator(asset: builtGrid.composition)
        gg.videoComposition = builtGrid.videoComposition
        Self.writePNG(try await gg.image(at: .seconds(3)).image, name: "multicam-grid-2up.png")

        // 10. Compound clip: two video clips + a title collapsed, then scaled down as one picture.
        var compoundEdit = Timeline.empty(name: "Compound", canvas: .landscape1080)
        let cv = compoundEdit.tracks[0].id, ct = compoundEdit.tracks[2].id, ca = compoundEdit.tracks[3].id
        try compoundEdit.insert(TimelineClip(name: "Shot 1", content: .media(assetID: asset.id), start: 0, sourceIn: 5, sourceDuration: 2), onTrack: cv)
        try compoundEdit.insert(TimelineClip(name: "Shot 2", content: .media(assetID: asset.id), start: 2, sourceIn: 40, sourceDuration: 2), onTrack: cv)
        try compoundEdit.insert(TimelineClip(name: "Shot audio", content: .media(assetID: asset.id), start: 0, sourceIn: 5, sourceDuration: 4), onTrack: ca)
        try compoundEdit.insert(TimelineClip(name: "Title", content: .text(TextElement(text: "COMPOUND")), start: 0.5, sourceDuration: 3), onTrack: ct)
        let (nestedTimeline, compoundID) = try CompoundEditor.makeCompound(in: &compoundEdit, clipIDs: compoundEdit.allClips.map(\.id), name: "Group")
        compoundEdit.updateClip(id: compoundID) { $0.transform.scale = AnimatedDouble(0.5) }
        var compoundOptions = CompositionBuilder.Options()
        compoundOptions.compounds = [nestedTimeline.id: nestedTimeline]
        let builtCompound = try await CompositionBuilder.build(timeline: compoundEdit, assets: [asset.id: asset], options: compoundOptions)
        XCTAssertTrue(builtCompound.missingAssetIDs.isEmpty)
        XCTAssertEqual(builtCompound.duration, 4, accuracy: 0.05)
        let groupInstruction = builtCompound.videoComposition.instructions
            .compactMap { $0 as? PulseCompositionInstruction }
            .first { $0.timeRange.containsTime(.seconds(2.5)) }
        let groupLayer = groupInstruction?.layers.first { if case .group = $0.content { return true }; return false }
        XCTAssertNotNil(groupLayer, "the compound renders as one group layer")
        if case .group(let children)? = groupLayer?.content {
            XCTAssertEqual(children.count, 2, "Shot 2 + the title are inside the group at 2.5 s")
        }
        XCTAssertEqual(builtCompound.composition.tracks.filter { $0.mediaType == .audio }.count, 1, "nested audio is mixed in")
        let gc = AVAssetImageGenerator(asset: builtCompound.composition)
        gc.videoComposition = builtCompound.videoComposition
        Self.writePNG(try await gc.image(at: .seconds(2.5)).image, name: "compound-scaled.png")
    }

    /// Live screen capture through ScreenCaptureKit. Skips when the runner has no Screen Recording permission.
    func testScreenRecordingWhenPermitted() async throws {
        let sources: [CaptureSource]
        do {
            sources = try await withThrowingTaskGroup(of: [CaptureSource].self) { group in
                group.addTask { try await SessionRecorder.sources() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw CaptureError.screenPermission
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch {
            throw XCTSkip("Screen Recording not permitted on this machine: \(error.localizedDescription)")
        }
        guard let display = sources.first(where: { $0.kind == .display }) else { throw XCTSkip("no display") }
        let dir = Self.workDir.appendingPathComponent("capture-\(UUID().uuidString)", isDirectory: true)
        let recorder = SessionRecorder()
        do {
            try await recorder.start(RecordingOptions(source: display, captureSystemAudio: false, frameRate: 30, codec: .h264, outputDirectory: dir))
        } catch CaptureError.screenPermission {
            throw XCTSkip("Screen Recording not permitted")
        }
        // Record 1.5 s, pause 2 s, record 1.5 s: the file holds ~3 s with no gap.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        recorder.pause()
        XCTAssertTrue(recorder.isPaused)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        recorder.resume()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(recorder.elapsed, 3, accuracy: 0.5)
        let result = try await recorder.stop()
        let screen = try XCTUnwrap(result.files.first { $0.role == .gameplay })
        let meta = try await MediaProbe.probe(screen.url)
        XCTAssertTrue(meta.hasVideo)
        XCTAssertEqual(meta.duration, 3, accuracy: 0.6, "paused time is excluded; a static screen still records until Stop")
        print("screen capture:", screen.url.lastPathComponent, meta.width, "x", meta.height, String(format: "%.1fs", meta.duration))
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
