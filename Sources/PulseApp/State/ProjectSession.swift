import AppKit
import Foundation
import PulseCore
import PulseEngine
import SwiftUI

enum EditTool: String, CaseIterable {
    case select, blade

    var symbol: String { self == .select ? "cursorarrow" : "scissors" }
    var shortcut: String { self == .select ? "A" : "B" }
}

enum LeftPanelTab: String, CaseIterable, Identifiable {
    case media, transcript, angles, effects, ai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .media: return "Media"
        case .transcript: return "Transcript"
        case .angles: return "Angles"
        case .effects: return "Effects"
        case .ai: return "AI Tools"
        }
    }
    var symbol: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .transcript: return "text.quote"
        case .angles: return "video.badge.checkmark"
        case .effects: return "sparkle"
        case .ai: return "wand.and.stars"
        }
    }
}

/// An open project: the document, undo history, analyses, selection and playback.
@MainActor
final class ProjectSession: ObservableObject, Identifiable {
    let id = UUID()
    let package: ProjectPackage
    unowned let app: AppModel

    @Published private(set) var document: ProjectDocument
    @Published private(set) var analyses: [UUID: MediaAnalysis] = [:]
    @Published private(set) var isDirty = false
    @Published private(set) var lastSaved: Date?
    @Published var selectedTimelineID: UUID?
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var selectedCandidateIDs: Set<UUID> = []
    @Published var focusedCaptionWordID: UUID?
    @Published var tool: EditTool = .select
    @Published var pixelsPerSecond: Double = 60
    @Published var inPoint: Seconds?
    @Published var outPoint: Seconds?
    @Published var leftTab: LeftPanelTab = .media
    @Published var candidateSort: CandidateSort = .potential
    @Published var analysisProgress: [UUID: EngineProgress] = [:]
    @Published var lastAIReport: String?
    /// Timelines we came from while inside compound clips (breadcrumb, outermost first).
    @Published var compoundPath: [UUID] = []

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var undoLabel: String?
    @Published private(set) var redoLabel: String?

    let playback = PlaybackController()
    private var history = History<ProjectDocument>()
    private var autosaveTask: Task<Void, Never>?
    private var snapshotDirty = false

    init(package: ProjectPackage, document: ProjectDocument, app: AppModel) {
        self.package = package
        self.document = document
        self.app = app
        selectedTimelineID = document.activeTimelineID ?? document.timelines.first?.id
        for asset in document.media {
            if let analysis = app.store.loadAnalysis(assetID: asset.id, in: package) { analyses[asset.id] = analysis }
        }
        refreshAvailability()
        startAutosave()
        reloadPlayback(debounce: 0)
    }

    // MARK: Derived

    var assetsByID: [UUID: MediaAsset] {
        Dictionary(uniqueKeysWithValues: document.media.map { ($0.id, $0) })
    }

    var activeTimeline: Timeline? {
        selectedTimelineID.flatMap { document.timeline(id: $0) }
    }

    var selectedClips: [TimelineClip] {
        guard let t = activeTimeline else { return [] }
        return selectedClipIDs.compactMap { t.clip(id: $0) }
    }

    var primaryAnalysis: MediaAnalysis? {
        document.primaryAsset.flatMap { analyses[$0.id] }
    }

    func analysis(for timeline: Timeline) -> MediaAnalysis? {
        (timeline.origin?.assetID ?? timeline.assetIDs.first).flatMap { analyses[$0] }
    }

    func url(for asset: MediaAsset) -> URL { MediaAccess.resolve(asset) }

    // MARK: Editing (everything goes through here → undoable)

