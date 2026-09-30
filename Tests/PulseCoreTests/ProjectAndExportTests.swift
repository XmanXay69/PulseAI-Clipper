import XCTest
@testable import PulseCore

final class ProjectAndExportTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PulseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func sampleDocument() -> ProjectDocument {
        var doc = ProjectDocument(name: "Big Stream")
        doc.media = [Fixtures.mediaAsset()]
        doc.primaryAssetID = Fixtures.assetID
        var timeline = Fixtures.simpleTimeline(clipDuration: 12)
        timeline.captions = CaptionTrack(sourceAssetID: Fixtures.assetID, words: [CaptionWord(text: "hey", start: 100, end: 100.4)])
        timeline.tracks[0].clips[0].transform.zoom.setKeyframe(at: 2, value: 1.1, aiGenerated: true)
        doc.timelines = [timeline]
        doc.candidates = [ClipCandidate(assetID: Fixtures.assetID, range: TimeRange(start: 10, end: 40), payoffTime: 30, targetDuration: 30,
                                        potential: 77, scores: ClipScores(hook: 0.5), tags: [.funny], title: "NO WAY", copy: .empty, transcriptSnippet: "no way")]
        return doc
    }

    func testCreateSaveLoadRoundTrip() throws {
        let store = ProjectStore()
        let (package, _) = try store.create(name: "Big Stream", in: tempDir)
        XCTAssertEqual(package.url.pathExtension, "pulse")
        var doc = sampleDocument()
        doc.id = try store.load(package).document.id
        try store.save(doc, to: package)
        let loaded = try store.load(package)
        XCTAssertFalse(loaded.recoveredFromBackup)
        XCTAssertEqual(loaded.document, doc)
        XCTAssertEqual(loaded.document.status, .editing)
        XCTAssertEqual(store.backups(of: package).count, 1)
        // Second project with the same name gets a unique folder.
        let (second, _) = try store.create(name: "Big Stream", in: tempDir)
        XCTAssertNotEqual(second.url, package.url)
        XCTAssertEqual(store.listProjects(in: tempDir).count, 2)
    }

    func testCorruptedProjectFallsBackToBackup() throws {
        let store = ProjectStore()
        let (package, _) = try store.create(name: "Fragile", in: tempDir)
        let doc = sampleDocument()
        try store.save(doc, to: package)
        try store.save(doc, to: package) // creates a backup of the good file
        try Data("{ not json".utf8).write(to: package.documentURL)
        let loaded = try store.load(package)
        XCTAssertTrue(loaded.recoveredFromBackup)
        XCTAssertEqual(loaded.document.name, "Big Stream")
    }

    func testBackupRotationKeepsLimit() throws {
        let store = ProjectStore(backupsToKeep: 3)
        let (package, doc) = try store.create(name: "Rotate", in: tempDir)
        for _ in 0..<6 {
            try store.save(doc, to: package)
            Thread.sleep(forTimeInterval: 0.002)
        }
        XCTAssertEqual(store.backups(of: package).count, 3)
    }

    func testVersionsAndAnalysisPersistence() throws {
        let store = ProjectStore()
        let (package, _) = try store.create(name: "Versions", in: tempDir)
        let doc = sampleDocument()
        let v1 = try store.createVersion(of: doc, in: package)
        var changed = doc
        changed.name = "Changed"
        let v2 = try store.createVersion(of: changed, in: package, label: "Experiment")
        XCTAssertEqual(v1.number, 1)
        XCTAssertEqual(v2.number, 2)
        XCTAssertEqual(store.versions(of: package).map(\.label), ["Experiment", "Version 1"])
        XCTAssertEqual(try store.loadVersion(v1, in: package).name, "Big Stream")

        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 60, audio: Fixtures.audio(duration: 60), transcript: Fixtures.transcript(duration: 60))
        try store.saveAnalysis(analysis, in: package)
        let reloaded = store.loadAnalysis(assetID: Fixtures.assetID, in: package)
        XCTAssertEqual(reloaded?.audio?.count, analysis.audio?.count)
        XCTAssertEqual(reloaded?.transcript?.words.count, analysis.transcript?.words.count)
    }

    func testDuplicateProjectGetsNewIdentity() throws {
        let store = ProjectStore()
        let (package, original) = try store.create(name: "Original", in: tempDir)
        let copy = try store.duplicate(package, newName: "Original copy")
        let loaded = try store.load(copy).document
        XCTAssertEqual(loaded.name, "Original copy")
        XCTAssertNotEqual(loaded.id, original.id)
    }

    func testRecoveryManagerLifecycle() throws {
        let recovery = RecoveryManager(directory: tempDir.appendingPathComponent("Recovery"))
        XCTAssertFalse(recovery.beginSession())
        let doc = sampleDocument()
        try recovery.writeSnapshot(doc, projectPath: "/tmp/x.pulse")
        // Simulate a crash: the next launch finds the lock and the snapshot.
        XCTAssertTrue(recovery.beginSession())
        let pending = recovery.pendingRecoveries()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].document, doc)
        recovery.discard(pending[0])
        XCTAssertTrue(recovery.pendingRecoveries().isEmpty)
        recovery.endSession()
        XCTAssertFalse(recovery.beginSession())
    }

    func testDocumentDecodesWithMissingNewerFields() throws {
        // A minimal file written by an older version still opens.
        let json = """
        {"id": "\(UUID().uuidString)", "name": "Old", "timelines": [{"id": "\(UUID().uuidString)", "name": "T", "tracks": [{"id": "\(UUID().uuidString)", "kind": "video", "name": "V1", "clips": [
          {"id": "\(UUID().uuidString)", "content": {"media": {"assetID": "\(Fixtures.assetID.uuidString)"}}, "start": 0, "sourceDuration": 5}
        ]}]}]}
        """
        let doc = try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.timelines[0].tracks[0].clips[0].duration, 5)
        XCTAssertEqual(doc.timelines[0].canvas, .vertical1080)
    }

    func testExportFilenameSizeAndValidation() {
        var settings = ExportSettings(preset: .tiktok, outputDirectory: "/tmp")
        settings.filenameTemplate = "{project}-{clip}-{preset}-{index}"
        let name = settings.filename(project: "My/Stream", clip: "“NO WAY?!” 😭", index: 3)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains("😭"))
        XCTAssertTrue(name.hasSuffix(".mp4"))
        XCTAssertTrue(name.contains("TikTok"))
        XCTAssertTrue(name.contains("03"))

        let size = settings.outputSize(for: .vertical1080)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
        var youtube = ExportSettings(preset: .youtube, outputDirectory: "/tmp")
        let squareSize = youtube.outputSize(for: .square1080)
        XCTAssertEqual(squareSize.width, 1920)
        XCTAssertEqual(squareSize.height, 1920)
        XCTAssertNil(youtube.validationError(for: .landscape1080))
        youtube.videoBitrate = 1000
        XCTAssertNotNil(youtube.validationError(for: .landscape1080))
        XCTAssertNotNil(ExportSettings(preset: .tiktok, outputDirectory: "").validationError(for: .vertical1080))

        let existing: Set<String> = ["/out/Clip.mp4", "/out/Clip (2).mp4"]
        let url = ExportSettings.uniqueURL(directory: URL(fileURLWithPath: "/out"), filename: "Clip.mp4") { existing.contains($0.path) }
        XCTAssertEqual(url.lastPathComponent, "Clip (3).mp4")
    }

    func testExportQueueSummary() {
        var a = ExportJob(projectID: UUID(), projectName: "P", timelineID: UUID(), timelineName: "A", settings: ExportSettings())
        a.status = .completed(path: "/tmp/a.mp4")
        a.startedAt = Date(timeIntervalSinceNow: -20)
        a.finishedAt = Date(timeIntervalSinceNow: -10)
        var b = ExportJob(projectID: UUID(), projectName: "P", timelineID: UUID(), timelineName: "B", settings: ExportSettings())
        b.status = .rendering(progress: 0.5)
        b.startedAt = Date(timeIntervalSinceNow: -5)
        let c = ExportJob(projectID: UUID(), projectName: "P", timelineID: UUID(), timelineName: "C", settings: ExportSettings())
        let summary = ExportQueueSummary(jobs: [a, b, c])
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.active, 1)
        XCTAssertEqual(summary.queued, 1)
        XCTAssertEqual(summary.overallProgress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(summary.estimatedRemaining ?? 0, 15, accuracy: 1)
    }

    func testImportPlanClassifiesFiles() {
        let urls = ["Gameplay.mp4", "Webcam.mp4", "Microphone.wav", "notes.docx", "Stream.srt", "Gameplay.mp4"].map { URL(fileURLWithPath: "/media/\($0)") }
        let plan = ImportPlan.make(urls: urls, existingPaths: [])
        XCTAssertEqual(plan.items.map(\.role), [.gameplay, .webcam, .microphone])
        XCTAssertEqual(plan.rejected.count, 1)
        XCTAssertEqual(plan.transcripts.count, 1)
        XCTAssertEqual(plan.duplicates.count, 1)
        XCTAssertTrue(plan.isMultiSourceSession)
        XCTAssertTrue(ImportPlan.make(urls: [URL(fileURLWithPath: "/m/vod.mkv")], existingPaths: []).items[0].needsConversion)
    }

    func testSearchFindsClipsTranscriptAndTimestamps() {
        let doc = sampleDocument()
        let transcript = Fixtures.transcript(duration: 120, special: [(50, "hahaha"), (90, "lmao")])
        let analyses = [Fixtures.assetID: MediaAnalysis(assetID: Fixtures.assetID, duration: 120, transcript: transcript)]
        let results = SearchEngine.search("funny", projects: [doc.summary], document: doc, analyses: analyses)
        XCTAssertTrue(results.contains { $0.kind == .clip })
        XCTAssertEqual(results.filter { $0.kind == .transcript }.count, 2)
        let jump = SearchEngine.search("1:30", projects: [], document: doc, analyses: [:])
        XCTAssertEqual(jump.first?.time, 90)
    }

    func testShortBuilderCreatesEditableTimeline() {
        let duration: Seconds = 600
        let transcript = Fixtures.transcript(duration: duration, special: [(300, "NO"), (300.4, "WAY!"), (301, "hahaha")])
        var faces: [FaceSample] = []
        for t in stride(from: 0.0, to: duration, by: 2) { faces.append(FaceSample(time: t, boxes: [NormRect(x: 0.84, y: 0.74, width: 0.06, height: 0.11)])) }
        let visual = VisualFeatureSeries(hop: 1, motion: [Float](repeating: 0.02, count: 600), brightness: [Float](repeating: 0.4, count: 600), sceneCuts: [], faces: faces)
        let webcam = WebcamEstimator.estimate(faces: faces, frameSize: Size2(1920, 1080))
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: [300], silences: [TimeRange(start: 285, end: 288)]),
                                     visual: visual, transcript: transcript, webcam: webcam, profile: .gameplayWithFacecam)
        let generator = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings(targetDuration: 30, minimumPotential: 0))
        let candidate = generator.generate().first { $0.range.contains(300) }!
        let timeline = ShortBuilder.build(ShortBuildInput(candidate: candidate, asset: Fixtures.mediaAsset(duration: duration), analysis: analysis), options: .oneClick)

        XCTAssertEqual(timeline.canvas.width, 1080)
        XCTAssertEqual(timeline.canvas.height, 1920)
        XCTAssertEqual(timeline.layout, .splitScreen)
        XCTAssertTrue(timeline.allClips.contains { $0.role == .webcam && $0.isEnabled })
        XCTAssertNotNil(timeline.captions)
        XCTAssertFalse(timeline.captions!.words.isEmpty)
        XCTAssertTrue(timeline.markers.contains { $0.name == "Payoff" && $0.aiGenerated })
        XCTAssertTrue(timeline.hasAIContent)
        XCTAssertLessThanOrEqual(timeline.duration, candidate.duration + 1e-6)
        XCTAssertEqual(timeline.origin?.candidateID, candidate.id)

        // Everything AI can be stripped back to a plain cut.
        var stripped = timeline
        EntertainmentEditor.stripAIEdits(from: &stripped)
        XCTAssertTrue(stripped.markers.isEmpty)
        XCTAssertTrue(stripped.removedSections.filter(\.aiGenerated).isEmpty)
        XCTAssertFalse(stripped.allClips.contains { $0.transform.zoom.hasAIKeyframes })
    }

    func testEntertainmentPassReportsChanges() {
        let duration: Seconds = 300
        let silences = [TimeRange(start: 110, end: 112), TimeRange(start: 118, end: 121)]
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration, audio: Fixtures.audio(duration: duration, silences: silences),
                                     transcript: Transcript(words: [TranscriptWord(text: "um", start: 105, end: 105.3), TranscriptWord(text: "INSANE!", start: 106, end: 106.5)], source: .demo))
        var t = Fixtures.simpleTimeline(clipDuration: 30) // source 100…130
        t.captions = CaptionTrack.make(from: analysis.transcript!, range: TimeRange(start: 100, end: 130), assetID: Fixtures.assetID, style: .bold, emphasize: false)
        let report = EntertainmentEditor.apply(to: &t, analysis: analysis, options: EntertainmentOptions())
        XCTAssertGreaterThanOrEqual(report.silenceCuts, 2)
        XCTAssertEqual(report.fillerCuts, 1)
        XCTAssertGreaterThan(report.removedSeconds, 3)
        XCTAssertLessThan(t.duration, 30)
        XCTAssertFalse(report.summary.isEmpty)
    }
}