    /// Applies an edit to the document, recording an undo step.
    func edit(_ label: String, coalesce: String? = nil, _ body: (inout ProjectDocument) throws -> Void) {
        let before = document
        var working = document
        do {
            try body(&working)
        } catch {
            app.present(error, title: "Can't \(label.lowercased())")
            return
        }
        guard working != before else { return }
        history.record(before, label: label, coalesceKey: coalesce)
        working.touch()
        let timelineChanged = working.timelines != before.timelines || working.media != before.media
        document = working
        markDirty()
        if timelineChanged { reloadPlayback(debounce: coalesce == nil ? 0.02 : 0.1) }
    }

    /// Edits the active timeline.
    func editTimeline(_ label: String, coalesce: String? = nil, _ body: (inout Timeline) throws -> Void) {
        guard let id = selectedTimelineID else { return }
        edit(label, coalesce: coalesce) { doc in
            try doc.editTimeline(id: id, body)
        }
    }

    /// Edits one clip on the active timeline (inspector controls).
    func editClip(_ clipID: UUID, _ label: String, coalesce: String? = nil, _ body: @escaping (inout TimelineClip) -> Void) {
        editTimeline(label, coalesce: coalesce ?? "clip-\(clipID)-\(label)") { t in
            t.updateClip(id: clipID, body)
        }
    }

    func undo() {
        guard let previous = history.undo(current: document) else { return }
        apply(restored: previous)
    }

    func redo() {
        guard let next = history.redo(current: document) else { return }
        apply(restored: next)
    }

    private func apply(restored: ProjectDocument) {
        document = restored
        if let id = selectedTimelineID, restored.timeline(id: id) == nil { selectedTimelineID = restored.timelines.first?.id }
        selectedClipIDs = selectedClipIDs.filter { id in activeTimeline?.clip(id: id) != nil }
        markDirty()
        reloadPlayback(debounce: 0)
    }

    private func markDirty() {
        isDirty = true
        snapshotDirty = true
        canUndo = history.canUndo
        canRedo = history.canRedo
        undoLabel = history.undoLabel
        redoLabel = history.redoLabel
    }

    /// Ends slider-drag coalescing so the next change is a new undo step.
    func commitCoalescing() {
        history.breakCoalescing()
    }

    // MARK: Playback

    func reloadPlayback(debounce: Double = 0.05) {
        guard let timeline = activeTimeline else { return }
        playback.load(timeline: timeline, assets: assetsByID, compounds: document.compoundsByID,
                      useProxies: app.settings.proxy.useProxiesForPlayback, debounce: debounce)
    }

    func open(timelineID: UUID, at time: Seconds? = nil, section: SidebarSection = .editor) {
        compoundPath = []
        let switching = selectedTimelineID != timelineID
        selectedTimelineID = timelineID
        selectedClipIDs = []
        document.activeTimelineID = timelineID
        reloadPlayback(debounce: 0)
        if let time {
            playback.seek(to: time)
        } else if switching {
            playback.seek(to: 0)
        }
        app.section = section
    }

    /// Shows a moment of a recording: seeks the first timeline that contains it, otherwise
    /// builds a short around it so the user lands on something editable.
    func reveal(sourceTime: Seconds, assetID: UUID) {
        let ordered = document.timelines.sorted { ($0.id == document.activeTimelineID ? 0 : 1) < ($1.id == document.activeTimelineID ? 0 : 1) }
        for timeline in ordered {
            if let clip = timeline.allClips.first(where: { $0.assetID == assetID && $0.sourceRange.contains(sourceTime) }) {
                open(timelineID: timeline.id, at: clip.timelineTime(atSource: sourceTime))
                return
            }
        }
        let duration = document.asset(id: assetID)?.metadata.duration ?? sourceTime + 30
        let range = TimeRange(start: max(0, sourceTime - 3), end: min(duration, sourceTime + app.settings.ai.targetClipDuration - 3))
        createClip(fromSource: range, assetID: assetID)
    }

    // MARK: Persistence

    func save() {
        do {
            if document.thumbnailPath == nil, let asset = document.primaryAsset, asset.kind == .video {
                let relative = "thumbnails/poster.jpg"
                let target = package.url.appendingPathComponent(relative)
                let source = url(for: asset)
                Task {
                    if await ThumbnailService.shared.writePoster(for: source, at: min(10, asset.metadata.duration / 3), to: target) {
                        self.document.thumbnailPath = relative
                        self.save()
                    }
                }
            }
            try app.store.save(document, to: package)
            isDirty = false
            snapshotDirty = false
            lastSaved = Date()
            app.recovery.clearSnapshot(projectID: document.id)
            app.library?.index(document, path: package.url.path, thumbnailPath: document.thumbnailPath.map { package.url.appendingPathComponent($0).path })
            app.refreshProjects()
        } catch {
            app.present(error, title: "Couldn't save the project")
        }
    }

    private func startAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            var sinceSave: TimeInterval = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                sinceSave += 2
                let settings = self.app.settings
                if self.snapshotDirty {
                    try? self.app.recovery.writeSnapshot(self.document, projectPath: self.package.url.path)
                    self.snapshotDirty = false
                }
                if self.isDirty && sinceSave >= settings.autosaveInterval {
                    self.save()
                    sinceSave = 0
                }
            }
        }
    }

    func close() {
        if isDirty { save() }
        autosaveTask?.cancel()
        playback.pause()
    }

    func createVersion(label: String?) {
        do {
            let v = try app.store.createVersion(of: document, in: package, label: label)
            app.toast("Saved \(v.label)")
        } catch {
            app.present(error, title: "Couldn't create a version")
        }
    }

    func restore(version: ProjectVersion) {
        do {
            var restored = try app.store.loadVersion(version, in: package)
            restored.id = document.id
            let before = document
            history.record(before, label: "Restore \(version.label)")
            document = restored
            markDirty()
            reloadPlayback(debounce: 0)
        } catch {
            app.present(error, title: "Couldn't restore that version")
        }
    }

    // MARK: Media

    func refreshAvailability() {
        for i in document.media.indices {
            let exists = FileManager.default.fileExists(atPath: url(for: document.media[i]).path)
            let availability: MediaAvailability = exists ? .online : .missing
            if document.media[i].availability != availability && document.media[i].availability != .unsupported {
                document.media[i].availability = availability
            }
        }
    }

    func importMedia(_ urls: [URL]) {
        let plan = ImportPlan.make(urls: urls, existingPaths: Set(document.media.map(\.path)))
        if !plan.rejected.isEmpty {
            app.presentMessage(title: "Some files weren't imported", message: plan.rejected.map { "\($0.url.lastPathComponent): \($0.reason)" }.joined(separator: "\n"))
        }
        if plan.items.isEmpty && plan.transcripts.isEmpty {
            if !plan.duplicates.isEmpty { app.toast("Already in this project") }
            return
        }
        let cacheRoot = app.cacheFolder
        app.jobs.start("Importing \(plan.items.count) file\(plan.items.count == 1 ? "" : "s")", kind: .importMedia) { [weak self] job in
            guard let self else { return }
            var imported: [MediaAsset] = []
            var failures: [String] = []
            for (i, item) in plan.items.enumerated() {
                job.detail = item.url.lastPathComponent
                do {
                    let asset = try await MediaImporter.makeAsset(for: item, cacheRoot: cacheRoot)
                    imported.append(asset)
                } catch {
                    failures.append("\(item.url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                }
                job.progress = Double(i + 1) / Double(max(plan.items.count, 1))
            }
            if !imported.isEmpty {
                let syncGroup: UUID? = plan.isMultiSourceSession ? UUID() : nil
                self.edit("Import Media") { doc in
                    for var asset in imported {
                        asset.syncGroupID = syncGroup
                        doc.media.append(asset)
                    }
                    if doc.primaryAssetID == nil {
                        doc.primaryAssetID = imported.first(where: { $0.kind == .video && ($0.role == .main || $0.role == .gameplay) })?.id ?? imported.first?.id
                    }
                }
                self.save()
                // Offer proxies for heavy media.
                for asset in imported where asset.kind == .video && self.app.settings.proxy.shouldGenerateProxy(sourceHeight: asset.metadata.height, duration: asset.metadata.duration) {
                    self.generateProxy(assetID: asset.id)
                }
            }
            for url in plan.transcripts { self.importTranscript(url, for: nil) }
            if !failures.isEmpty {
                self.app.presentMessage(title: "Some files couldn't be imported", message: failures.joined(separator: "\n\n"))
            }
            if plan.isMultiSourceSession && imported.count >= 2 {
                self.synchronize(imported.map(\.id))
            }
        }
    }

    func importTranscript(_ url: URL, for assetID: UUID?) {
        guard let target = assetID ?? document.primaryAsset?.id else {
            app.presentMessage(title: "Import a video first", message: "Transcripts attach to a video or audio file in the project.")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let transcript = try TranscriptParser.parse(data: data, fileExtension: url.pathExtension)
            var analysis = analyses[target] ?? MediaAnalysis(assetID: target, duration: document.asset(id: target)?.metadata.duration ?? transcript.duration)
            analysis.transcript = transcript
            analysis.processing["transcript"] = .local
            setAnalysis(analysis)
            app.toast("Imported \(transcript.words.count) transcript words")
        } catch {
            app.present(error, title: "Couldn't read the transcript")
        }
    }

    func setAnalysis(_ analysis: MediaAnalysis) {
        analyses[analysis.assetID] = analysis
        try? app.store.saveAnalysis(analysis, in: package)
        if let transcript = analysis.transcript {
            app.library?.indexTranscript(transcript, projectID: document.id, assetID: analysis.assetID)
        }
    }

    func generateProxy(assetID: UUID) {
        guard let asset = document.asset(id: assetID) else { return }
        let settings = app.settings.proxy
        let cacheRoot = app.cacheFolder
        app.jobs.start("Proxy · \(asset.name)", kind: .proxy) { [weak self] job in
            let url = try await ProxyGenerator.makeProxy(for: asset, settings: settings, cacheRoot: cacheRoot) { p in
                Task { @MainActor in job.progress = p }
            }
            self?.document.media.firstIndex { $0.id == assetID }.map { self?.document.media[$0].preparation.proxyPath = url.path }
            self?.markDirty()
            self?.reloadPlayback()
        }
    }

    /// Aligns separately recorded sources by their audio.
    func synchronize(_ assetIDs: [UUID]) {
        let assets = assetIDs.compactMap { document.asset(id: $0) }.filter { $0.metadata.hasAudio }
        guard assets.count >= 2 else { return }
        app.jobs.start("Synchronizing \(assets.count) recordings", kind: .analysis) { [weak self] job in
            guard let self else { return }
            var envelopes: [UUID: [Float]] = [:]
            for (i, asset) in assets.enumerated() {
                job.detail = asset.name
                let result = try await AudioAnalyzer().analyze(url: self.url(for: asset), isCancelled: job.isCancelledCheck)
                envelopes[asset.id] = result.features.rmsDB.values
                job.progress = Double(i + 1) / Double(assets.count + 1)
            }
            guard let reference = assets.first, let refEnv = envelopes[reference.id] else { return }
            var offsets: [UUID: Seconds] = [reference.id: 0]
            var lowConfidence: [String] = []
            for asset in assets.dropFirst() {
                guard let env = envelopes[asset.id], let result = AudioSync.estimateOffset(reference: refEnv, other: env, hop: AudioAnalyzer.hop, maxOffset: 120) else { continue }
                offsets[asset.id] = result.offset
                if result.confidence < 0.3 { lowConfidence.append(asset.name) }
            }
            self.edit("Synchronize Recordings") { doc in
                let group = UUID()
                for (id, offset) in offsets {
                    doc.updateAsset(id: id) {
                        $0.syncOffset = offset
                        $0.syncGroupID = group
                    }
                }
            }
            self.app.toast(lowConfidence.isEmpty ? "Recordings synchronized" : "Synchronized — low confidence for \(lowConfidence.joined(separator: ", ")). Check alignment.")
        }
    }

    func relink(assetID: UUID, to newURL: URL) {
        edit("Relink Media") { doc in
            doc.updateAsset(id: assetID) {
                $0.path = newURL.path
                $0.bookmark = MediaAccess.bookmark(for: newURL)
                $0.availability = .online
            }
        }
    }

    // MARK: Analysis & clips

    func analyze(assetID: UUID, generateClips: Bool = true) {
        guard let asset = document.asset(id: assetID) else { return }
        let ai = app.settings.ai
        let imported = analyses[assetID]?.transcript
        let voice = voiceCompanion(for: asset).map { AnalysisPipeline.VoiceSource(main: asset, voice: $0) }
        let options = AnalysisPipeline.Options(transcribe: true, detectFaces: true, ai: ai, importedTranscript: imported, voiceSource: voice)
        let pipeline = AnalysisPipeline(cacheDirectory: PulseDirectories.cache("Analysis", root: app.cacheFolder))
        document.media.firstIndex { $0.id == assetID }.map { document.media[$0].preparation.analysisState = .running }
        app.jobs.start("Analyze · \(asset.name)", kind: .analysis) { [weak self] job in
            guard let self else { return }
            do {
                let output = try await pipeline.run(asset: asset, options: options, progress: { p in
                    Task { @MainActor [weak self] in
                        job.progress = p.fraction
                        job.detail = p.stage
                        self?.analysisProgress[assetID] = p
                    }
                }, isCancelled: job.isCancelledCheck)
                self.analysisProgress[assetID] = nil
                self.setAnalysis(output.analysis)
                self.edit("Analyze Video") { doc in
                    doc.updateAsset(id: assetID) { $0.preparation.analysisState = .complete }
                }
                let location = output.analysis.processing["transcript"] ?? .local
                self.app.logActivity(.analysis, title: "Analyzed \(asset.name)", detail: output.warnings.first ?? "Audio, video and faces", location: .local)
                if output.analysis.transcript != nil {
                    self.app.logActivity(.transcription, title: "Transcribed \(asset.name)", detail: "\(output.analysis.transcript?.words.count ?? 0) words", location: location)
                }
                if !output.warnings.isEmpty {
                    self.app.presentMessage(title: "Analysis finished with notes", message: output.warnings.joined(separator: "\n\n"))
                }
                if generateClips { self.generateCandidates(assetID: assetID) }
            } catch {
                self.analysisProgress[assetID] = nil
                self.document.media.firstIndex { $0.id == assetID }.map { self.document.media[$0].preparation.analysisState = .failed }
                throw error
            }
        }
    }

    func generateCandidates(assetID: UUID, settings override: ClipGenerationSettings? = nil) {
        guard let analysis = analyses[assetID] else {
            analyze(assetID: assetID, generateClips: true)
            return
        }
        let settings = override ?? app.settings.ai.generationSettings
        app.jobs.start("Finding clips", kind: .clipGeneration) { [weak self] job in
            guard let self else { return }
            job.detail = "Scoring moments"
            let candidates = await Task.detached(priority: .userInitiated) {
                ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: settings).generate()
            }.value
            self.edit("Generate AI Clips") { doc in
                // Keep clips the user already worked with; replace the rest.
                let kept = doc.candidates.filter { $0.assetID != assetID || $0.status != .new || $0.isFavorite }
                let fresh = candidates.filter { c in !kept.contains { $0.range.iou(c.range) > 0.5 } }
                doc.candidates = kept + fresh
                doc.generation = settings
            }
            self.app.logActivity(.clipGeneration, title: "\(candidates.count) potential clips found", detail: self.document.asset(id: assetID)?.name ?? "")
            self.app.toast("\(candidates.count) potential clips found")
            self.app.section = .aiClips
        }
    }

    func reshapeCandidate(_ id: UUID, targetDuration: Seconds?, regenerate: Bool) {
        guard let candidate = document.candidates.first(where: { $0.id == id }), let analysis = analyses[candidate.assetID] else { return }
        let generator = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: app.settings.ai.generationSettings)
        let reshaped = generator.reshape(candidate, targetDuration: targetDuration, generation: regenerate ? candidate.generation + 1 : nil)
        edit(regenerate ? "Regenerate Clip" : (targetDuration ?? 0) < candidate.duration ? "Shorten Clip" : "Extend Clip") { doc in
            guard let i = doc.candidates.firstIndex(where: { $0.id == id }) else { return }
            doc.candidates[i] = reshaped
        }
    }

    func deleteCandidates(_ ids: Set<UUID>) {
        edit(ids.count == 1 ? "Delete Clip" : "Delete \(ids.count) Clips") { doc in
            for i in doc.candidates.indices where ids.contains(doc.candidates[i].id) {
                doc.candidates[i].status = .dismissed
            }
        }
        selectedCandidateIDs.subtract(ids)
    }

    /// One-click short / Auto Edit: builds an editable timeline and opens it.
    @discardableResult
    func createShort(from candidateID: UUID, mode: ShortBuildOptions.Mode = .oneClick, open: Bool = true) -> UUID? {
        guard let candidate = document.candidates.first(where: { $0.id == candidateID }),
              let asset = document.asset(id: candidate.assetID) else { return nil }
        if let existing = candidate.timelineID, document.timeline(id: existing) != nil, mode == .oneClick {
            if open { self.open(timelineID: existing) }
            return existing
        }
        var options = ShortBuildOptions(settings: app.settings.ai, mode: mode)
        options.canvasPresetID = app.settings.safeAreaPlatform == .youtubeShorts ? CanvasPreset.shorts.id : (app.settings.safeAreaPlatform == .instagramReels ? CanvasPreset.reels.id : CanvasPreset.tiktok.id)
        let sfx = document.media.filter { $0.role == .soundEffect }
        let music = app.settings.ai.aiMusic ? document.media.first { $0.role == .music } : nil
        let cam = webcamCompanion(for: asset)
        let input = ShortBuildInput(candidate: candidate, asset: asset, analysis: analyses[asset.id], soundEffects: sfx, music: music,
                                    companionWebcam: cam, companionVoice: voiceCompanion(for: asset),
                                    companionFaceCenter: cam.flatMap { analyses[$0.id]?.webcam?.face.center })
        let timeline = ShortBuilder.build(input, options: options)
        edit(mode == .autoEdit ? "Auto Edit Short" : "Create Short") { doc in
            doc.timelines.append(timeline)
            if let i = doc.candidates.firstIndex(where: { $0.id == candidateID }) {
                doc.candidates[i].timelineID = timeline.id
                doc.candidates[i].status = .opened
            }
            doc.activeTimelineID = timeline.id
        }
        app.logActivity(.captions, title: "Captions + framing: \(timeline.name)", detail: "\(timeline.captions?.words.count ?? 0) caption words · \(timeline.layout?.displayName ?? "Full Frame")")
        if open { self.open(timelineID: timeline.id) }
        return timeline.id
    }

    func makeMoreEntertaining(options: EntertainmentOptions = EntertainmentOptions()) {
        guard let timeline = activeTimeline else { return }
        let analysis = analysis(for: timeline)
        let sfx = document.media.filter { $0.role == .soundEffect }
        let music = document.media.first { $0.role == .music }
        var report = AIEditReport()
        editTimeline("Make More Entertaining") { t in
            report = EntertainmentEditor.apply(to: &t, analysis: analysis, options: options, soundEffects: sfx, music: music)
        }
        lastAIReport = report.summary
        app.logActivity(.autoEdit, title: "Made “\(timeline.name)” more entertaining", detail: report.summary)
        app.toast(report.summary)
    }

    func stripAI() {
        editTimeline("Remove AI Edits") { t in EntertainmentEditor.stripAIEdits(from: &t) }
    }

    /// Creates an AI clip + short from a transcript selection ("Create clip from sentence").
    func createClip(fromSource range: TimeRange, assetID: UUID) {
        guard let analysis = analyses[assetID] else { return }
        let generator = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: app.settings.ai.generationSettings)
        let candidate = generator.candidate(for: range)
        edit("Create Clip from Transcript") { doc in doc.candidates.append(candidate) }
        createShort(from: candidate.id)
    }

    /// Text-based editing: removes transcript words from the active timeline.
    func deleteTranscriptRange(_ range: TimeRange, assetID: UUID, text: String) {
        editTimeline("Delete “\(text.prefix(24))”") { t in
            t.removeSourceRanges([range], assetID: assetID, reason: .transcriptEdit, texts: [text])
        }
    }

    // MARK: Timeline commands

    var playhead: Seconds { playback.currentTime }

    func splitAtPlayhead() {
        let t = playhead
        editTimeline("Split") { timeline in
            let ids = selectedClipIDs.isEmpty ? nil : Array(selectedClipIDs)
            try timeline.split(at: t, clipIDs: ids)
        }
    }

    func deleteSelection(ripple: Bool) {
        guard !selectedClipIDs.isEmpty else { return }
        let ids = Array(selectedClipIDs)
        // The magnetic timeline closes gaps automatically.
        let shouldRipple = ripple || app.settings.magneticTimeline
        editTimeline(shouldRipple ? "Ripple Delete" : "Delete") { t in
            t.delete(clipIDs: ids, ripple: shouldRipple)
        }
        selectedClipIDs = []
    }

    func duplicateSelection() {
        let ids = Array(selectedClipIDs)
        guard !ids.isEmpty else { return }
        editTimeline("Duplicate") { t in
            let created = try t.duplicate(clipIDs: ids)
            selectedClipIDs = Set(created)
        }
    }

    func addMarker(name: String = "Marker") {
        let t = playhead
        editTimeline("Add Marker") { $0.markers.append(Marker(time: t, name: name, color: .blue)) }
    }

    func setSpeed(_ speed: Double) {
        let ids = Array(selectedClipIDs)
        editTimeline("Change Speed") { t in
            for id in ids { try t.setSpeed(clipID: id, speed: speed) }
        }
    }

    func detachAudio() {
        let ids = Array(selectedClipIDs)
        editTimeline("Detach Audio") { t in for id in ids { t.unlink(clipID: id) } }
    }

    func rippleDeleteInOut() {
        guard let a = inPoint, let b = outPoint, b > a else { return }
        editTimeline("Ripple Delete In→Out") { $0.rippleDelete(range: TimeRange(start: a, end: b)) }
        inPoint = nil
        outPoint = nil
    }

    func addText(_ text: String = "YOUR TITLE") {
        let t = playhead
        editTimeline("Add Text") { timeline in
            let trackID = timeline.freeTrack(kind: .text, for: TimeRange(start: t, duration: 3))
            var clip = TimelineClip(name: "Text", content: .text(TextElement(text: text, style: TextStyle(fontSize: 90, weight: .black, textCase: .uppercase, strokeWidth: 8))),
                                    start: t, sourceDuration: 3)
            clip.transform.positionY = AnimatedDouble(0.2)
            try timeline.insert(clip, onTrack: trackID)
            selectedClipIDs = [clip.id]
        }
    }

    /// Places a media asset at the playhead (video + linked audio).
    func placeAsset(_ assetID: UUID, at time: Seconds? = nil, trackID: UUID? = nil) {
        guard let asset = document.asset(id: assetID) else { return }
        let start = time ?? playhead
        let duration = asset.kind == .image ? 5 : max(asset.metadata.duration, 0.1)
        editTimeline("Add \(asset.name)") { t in
            let group = UUID()
            if asset.kind == .video || asset.kind == .image {
                let range = TimeRange(start: start, duration: duration)
                let vt = trackID.flatMap { id in t.tracks.first { $0.id == id && $0.kind == .video }?.id } ?? t.freeTrack(kind: .video, for: range)
                var video = TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: start, sourceDuration: duration,
                                         linkGroup: asset.metadata.hasAudio ? group : nil, role: asset.role == .webcam ? .webcam : (asset.role == .gameplay ? .gameplay : .main))
                video.transform.fit = .fill
                try t.insert(video, onTrack: vt)
            }
            if asset.metadata.hasAudio || asset.kind == .audio {
                let range = TimeRange(start: start, duration: duration)
                let at = t.freeTrack(kind: .audio, for: range)
                var audio = TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: start, sourceDuration: duration,
                                         linkGroup: asset.kind == .video ? group : nil, role: asset.role == .music ? .music : (asset.role == .soundEffect ? .soundEffect : .microphone))
                if asset.role == .music {
                    audio.audio.duckUnderDialogue = true
                    audio.audio.volume = AnimatedDouble(0.35)
                }
                try t.insert(audio, onTrack: at)
            }
        }
    }

    func newTimeline(canvas: CanvasSettings, name: String = "Timeline") {
        let timeline = Timeline.empty(name: name, canvas: canvas)
        edit("New Timeline") { $0.timelines.append(timeline) }
        open(timelineID: timeline.id)
    }

    func applyLayout(_ preset: LayoutPreset) {
        guard let timeline = activeTimeline else { return }
        let analysis = analysis(for: timeline)
        let assetID = timeline.origin?.assetID ?? timeline.assetIDs.first
        let size = assetID.flatMap { document.asset(id: $0)?.metadata.size } ?? Size2(1920, 1080)
        let context = LayoutContext(analysis: analysis, sourceSize: size)
        editTimeline("Layout: \(preset.displayName)") { t in
            if preset.usesWebcam, context.webcamRegion != nil, let assetID { LayoutEngine.ensureWebcamLayer(in: &t, assetID: assetID) }
            LayoutEngine.apply(preset == .dynamic ? .splitScreen : preset, to: &t, context: context)
            t.layout = preset
        }
    }

    func setCanvas(_ canvas: CanvasSettings) {
        guard let timeline = activeTimeline else { return }
        editTimeline("Change Aspect Ratio") { t in t.canvas = canvas }
        if let layout = timeline.layout { applyLayout(layout) }
    }

    func applyTemplate(_ template: ClipTemplate) {
        guard let timeline = activeTimeline else { return }
        let analysis = analysis(for: timeline)
        let assetID = timeline.origin?.assetID ?? timeline.assetIDs.first
        let size = assetID.flatMap { document.asset(id: $0)?.metadata.size } ?? Size2(1920, 1080)
        editTimeline("Apply Template “\(template.name)”") { t in
            if let preset = CanvasPreset.preset(id: template.canvasPresetID), preset.width != t.canvas.width || preset.height != t.canvas.height {
                t.canvas = preset.canvas(frameRate: t.canvas.frameRate)
            }
            template.apply(to: &t, context: LayoutContext(analysis: analysis, sourceSize: size))
        }
    }

    func saveTemplate(named name: String) {
        guard let timeline = activeTimeline else { return }
        let template = ClipTemplate.capture(from: timeline, name: name)
        edit("Save Template") { $0.templates.append(template) }
        app.addGlobalTemplate(template)
        app.toast("Saved template “\(name)”")
    }

    func applyAIResult(copy: ClipCopy, to timelineID: UUID) {
        edit("AI Titles") { doc in
            doc.updateTimeline(id: timelineID) { $0.copy = copy }
        }
    }
}
