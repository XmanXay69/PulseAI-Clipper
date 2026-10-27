import AppKit
import Combine
import Foundation
import PulseCore
import PulseEngine
import SwiftUI
import UniformTypeIdentifiers

enum EditTool: String, CaseIterable {
    case select, blade

    var symbol: String { self == .select ? "cursorarrow" : "scissors" }
    var shortcut: String { self == .select ? "A" : "B" }
}

enum LeftPanelTab: String, CaseIterable, Identifiable {
    case media, sounds, transcript, angles, effects, ai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .media: return "Media"
        case .sounds: return "Sounds"
        case .transcript: return "Transcript"
        case .angles: return "Angles"
        case .effects: return "Effects"
        case .ai: return "AI Tools"
        }
    }
    var symbol: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .sounds: return "music.note.list"
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
    /// The last Edit My VOD settings, so "Edit Again" (and ±10 %) can re-run them.
    var lastLongFormOptions: LongFormOptions?
    /// Excitement over source time per asset (for the strip on the timeline ruler), computed once on demand.
    @Published private(set) var energySignals: [UUID: EngagementSignals] = [:]
    private var energyRequests: Set<UUID> = []

    /// The asset's excitement curve if it's ready; kicks off the computation (off the main thread) if not.
    /// Predicted retention per recording (#490), from the engagement signals; nil until they're ready.
    func retentionCurve(for assetID: UUID) -> RetentionPredictor.Curve? {
        if let ready = retentionCurves[assetID] { return ready }
        guard let signals = energySignal(for: assetID), signals.step > 0 else { return nil }
        let curve = RetentionPredictor.predict(excitement: signals.excitement, step: signals.step)
        retentionCurves[assetID] = curve
        return curve
    }
    private var retentionCurves: [UUID: RetentionPredictor.Curve] = [:]

    func energySignal(for assetID: UUID) -> EngagementSignals? {
        if let ready = energySignals[assetID] { return ready }
        guard !energyRequests.contains(assetID), let analysis = analyses[assetID] else { return nil }
        energyRequests.insert(assetID)
        Task { [weak self] in
            let signals = await Task.detached(priority: .utility) { EngagementModel.compute(analysis: analysis) }.value
            await MainActor.run { self?.energySignals[assetID] = signals }
        }
        return nil
    }
    @Published var selectedCandidateIDs: Set<UUID> = []
    /// Series labels for the current set of cards (#66).
    var seriesCache: (key: Int, labels: [UUID: String])?
    /// The last Check Edit result, shown as a panel instead of an alert (#436).
    @Published var lastEditCheck: EditCheckReport?
    @Published var showEditCheck = false
    /// File → Project Settings… (#445).
    @Published var showProjectSettings = false
    /// Speed Edit (#500): keyboard-only pass over the recording's moments — N/P move, I/O mark, X makes a short.
    @Published var speedEdit = false
    @Published var speedEditIndex: Int?
    /// What dragging on the viewer does to the selected layer (#192): move/scale it, or pan and zoom its content.
    @Published var canvasTool: CanvasTool = .transform
    /// Waveform peaks per recording for the meters (#194, #281); not published — the meters read them on the clock.
    var meterPeaks: [UUID: [Float]] = [:]
    var meterPeaksLoading: Set<UUID> = []
    @Published var focusedCaptionWordID: UUID?
    /// Show only clips with this label; others dim (#177).
    @Published var labelFilter: MarkerColor?
    /// The rubber band being dragged on the timeline (#147), in content coordinates.
    @Published var marqueeRect: CGRect?
    /// The ruler is being scrubbed (#417).
    @Published var isScrubbing = false
    /// Where a dragged clip is snapping to right now (#144), in timeline seconds.
    @Published var snapLineTime: Seconds?

    /// Insert mode (#163): media added to the timeline pushes what follows instead of covering it.
    @Published var insertMode: Bool = UserDefaults.standard.bool(forKey: "timeline.insertMode") {
        didSet { UserDefaults.standard.set(insertMode, forKey: "timeline.insertMode") }
    }
    @Published var tool: EditTool = .select
    @Published var pixelsPerSecond: Double = 60
    @Published var inPoint: Seconds?
    @Published var outPoint: Seconds?
    /// The look/sound lifted off a clip with Copy Attributes (#165).
    @Published var copiedAttributes: ClipAttributes?

    var inOutRange: TimeRange? {
        guard let a = inPoint, let b = outPoint, b > a + 0.1 else { return nil }
        return TimeRange(start: a, end: b)
    }
    @Published var leftTab: LeftPanelTab = .media
    @Published var candidateSort: CandidateSort = .potential
    @Published var analysisProgress: [UUID: EngineProgress] = [:]
    /// Engagement curves per analyzed asset (the coach reads them on every edit).
    var signalCache: [UUID: EngagementSignals] = [:]
    /// A chat replay dropped in before its video finished importing.
    var pendingChat: ChatLog?
    /// Estimated seconds left for each running analysis.
    @Published var analysisRemaining: [UUID: Seconds] = [:]
    @Published var lastAIReport: String?
    /// Timelines we came from while inside compound clips (breadcrumb, outermost first).
    @Published var compoundPath: [UUID] = []

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var undoLabel: String?
    @Published private(set) var redoLabel: String?

    let playback = PlaybackController()
    /// Undo keeps up to 300 steps, but never more than roughly 60 big-timeline snapshots' worth (#397).
    private var history = History<ProjectDocument>(limit: 300, maxCost: 2_000_000, cost: ProjectSession.snapshotCost)

    /// Roughly how much a document snapshot costs to keep (clips weigh most, then caption words).
    nonisolated static func snapshotCost(_ doc: ProjectDocument) -> Int {
        var cost = doc.candidates.count * 5 + doc.media.count
        for timeline in doc.timelines {
            let clips: Int = timeline.allClips.count
            let words: Int = timeline.captions?.words.count ?? 0
            cost += clips * 20 + words
        }
        return cost
    }
    /// The transcript each asset had before its last re-analysis, so rebuilt captions can tell your edits from
    /// the machine's (#258).
    var previousTranscripts: [UUID: Transcript] = [:]
    /// Seconds of editing not yet written into the document (#477).
    var pendingEditingSeconds: Seconds = 0
    private var editingTimer: Timer?
    private var autosaveTask: Task<Void, Never>?
    private var snapshotDirty = false

    /// A step below the chosen viewer quality, set when playback can't keep up (#187); nil = the setting.
    @Published var playbackQualityOverride: PlaybackQuality?
    private var paceWatcher: AnyCancellable?

    var effectivePlaybackQuality: PlaybackQuality { playbackQualityOverride ?? app.settings.playbackQuality }

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
        registerMediaIdentities(document.media)
        reloadPlayback(debounce: 0)
        watchPlaybackPace()
        // An analysis that was running when PULSE quit picks up where it left off.
        let interrupted = document.media.filter { $0.preparation.analysisState == .running }.map(\.id)
        if !interrupted.isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self?.resumeInterruptedAnalyses(interrupted)
            }
        }
    }

    /// Restarts analyses that were cut off by quitting; finished stages come back from their checkpoints.
    func resumeInterruptedAnalyses(_ ids: [UUID]) {
        for id in ids {
            guard let asset = document.asset(id: id), analysisProgress[id] == nil else { continue }
            PulseLog.info("Resuming interrupted analysis: \(asset.name)")
            app.toast("Resuming the analysis of \(asset.name) where it left off")
            analyze(assetID: id, generateClips: document.candidates.allSatisfy { $0.assetID != id })
        }
    }

    /// Analysis state is saved right away (not an undo step) so an interrupted run can be resumed.
    func setAnalysisState(_ state: MediaPreparation.AnalysisState, for id: UUID) {
        guard let i = document.media.firstIndex(where: { $0.id == id }) else { return }
        document.media[i].preparation.analysisState = state
        isDirty = true
        save()
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

    /// The same edit on every selected clip (and the primary one) — one value on ten clips at once (#225).
    func editSelectedClips(primary: UUID, _ label: String, coalesce: String? = nil, _ body: @escaping (inout TimelineClip) -> Void) {
        let ids = selectedClipIDs.union([primary])
        guard ids.count > 1 else { return editClip(primary, label, coalesce: coalesce, body) }
        editTimeline(label, coalesce: coalesce ?? "clips-\(label)") { t in
            for id in ids { t.updateClip(id: id, body) }
        }
    }

    /// A marker named "Drop" at the playhead (#288): the music pulls out for a beat there.
    func addDropMarker() {
        let t = playback.currentTime
        editTimeline("Add Drop Marker") { timeline in
            timeline.markers.append(Marker(time: t, name: "Drop", color: .purple))
            timeline.markers.sort { $0.time < $1.time }
        }
    }

    /// Music drops at every "Drop" marker (#288).
    func applyDropMarkers() {
        var placed = 0
        editTimeline("Music Drops") { placed = EditPolish.applyDropMarkers(&$0) }
        app.toast(placed == 0 ? "Put a marker named “Drop” over the music first (Timeline → Add Music Drop Marker)" : "\(placed) music drop\(placed == 1 ? "" : "s") placed")
    }

    /// The thin "how much is left" bar along the bottom (#92), on or off.
    func toggleProgressBar() {
        guard let timeline = activeTimeline else { return }
        if ProgressBar.isPresent(timeline) {
            editTimeline("Remove Progress Bar") { ProgressBar.remove(&$0) }
        } else {
            var added = false
            let color = Theme.accent.rgba
            editTimeline("Add Progress Bar") { added = ProgressBar.add(&$0, color: color) }
            if !added { app.toast("A progress bar needs at least 10 seconds of video") }
        }
    }

    /// Colour label on the selected clips (#177); nil clears it.
    func setLabel(_ label: MarkerColor?) {
        let ids = selectedClipIDs
        guard !ids.isEmpty else { return }
        editTimeline(label.map { "Label \($0.displayName)" } ?? "Clear Label") { $0.setLabel(label, clipIDs: ids) }
    }

    /// Selects every clip carrying the label (#177).
    func selectClips(label: MarkerColor) {
        guard let timeline = activeTimeline else { return }
        selectedClipIDs = Set(timeline.clips(label: label).map(\.id))
    }

    /// One caption look for the whole project (#259).
    func applyCaptionStyleToAllShorts() {
        guard let id = activeTimeline?.id else { return }
        var count = 0
        edit("Caption Style to All Shorts") { count = $0.applyCaptionStyle(from: id) }
        app.toast(count == 0 ? "No other shorts with captions in this project" : "Applied this caption look to \(count) other short\(count == 1 ? "" : "s")")
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
        playback.audioScrub = app.settings.audioScrub
        playback.load(timeline: timeline, assets: assetsByID, compounds: document.compoundsByID,
                      useProxies: app.settings.proxy.useProxiesForPlayback, debounce: debounce,
                      renderScale: effectivePlaybackQuality.scale)
    }

    /// Viewer quality from the header menu (#187): clears any automatic drop and becomes the setting.
    func setPlaybackQuality(_ quality: PlaybackQuality) {
        playbackQualityOverride = nil
        app.settings.playbackQuality = quality
        reloadPlayback(debounce: 0)
    }

    /// When playback falls behind for a stretch, step the viewer down (if allowed) and say so once.
    private func watchPlaybackPace() {
        paceWatcher = playback.$isStruggling
            .removeDuplicates()
            .sink { [weak self] struggling in
                guard struggling, let self, self.app.settings.autoPlaybackQuality,
                      let lower = self.effectivePlaybackQuality.lower else { return }
                self.playbackQualityOverride = lower
                self.reloadPlayback(debounce: 0)
                PulseLog.info("Playback fell behind — viewer dropped to \(lower.longName.lowercased())")
                self.app.toast("Playback was falling behind, so the viewer dropped to \(lower.longName.lowercased()). Exports are unaffected — the viewer header has the switch.")
            }
    }

    /// Names each file by its content hash so thumbnails and waveforms survive a move or rename (#398).
    func registerMediaIdentities(_ assets: [MediaAsset]) {
        let pairs = assets.compactMap { asset -> (String, URL)? in
            guard let hash = asset.contentHash else { return nil }
            return (hash, url(for: asset))
        }
        guard !pairs.isEmpty else { return }
        Task.detached(priority: .utility) {
            for (hash, url) in pairs {
                await ThumbnailService.shared.register(identity: hash, for: url)
                await WaveformService.shared.register(identity: hash, for: url)
            }
        }
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
        if pendingEditingSeconds > 0 {
            document.editingSeconds += pendingEditingSeconds
            pendingEditingSeconds = 0
        }
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
        stopEditingClock()
        if isDirty || pendingEditingSeconds > 0 { save() }
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
        // Chat replays (Twitch / YouTube exports) attach to the main recording instead of becoming media.
        var urls = urls
        let chatFiles = urls.filter { ["json", "csv", "txt", "log"].contains($0.pathExtension.lowercased()) && Self.readChat($0) != nil }
        urls.removeAll { chatFiles.contains($0) }
        for url in chatFiles { importChat(url, for: nil) }
        if urls.isEmpty { return }
        let plan = ImportPlan.make(urls: urls, existingPaths: Set(document.media.map(\.path))).applying(app.settings.importPreset)
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
                    var asset = try await MediaImporter.makeAsset(for: item, cacheRoot: cacheRoot)
                    // The same recording under another name is caught by content, not path (#5).
                    asset.contentHash = try? ContentFingerprint.compute(url: item.url)
                    if let hash = asset.contentHash,
                       let twin = self.document.asset(contentHash: hash) ?? imported.first(where: { $0.contentHash == hash }) {
                        failures.append("\(item.url.lastPathComponent): the same recording is already in the project as “\(twin.name)”")
                        continue
                    }
                    imported.append(asset)
                } catch {
                    failures.append("\(item.url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                }
                job.progress = Double(i + 1) / Double(max(plan.items.count, 1))
            }
            if !imported.isEmpty {
                let syncGroup: UUID? = plan.isMultiSourceSession ? UUID() : nil
                self.registerMediaIdentities(imported)
                self.edit("Import Media") { doc in
                    for var asset in imported {
                        asset.syncGroupID = syncGroup
                        doc.media.append(asset)
                    }
                    if doc.primaryAssetID == nil {
                        doc.primaryAssetID = imported.first(where: { $0.kind == .video && ($0.role == .main || $0.role == .gameplay) })?.id ?? imported.first?.id
                    }
                    if let folder = plan.items.first?.url.deletingLastPathComponent().path { doc.lastImportFolder = folder }
                }
                self.save()
                if let chat = self.pendingChat, let main = self.document.primaryAsset {
                    self.pendingChat = nil
                    self.attachChat(chat, to: main.id)
                }
                // Offer proxies for heavy media.
                for asset in imported where asset.kind == .video && self.app.settings.proxy.shouldGenerateProxy(sourceHeight: asset.metadata.height, duration: asset.metadata.duration) {
                    self.generateProxy(assetID: asset.id)
                }
            }
            for url in plan.transcripts { self.importTranscript(url, for: nil) }
            // Chat replays found beside the recordings (#13); a `.json` that isn't chat is tried as a transcript.
            for url in plan.chatLogs {
                if Self.readChat(url) != nil { self.importChat(url, for: nil) } else if url.pathExtension.lowercased() == "json" { self.importTranscript(url, for: nil) }
            }
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

    // MARK: Chat replay

    static func readChat(_ url: URL) -> ChatLog? {
        guard let data = try? Data(contentsOf: url), data.count < 400_000_000 else { return nil }
        return try? ChatReplayParser.parse(data, fileName: url.lastPathComponent)
    }

    /// Adds a Twitch / YouTube chat replay to a recording; clips are re-scored with it.
    func importChat(_ url: URL, for assetID: UUID?) {
        guard let chat = Self.readChat(url) else {
            app.present(ChatParseError.unrecognized, title: "Couldn't read the chat replay")
            return
        }
        PulseLog.info("Chat replay imported: \(chat.messages.count) messages (\(chat.format))")
        guard let target = assetID ?? document.primaryAsset?.id else {
            pendingChat = chat
            app.toast("Chat replay ready — it'll attach to the video once it's imported")
            return
        }
        attachChat(chat, to: target)
    }

    func attachChat(_ chat: ChatLog, to assetID: UUID) {
        var analysis = analyses[assetID] ?? MediaAnalysis(assetID: assetID, duration: document.asset(id: assetID)?.metadata.duration ?? (chat.messages.last?.time ?? 0))
        analysis.chat = chat
        setAnalysis(analysis)
        signalCache[assetID] = nil
        app.logActivity(.analysis, title: "Chat replay added", detail: "\(chat.messages.count) messages · \(chat.format)")
        if analysis.audio != nil || analysis.transcript != nil {
            app.toast("Chat replay added (\(chat.messages.count) messages) — re-scoring clips with it")
            generateCandidates(assetID: assetID)
        } else {
            app.toast("Chat replay added (\(chat.messages.count) messages) — it'll be used when the video is analyzed")
        }
    }

    /// Moves the chat earlier/later when it doesn't line up with the video (e.g. the VOD was trimmed).
    func shiftChat(by seconds: Seconds, assetID: UUID) {
        guard var analysis = analyses[assetID], var chat = analysis.chat else { return }
        chat.offset += seconds
        analysis.chat = chat
        setAnalysis(analysis)
        signalCache[assetID] = nil
        app.toast(String(format: "Chat offset %+.0f s", chat.offset))
    }

    func removeChat(assetID: UUID) {
        guard var analysis = analyses[assetID], analysis.chat != nil else { return }
        analysis.chat = nil
        setAnalysis(analysis)
        signalCache[assetID] = nil
        app.toast("Chat replay removed")
    }

    func setAnalysis(_ analysis: MediaAnalysis) {
        if let old = analyses[analysis.assetID]?.transcript, old != analysis.transcript { previousTranscripts[analysis.assetID] = old }
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

    /// Selects every clip the rubber band touches (#147); ⇧ adds to the selection.
    func selectClips(inContentRect rect: CGRect, laneTop: CGFloat, laneHeight: (TrackKind) -> CGFloat, pps: CGFloat, extend: Bool) {
        guard let timeline = activeTimeline, pps > 0 else { return }
        let t0 = Double(rect.minX / pps), t1 = Double(rect.maxX / pps)
        var hits = Set<UUID>()
        var y = laneTop
        for track in timeline.tracks {
            let h = laneHeight(track.kind)
            if rect.minY < y + h, rect.maxY > y {
                for clip in track.clips where clip.end > t0 && clip.start < t1 { hits.insert(clip.id) }
            }
            y += h
        }
        selectedClipIDs = extend ? selectedClipIDs.union(hits) : hits
    }

    // MARK: Slip / slide / roll (#143)

    var primarySelectedClip: TimelineClip? {
        guard let timeline = activeTimeline else { return nil }
        return selectedClipIDs.compactMap { timeline.clip(id: $0) }.min { $0.start < $1.start }
    }

    func frameSeconds(_ frames: Int) -> Seconds { Double(frames) / max(playback.frameRate, 1) }

    /// Moves what plays inside the selected clip, not the clip.
    func slipSelection(frames: Int) {
        guard let clip = primarySelectedClip else { return app.toast("Select a clip to slip") }
        let media = clip.assetID.flatMap { document.asset(id: $0) }?.metadata.duration
        let delta = frameSeconds(frames)
        editTimeline("Slip", coalesce: "slip-\(clip.id)") { try $0.slip(clipID: clip.id, by: delta, mediaDuration: media) }
    }

    /// Moves the selected clip between its neighbours; they give or take the room.
    func slideSelection(frames: Int) {
        guard let clip = primarySelectedClip else { return app.toast("Select a clip to slide") }
        let delta = frameSeconds(frames)
        editTimeline("Slide", coalesce: "slide-\(clip.id)") { try $0.slide(clipID: clip.id, by: delta) }
    }

    /// Moves the cut after the selected clip.
    func rollSelection(frames: Int) {
        guard let clip = primarySelectedClip else { return app.toast("Select the clip before the cut to roll") }
        let media = clip.assetID.flatMap { document.asset(id: $0) }?.metadata.duration
        let delta = frameSeconds(frames)
        editTimeline("Roll", coalesce: "roll-\(clip.id)") { try $0.roll(edgeAfter: clip.id, by: delta, mediaDuration: media) }
    }

    /// Drop a media item onto a clip (#164): the clip keeps its place and length, the file behind it changes.
    func replaceClip(_ clipID: UUID, with assetID: UUID) {
        guard let asset = document.asset(id: assetID), asset.kind != .image else { return }
        let duration = max(asset.metadata.duration, 0.1)
        let hasAudio = asset.metadata.hasAudio || asset.kind == .audio
        editTimeline("Replace Clip") { $0.replaceContent(clipID: clipID, assetID: assetID, assetDuration: duration, name: asset.name, hasAudio: hasAudio) }
    }

    /// Relinks every missing file found under `folder` by name (and size when names repeat) (#7).
    func relinkMissingMedia(in folder: URL) {
        let missing = document.media.filter { $0.availability == .missing }
        guard !missing.isEmpty else { return }
        app.jobs.start("Looking for \(missing.count) missing file\(missing.count == 1 ? "" : "s")", kind: .importMedia) { [weak self] job in
            guard let self else { return }
            let wanted = Set(missing.map { ($0.path as NSString).lastPathComponent.lowercased() })
            let candidates = await Task.detached(priority: .userInitiated) { () -> [MediaRelinker.Candidate] in
                var out: [MediaRelinker.Candidate] = []
                let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isPackageKey]
                guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
                for case let url as URL in walker {
                    guard wanted.contains(url.lastPathComponent.lowercased()),
                          let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                    out.append(MediaRelinker.Candidate(path: url.path, size: Int64(values.fileSize ?? 0)))
                    if out.count > 5_000 { break }
                }
                return out
            }.value
            let matches = MediaRelinker.matches(missing: missing, files: candidates)
            guard !matches.isEmpty else {
                self.app.toast("None of the missing files are in \(folder.lastPathComponent)")
                return
            }
            self.edit("Relink Media") { doc in
                for (id, path) in matches {
                    let url = URL(fileURLWithPath: path)
                    doc.updateAsset(id: id) {
                        $0.path = url.path
                        $0.bookmark = MediaAccess.bookmark(for: url)
                        $0.availability = .online
                    }
                }
            }
            self.save()
            self.app.toast("Relinked \(matches.count) of \(missing.count) missing file\(missing.count == 1 ? "" : "s")")
            job.progress = 1
        }
    }

    /// On open (#6): missing files are looked for where they used to be, one folder up, beside the project
    /// and in the last import folder — quietly, without a scan of the whole disk.
    func autoRelinkMissing() {
        let missing = document.media.filter { $0.availability == .missing }
        guard !missing.isEmpty else { return }
        let projectFolder = package.url.deletingLastPathComponent().path
        let lastImport = document.lastImportFolder
        Task { @MainActor [weak self] in
            guard let self else { return }
            var candidates: [MediaRelinker.Candidate] = []
            var roots: [String] = []
            for asset in missing { for root in MediaRelinker.searchRoots(for: asset, projectFolder: projectFolder, lastImportFolder: lastImport) where !roots.contains(root) { roots.append(root) } }
            let wanted = Set(missing.map { ($0.path as NSString).lastPathComponent.lowercased() })
            for root in roots.prefix(12) {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
                for name in names where wanted.contains(name.lowercased()) {
                    let path = (root as NSString).appendingPathComponent(name)
                    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                    candidates.append(MediaRelinker.Candidate(path: path, size: size))
                }
            }
            let matches = MediaRelinker.matches(missing: missing, files: candidates)
            guard !matches.isEmpty else { return }
            self.edit("Relink Media") { doc in
                for (id, path) in matches {
                    let url = URL(fileURLWithPath: path)
                    doc.updateAsset(id: id) {
                        $0.path = url.path
                        $0.bookmark = MediaAccess.bookmark(for: url)
                        $0.availability = .online
                    }
                }
            }
            self.save()
            self.app.toast("Found \(matches.count) moved file\(matches.count == 1 ? "" : "s") and relinked \(matches.count == 1 ? "it" : "them")")
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

    func analyze(assetID: UUID, generateClips: Bool = true, then followUp: (@MainActor () -> Void)? = nil) {
        guard let asset = document.asset(id: assetID) else { return }
        // Analysis writes a 16 kHz WAV, proxies and thumbnails: make sure the cache disk has room first.
        let needed = Int64(max(asset.metadata.duration, 60) * 32_000) + (1 << 30)
        do {
            try DiskSpace.ensure(needed, at: app.cacheFolder)
        } catch {
            app.presentMessage(title: "Not enough disk space to analyze",
                               message: "Free about \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) on the disk holding PULSE's cache (Settings → Files & Storage), then try again.")
            return
        }
        let ai = app.settings.ai
        let imported = analyses[assetID]?.transcript
        let voice = voiceCompanion(for: asset).map { AnalysisPipeline.VoiceSource(main: asset, voice: $0) }
        let options = AnalysisPipeline.Options(transcribe: true, detectFaces: true, ai: ai, importedTranscript: imported, voiceSource: voice,
                                               speed: ai.analysisSpeed)
        let pipeline = AnalysisPipeline(cacheDirectory: PulseDirectories.cache("Analysis", root: app.cacheFolder))
        setAnalysisState(.running, for: assetID)
        let job = app.jobs.start("Analyze · \(asset.name)", kind: .analysis) { [weak self] job in
            guard let self else { return }
            do {
                let output = try await pipeline.run(asset: asset, options: options, progress: { p in
                    Task { @MainActor [weak self] in
                        job.progress = p.fraction
                        job.detail = p.stage
                        self?.analysisProgress[assetID] = p
                        self?.analysisRemaining[assetID] = job.remaining
                    }
                }, isCancelled: job.isCancelledCheck)
                self.analysisProgress[assetID] = nil
                self.analysisRemaining[assetID] = nil
                if !output.resumedStages.isEmpty {
                    PulseLog.info("Analysis resumed; reused: \(output.resumedStages.map(\.rawValue).joined(separator: ", "))")
                }
                // Learn this Mac's speed so the next estimate is closer.
                self.app.settings.ai.analysisSpeed.learn(stageSeconds: output.stageSeconds, mediaDuration: asset.metadata.duration)
                var analysis = output.analysis
                analysis.chat = self.analyses[assetID]?.chat // an imported chat replay survives re-analysis
                // Moments marked while recording are sure things: they score like a win banner.
                let marked = self.document.asset(id: assetID)?.markedMoments ?? []
                if !marked.isEmpty {
                    analysis.hudEvents = (analysis.hudEvents ?? []) + marked.map { HUDEvent(time: $0, kind: .marked, text: "CLIP IT") }
                }
                self.setAnalysis(analysis)
                self.edit("Analyze Video") { doc in
                    doc.updateAsset(id: assetID) { $0.preparation.analysisState = .complete }
                }
                self.app.settings.stats.note { $0.secondsAnalyzed += analysis.duration }
                let location = output.analysis.processing["transcript"] ?? .local
                self.app.logActivity(.analysis, title: "Analyzed \(asset.name)", detail: output.warnings.first ?? "Audio, video and faces", location: .local)
                if output.analysis.transcript != nil {
                    self.app.logActivity(.transcription, title: "Transcribed \(asset.name)", detail: "\(output.analysis.transcript?.words.count ?? 0) words", location: location)
                }
                if !output.warnings.isEmpty {
                    self.app.presentMessage(title: "Analysis finished with notes", message: output.warnings.joined(separator: "\n\n"))
                }
                if let followUp { followUp() } else if generateClips { self.generateCandidates(assetID: assetID) }
            } catch {
                self.analysisProgress[assetID] = nil
                self.analysisRemaining[assetID] = nil
                // Cancelled or failed: a later "Analyze" (or relaunch) resumes from the checkpoints.
                self.setAnalysisState(.failed, for: assetID)
                throw error
            }
        }
        let expected = options.estimate(for: asset).total
        job.expect(expected)
        analysisRemaining[assetID] = expected
    }

    /// How long analyzing this asset should take on this Mac.
    func analysisEstimate(for asset: MediaAsset) -> Seconds {
        let voice = voiceCompanion(for: asset).map { AnalysisPipeline.VoiceSource(main: asset, voice: $0) }
        return AnalysisPipeline.Options(ai: app.settings.ai, importedTranscript: analyses[asset.id]?.transcript, voiceSource: voice,
                                        speed: app.settings.ai.analysisSpeed).estimate(for: asset).total
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
            let taste = self.app.settings.ai.taste
            let candidates = await Task.detached(priority: .userInitiated) {
                ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: settings).generate()
                    .applyingTaste(taste).sorted { $0.potential > $1.potential }
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

    /// 👍 / 👎 on a clip: teaches your taste profile and re-ranks every clip with it.
    func rateCandidate(_ id: UUID, liked: Bool?) {
        guard let candidate = document.candidates.first(where: { $0.id == id }) else { return }
        var taste = app.settings.ai.taste
        if let old = candidate.feedback { taste.forget(liked: old > 0) }
        if let liked { taste.learn(scores: candidate.scores, tags: candidate.tags, liked: liked) }
        app.settings.ai.taste = taste
        edit(liked == nil ? "Clear Rating" : (liked! ? "Like Clip" : "Dislike Clip")) { doc in
            if let i = doc.candidates.firstIndex(where: { $0.id == id }) { doc.candidates[i].feedback = liked.map { $0 ? 1 : -1 } }
            doc.candidates = doc.candidates.applyingTaste(taste)
        }
        if liked != nil { app.settings.stats.note { $0.momentsRated += 1 } }
        PulseLog.info("Clip rated \(liked.map { $0 ? "up" : "down" } ?? "cleared") — taste now from \(taste.ratings) ratings")
    }

    /// "Never show moments like this" (#52): a 👎 that weighs three times as much, and the card goes to Maybe later.
    func neverCandidate(_ id: UUID) {
        guard let candidate = document.candidates.first(where: { $0.id == id }) else { return }
        var taste = app.settings.ai.taste
        if let old = candidate.feedback, old != -2 { taste.forget(liked: old > 0) }
        if candidate.feedback != -2 { taste.never(scores: candidate.scores, tags: candidate.tags) }
        app.settings.ai.taste = taste
        app.settings.stats.note { $0.momentsRated += 1 }
        edit("Never Like This") { doc in
            if let i = doc.candidates.firstIndex(where: { $0.id == id }) {
                doc.candidates[i].feedback = -2
                doc.candidates[i].status = .dismissed
            }
            doc.candidates = doc.candidates.applyingTaste(taste)
        }
        selectedCandidateIDs.remove(id)
        app.toast("Got it — moments like “\(candidate.title)” will score lower from now on")
    }

    /// Three more titles in the spirit of the current one (#60).
    func moreTitles(for id: UUID) {
        guard let candidate = document.candidates.first(where: { $0.id == id }) else { return }
        let words = analyses[candidate.assetID]?.transcript?.words.filter { $0.start >= candidate.range.start - 2 && $0.end <= candidate.range.end + 2 } ?? []
        let more = TitleGenerator.moreLike(candidate.title, words: words, payoff: candidate.payoffTime, tags: candidate.tags,
                                           seed: candidate.generation + candidate.copy.titles.count, avoiding: candidate.copy.titles)
        guard !more.isEmpty else { app.toast("No more titles in that spirit — try Regenerate"); return }
        edit("More Titles") { doc in
            guard let i = doc.candidates.firstIndex(where: { $0.id == id }) else { return }
            doc.candidates[i].copy.titles = Array((doc.candidates[i].copy.titles + more).suffix(9))
        }
    }

    /// The hashtags you typed for a card (#72).
    func setHashtags(_ text: String, for id: UUID) {
        let tags = Hashtags.parse(text)
        edit("Edit Hashtags") { doc in
            guard let i = doc.candidates.firstIndex(where: { $0.id == id }) else { return }
            doc.candidates[i].copy.hashtags = tags
        }
    }

    /// "Part 1/2" labels for moments that belong together (#66), cached per set of cards.
    var seriesLabels: [UUID: String] {
        let visible = document.visibleCandidates
        var hasher = Hasher()
        for c in visible { hasher.combine(c.id); hasher.combine(c.range.start) }
        let words = document.primaryAsset.flatMap { analyses[$0.id]?.transcript?.words } ?? []
        hasher.combine(words.count)
        let key = hasher.finalize()
        if let cached = seriesCache, cached.key == key { return cached.labels }
        let labels = SeriesDetector.partLabels(SeriesDetector.series(candidates: visible, words: words))
        seriesCache = (key, labels)
        return labels
    }

    /// Two or more moments as one short (#65): each is cut the one-click way, then they're joined with a cut.
    func mergeCandidates(_ ids: Set<UUID>) {
        let picked = document.candidates.filter { ids.contains($0.id) && $0.status != .dismissed }.sorted { $0.range.start < $1.range.start }
        guard picked.count >= 2 else { return }
        var merged: Timeline?
        var built = 0
        for candidate in picked {
            guard let piece = buildShort(for: candidate, mode: .oneClick, style: nil) else { continue }
            var timeline = piece.timeline
            if built > 0 {
                // Only the first piece keeps the hook marker; the join is a plain cut.
                timeline.markers.removeAll { $0.name == "Hook" }
            }
            if merged == nil { merged = timeline } else { merged?.append(timeline) }
            built += 1
        }
        guard var timeline = merged, built >= 2 else { return }
        var card = picked.dropFirst().reduce(picked[0]) { ClipCandidate.merged($0, $1) }
        timeline.name = "\(picked[0].title) + \(picked.count - 1) more"
        timeline.id = UUID()
        card.timelineID = timeline.id
        card.status = .opened
        let cardID = card.id
        edit("Merge Moments") { doc in
            doc.timelines.append(timeline)
            doc.candidates.insert(card, at: doc.candidates.firstIndex(where: { $0.id == picked[0].id }) ?? 0)
            doc.activeTimelineID = timeline.id
        }
        selectedCandidateIDs = [cardID]
        app.settings.stats.note { $0.shortsBuilt += 1 }
        app.logActivity(.autoEdit, title: "Merged \(picked.count) moments into “\(timeline.name)”", detail: Timecode.duration(timeline.duration))
        open(timelineID: timeline.id)
        app.toast("\(picked.count) moments joined — \(Timecode.duration(timeline.duration)); trim the join on the timeline if you like")
    }

    /// What tightening pauses would save on the active timeline (#82).
    func pauseEstimate(minimum: Seconds) -> (pauses: Int, saved: Seconds) {
        guard let timeline = activeTimeline, let words = pauseWords(for: timeline) else { return (0, 0) }
        return EditPolish.pauseRemovalEstimate(timeline, words: words, minimum: minimum)
    }

    func tightenPauses(minimum: Seconds) {
        guard let timeline = activeTimeline, let words = pauseWords(for: timeline) else { return }
        autoSnapshot("Before Tighten Pauses")
        var removed = 0
        var saved: Seconds = 0
        editTimeline("Tighten Pauses") { t in
            let before = t.duration
            removed = EditPolish.shortenPauses(&t, words: words, after: 0, minimum: minimum)
            saved = before - t.duration
        }
        app.toast(removed == 0 ? "No pauses longer than \(String(format: "%.1f", minimum)) s" : "\(removed) pause\(removed == 1 ? "" : "s") sped up — \(String(format: "%.1f", saved)) s shorter", undo: removed > 0)
    }

    func pauseWords(for timeline: Timeline) -> [TranscriptWord]? {
        guard let assetID = timeline.tracks.first(where: { $0.kind == .video })?.clips.first(where: { $0.role != .graphic })?.content.assetID,
              let words = analyses[assetID]?.transcript?.words, !words.isEmpty else { return nil }
        return words
    }

    /// Counts a minute of editing whenever PULSE is in front with this project open (#477).
    func startEditingClock() {
        editingTimer?.invalidate()
        editingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, NSApp.isActive else { return }
                self.pendingEditingSeconds += 60
                if self.pendingEditingSeconds >= 300 && !self.isDirty { self.save() }
            }
        }
    }

    func stopEditingClock() {
        editingTimer?.invalidate()
        editingTimer = nil
    }

    /// The selected clip takes the look of the clip before it on its track (#226).
    func matchPreviousClip() {
        let ids = selectedClipIDs
        guard !ids.isEmpty else { return }
        var matched = 0
        editTimeline("Match Previous Clip") { t in
            for id in ids where t.matchPrevious(clipID: id) { matched += 1 }
        }
        app.toast(matched == 0 ? "Nothing before the selected clip on its track" : "\(matched) clip\(matched == 1 ? "" : "s") now look like the one before")
    }

    /// The frame under the playhead becomes the export thumbnail (#70).
    func setCoverFrame() {
        let time = playhead
        editTimeline("Set Cover Frame") { $0.coverTime = time }
        app.toast("Cover frame set at \(Timecode.short(time)) — exports use it for the thumbnail")
    }

    /// Captions rebuilt from the newest transcript, keeping your fixes (#258).
    func rebuildCaptionsKeepingFixes() {
        guard let timeline = activeTimeline, let old = timeline.captions,
              let transcript = analyses[old.sourceAssetID]?.transcript else { app.toast("No transcript to rebuild from yet"); return }
        let range = timeline.tracks.flatMap(\.clips).filter { $0.content.assetID == old.sourceAssetID }.map(\.sourceRange).merged()
        guard let start = range.first?.start, let end = range.last?.end else { return }
        let previous = previousTranscripts[old.sourceAssetID]
        editTimeline("Rebuild Captions") { t in
            t.captions = CaptionTrack.rebuilt(from: transcript, range: TimeRange(start: start, end: end), assetID: old.sourceAssetID,
                                              keeping: old, previous: previous, emphasize: true)
        }
        app.toast("Captions rebuilt from the latest transcript — your edits were kept")
    }

    /// Timeline → Export Chapter Art… (#493): one 1280×720 PNG per chapter marker, the frame with its name over it.
    func exportChapterArt() {
        guard let timeline = activeTimeline else { return }
        let chapters = timeline.markers.filter { $0.color == .blue }
        guard !chapters.isEmpty else { return app.toast("Add chapter markers first — blue markers become chapters") }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "A folder for \(chapters.count) chapter picture\(chapters.count == 1 ? "" : "s")"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let assets = Dictionary(uniqueKeysWithValues: document.media.map { ($0.id, $0) })
        app.jobs.start("Chapter art for \(timeline.name)", kind: .export) { [weak self] job in
            guard let self else { return }
            let result = try await ChapterArt.render(timeline: timeline, assets: assets, into: folder) { p in Task { @MainActor in job.progress = p } }
            self.app.logActivity(.export, title: "Chapter art for “\(timeline.name)”", detail: "\(result.files.count) pictures")
            self.app.toast(result.skipped > 0 ? "\(result.files.count) chapter pictures saved · \(result.skipped) marker\(result.skipped == 1 ? "" : "s") sat over a cutaway and were skipped" : "\(result.files.count) chapter pictures saved")
            NSWorkspace.shared.open(folder)
        }
    }

    /// A review page for someone without PULSE (#471).
    func exportReviewPage() {
        guard let timeline = activeTimeline else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportSettings.cleanComponent(timeline.name) + " review.html"
        panel.allowedContentTypes = [.html]
        panel.prompt = "Save Page"
        panel.message = "One HTML file: the cut with timecodes, chapters, what was removed and your notes. Works offline, prints."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = ReviewPage.html(timeline: timeline, projectName: document.name, assets: document.media)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            app.logActivity(.export, title: "Review page for “\(timeline.name)”", detail: url.lastPathComponent)
            app.toast("Saved \(url.lastPathComponent)")
            NSWorkspace.shared.open(url)
        } catch {
            app.present(error, title: "Couldn't write the review page")
        }
    }

    /// What the edit did, with jump links (#107).
    var editReport: EditReport? { activeTimeline.map { EditReport.build(timeline: $0, assets: document.media) } }

    /// The timeline as Final Cut Pro XML for Final Cut Pro or DaVinci Resolve (#480).
    func exportFCPXML() {
        guard let timeline = activeTimeline else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportSettings.cleanComponent(timeline.name) + ".fcpxml"
        panel.allowedContentTypes = [UTType(filenameExtension: "fcpxml") ?? .xml]
        panel.prompt = "Export XML"
        panel.message = "The cut, titles and markers go to Final Cut Pro or Resolve; zooms, grades, captions and effects stay in PULSE."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let xml = FCPXMLExporter.xml(timeline: timeline, assets: document.media, projectName: document.name, compounds: document.compoundsByID)
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            app.logActivity(.export, title: "Exported “\(timeline.name)” as Final Cut Pro XML", detail: url.lastPathComponent)
            app.toast("Saved \(url.lastPathComponent) — open it in Final Cut Pro or Resolve")
        } catch {
            app.present(error, title: "Couldn't write the XML")
        }
    }

    /// Remembers that you bolded (or un-bolded) this word, so new captions follow (#238).
    func learnEmphasis(_ word: CaptionWord) {
        let key = TranscriptWord.normalize(word.text)
        guard key.count >= 2 else { return }
        let delta = word.isEmphasized ? -1 : 1
        app.settings.ai.emphasisLearned[key] = ((app.settings.ai.emphasisLearned[key] ?? 0) + delta).clamped(-5, 5)
        if app.settings.ai.emphasisLearned[key] == 0 { app.settings.ai.emphasisLearned.removeValue(forKey: key) }
    }

    /// An SRT / VTT for the main recording becomes this timeline's captions (#247); they sit in source time, so
    /// the cut re-times them.
    func importCaptionsFile() {
        guard let timeline = activeTimeline,
              let assetID = timeline.tracks.first(where: { $0.kind == .video })?.clips.first(where: { $0.role != .graphic })?.content.assetID else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["srt", "vtt", "json"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose captions for the main recording (SRT, WebVTT or Whisper JSON)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let transcript = try TranscriptParser.parse(data: Data(contentsOf: url), fileExtension: url.pathExtension)
            let sourceRanges = timeline.allClips.filter { $0.content.assetID == assetID }.map(\.sourceRange).merged()
            guard let start = sourceRanges.first?.start, let end = sourceRanges.last?.end else { return }
            let style = timeline.captions?.style ?? CaptionStyle.preset(named: document.overrides.captionPresetName ?? app.settings.ai.captionPresetName) ?? .tiktok
            editTimeline("Import Captions") { t in
                t.captions = CaptionTrack.make(from: transcript, range: TimeRange(start: start, end: end), assetID: assetID, style: style, emphasize: false, aiGenerated: false)
            }
            app.toast("Imported \(transcript.words.count) caption words from \(url.lastPathComponent)")
        } catch {
            app.present(error, title: "Couldn't read the captions")
        }
    }

    /// This stretch transcribed again (#42) with the current engine and vocabulary; the rest stays.
    func retranscribe(range: TimeRange, assetID: UUID) {
        guard let asset = document.asset(id: assetID), var analysis = analyses[assetID], let transcript = analysis.transcript else { return }
        let settings = app.settings.ai
        let voice = voiceCompanion(for: asset).map { url(for: $0) }
        app.jobs.start("Re-transcribing \(Timecode.duration(range.duration))", kind: .transcription) { [weak self] job in
            guard let self else { return }
            job.detail = Timecode.short(range.start)
            do {
                var words = try await Retranscriber.transcribe(asset: asset, range: range, settings: settings, voiceSource: voice)
                if !settings.customVocabulary.isEmpty {
                    words = TranscriptCorrector.correct(Transcript(language: transcript.language, words: words, source: transcript.source), vocabulary: settings.customVocabulary).transcript.words
                }
                analysis.transcript = transcript.replacingWords(in: range, with: words)
                self.setAnalysis(analysis)
                self.app.logActivity(.transcription, title: "Re-transcribed \(Timecode.duration(range.duration)) of \(asset.name)", detail: "\(words.count) words")
                self.app.toast("Re-transcribed that stretch — \(words.count) words")
            } catch {
                self.app.present(error, title: "Couldn't re-transcribe")
            }
        }
    }

    /// One channel through both ears on every clip of this recording (#272).
    func applyMonoSource(assetID: UUID, source: MonoSource) {
        var changed = 0
        edit("Mono Source") { doc in
            for ti in doc.timelines.indices {
                for tr in doc.timelines[ti].tracks.indices where doc.timelines[ti].tracks[tr].kind == .audio {
                    for ci in doc.timelines[ti].tracks[tr].clips.indices where doc.timelines[ti].tracks[tr].clips[ci].content.assetID == assetID {
                        doc.timelines[ti].tracks[tr].clips[ci].audio.monoSource = source
                        changed += 1
                    }
                }
            }
        }
        app.toast(changed == 0 ? "No clips of this recording on a timeline yet — set Channels in the clip's Audio section later" : "\(changed) clip\(changed == 1 ? "" : "s") now play the \(source == .left ? "left" : "right") channel through both ears", undo: changed > 0)
    }

    /// Media out of the panel but not gone (#22).
    func trashMedia(_ id: UUID) {
        guard let asset = document.asset(id: id) else { return }
        edit("Trash Media") { $0.trashMedia(id: id) }
        app.toast("“\(asset.name)” moved to the media trash — its clips still play", undo: true)
    }

    func restoreMedia(_ id: UUID) {
        edit("Restore Media") { $0.restoreMedia(id: id) }
    }

    func emptyMediaTrash() {
        var gone: [MediaAsset] = []
        edit("Empty Media Trash") { gone = $0.emptyMediaTrash() }
        app.toast(gone.isEmpty ? "Everything in the trash is still used by a timeline" : "Removed \(gone.count) file\(gone.count == 1 ? "" : "s") from the project", undo: !gone.isEmpty)
    }

    /// Every undo step, oldest first (#175).
    var undoLabels: [String] { history.labels }

    /// Jumps back `steps` edits (#175).
    func undo(steps: Int) {
        for _ in 0..<max(0, steps) { undo() }
    }

    /// Trims the project to the media it uses (#469); the files stay on disk.
    func removeUnusedMedia() {
        let unused = document.unusedMedia
        guard !unused.isEmpty else { app.toast("Every file in the project is in use"); return }
        var gone: [MediaAsset] = []
        edit("Remove Unused Media") { doc in gone = doc.removeUnusedMedia() }
        app.toast("Removed \(gone.count) unused file\(gone.count == 1 ? "" : "s") from the project — \(gone.map(\.name).prefix(3).joined(separator: ", "))\(gone.count > 3 ? "…" : "")", undo: true)
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
        app.toast(ids.count == 1 ? "Clip set aside — it's in Maybe later" : "\(ids.count) clips set aside", undo: true)
    }

    /// One-click short / Auto Edit: builds an editable timeline and opens it.
    @discardableResult
    func createShort(from candidateID: UUID, mode: ShortBuildOptions.Mode = .oneClick, open: Bool = true,
                     style: (ReferenceStyle, ReferenceAnswers)? = nil) -> UUID? {
        guard let candidate = document.candidates.first(where: { $0.id == candidateID }),
              let asset = document.asset(id: candidate.assetID) else { return nil }
        if let existing = candidate.timelineID, document.timeline(id: existing) != nil, mode == .oneClick, style == nil {
            if open { self.open(timelineID: existing) }
            return existing
        }
        guard let built = buildShort(for: candidate, mode: mode, style: style) else { return nil }
        let (timeline, wantsMusic, options, music, sfx) = (built.timeline, built.wantsMusic, built.options, built.music, built.sfx)
        edit(mode == .autoEdit ? "Auto Edit Short" : "Create Short") { doc in
            doc.timelines.append(timeline)
            if let i = doc.candidates.firstIndex(where: { $0.id == candidateID }) {
                doc.candidates[i].timelineID = timeline.id
                doc.candidates[i].status = .opened
            }
            doc.activeTimelineID = timeline.id
        }
        app.logActivity(.captions, title: "Captions + framing: \(timeline.name)", detail: "\(timeline.captions?.words.count ?? 0) caption words · \(timeline.layout?.displayName ?? "Full Frame")")
        // No music / effects of the project's own: use the built-in library.
        addLibraryAudio(toShort: timeline.id, music: wantsMusic && music == nil, effects: options.soundEffects && sfx.isEmpty)
        autoApplyBrandKit(to: timeline.id)
        app.settings.stats.note { $0.shortsBuilt += 1 }
        if open { self.open(timelineID: timeline.id) }
        return timeline.id
    }

    /// The short for a card, built but not added to the project.
    func buildShort(for candidate: ClipCandidate, mode: ShortBuildOptions.Mode, style: (ReferenceStyle, ReferenceAnswers)?)
        -> (timeline: Timeline, wantsMusic: Bool, options: ShortBuildOptions, music: MediaAsset?, sfx: [MediaAsset])? {
        guard let asset = document.asset(id: candidate.assetID) else { return nil }
        var options = ShortBuildOptions(settings: app.settings.ai, mode: mode)
        let platform = document.overrides.safeAreaPlatform ?? app.settings.safeAreaPlatform
        options.canvasPresetID = platform == .youtubeShorts ? CanvasPreset.shorts.id : (platform == .instagramReels ? CanvasPreset.reels.id : CanvasPreset.tiktok.id)
        // "Make shorts like this reference": its captions, zooms, pacing and effects.
        var wantsMusic = app.settings.ai.aiMusic
        if let style {
            options = style.0.shortOptions(style.1, base: options)
            wantsMusic = style.0.shortWantsMusic(style.1, default: wantsMusic)
        }
        let cam = webcamCompanion(for: asset)
        // The split that suits what you stream (Set up for my stream), when there's a facecam to place.
        if options.layout == nil, let content = app.settings.streamSetup?.content, cam != nil || analyses[asset.id]?.webcam != nil {
            options.layout = content.preferredLayout
        }
        let sfx = document.media.filter { $0.role == .soundEffect }
        let music = wantsMusic ? document.media.first { $0.role == .music } : nil
        let input = ShortBuildInput(candidate: candidate, asset: asset, analysis: analyses[asset.id], soundEffects: sfx, music: music,
                                    companionWebcam: cam, companionVoice: voiceCompanion(for: asset),
                                    companionFaceCenter: cam.flatMap { analyses[$0.id]?.webcam?.face.center })
        var timeline = ShortBuilder.build(input, options: options)
        if app.settings.ai.censorAudio != .off, let words = analyses[asset.id]?.transcript?.words {
            AudioCensor.apply(app.settings.ai.censorAudio, to: &timeline, words: words, assetID: asset.id, extra: app.settings.ai.normalizedExtraProfanity,
                              tone: app.settings.ai.bleepTone)
        }
        return (timeline, wantsMusic, options, music, sfx)
    }

    func makeMoreEntertaining(options: EntertainmentOptions = EntertainmentOptions()) {
        autoSnapshot("Before Make More Entertaining")
        makeMoreEntertainingWithLibrary(options: options)
    }

    func applyEntertainment(options: EntertainmentOptions) {
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

    /// Razor through every unlocked track at the playhead, whatever is selected (#145).
    func splitAllAtPlayhead() {
        let t = playhead
        editTimeline("Split All Tracks") { try $0.split(at: t, clipIDs: nil) }
    }

    // MARK: Attributes, transitions, loops, snapshots

    func copyAttributes() {
        guard let clip = selectedClips.first else { app.toast("Select a clip to copy its look from"); return }
        copiedAttributes = ClipAttributes(from: clip)
        app.toast("Copied the look and sound of “\(clip.name)”")
    }

    func pasteAttributes(parts: ClipAttributes.Parts = .all) {
        guard let attributes = copiedAttributes else { app.toast("Copy attributes from a clip first (⌥⌘C)"); return }
        let ids = Array(selectedClipIDs)
        guard !ids.isEmpty else { app.toast("Select the clips to paste onto"); return }
        var changed = 0
        editTimeline("Paste Attributes") { changed = $0.paste(attributes, onto: ids, parts: parts) }
        app.toast("Pasted \(parts.displayName) onto \(changed) clip\(changed == 1 ? "" : "s")")
    }

    /// ⌘T: the default transition at the selected clips' edges, or at the cut under the playhead (#168).
    func addDefaultTransition() {
        let transition = ClipTransition(kind: app.settings.defaultTransitionKind, duration: app.settings.defaultTransitionDuration)
        var ids = Array(selectedClipIDs)
        if ids.isEmpty, let edit = activeTimeline?.editPoint(near: playhead) { ids = [edit.incoming] }
        guard !ids.isEmpty else { app.toast("Select a clip, or put the playhead on a cut"); return }
        var count = 0
        editTimeline("Add Transition") { count = $0.addTransition(transition, toEdgesOf: ids) }
        app.toast(count == 0 ? "No cut to put a transition on (the clip edges don't touch a neighbour)" : "\(transition.kind.displayName) on \(count) cut\(count == 1 ? "" : "s")")
    }

    /// ⌥L: loop the in → out stretch (or the whole timeline when there is none) (#159).
    func toggleLoopInOut() {
        if playback.loopEnabled, playback.loopRange == inOutRange {
            playback.loopEnabled = false
            playback.loopRange = nil
            app.toast("Loop off")
            return
        }
        playback.loopRange = inOutRange
        playback.loopEnabled = true
        if let r = inOutRange {
            if !r.contains(playback.currentTime) { playback.seek(to: r.start) }
            app.toast("Looping \(Timecode.short(r.start)) → \(Timecode.short(r.end))")
        } else {
            app.toast("Looping the whole timeline — set in and out points (I / O) to loop a stretch")
        }
    }

    /// ⌥⌘E: export only the in → out stretch with the project's last settings (#158).
    func exportInOut() {
        guard let range = inOutRange else { app.toast("Set in and out points first (I / O)"); return }
        app.quickExport(range: range)
    }

    func takeSnapshot(name: String? = nil) {
        guard let timeline = activeTimeline else { return }
        let count = document.snapshots(for: timeline.id).count + 1
        let label = name ?? "Snapshot \(count) — \(Date().formatted(date: .omitted, time: .shortened))"
        edit("Take Snapshot") { $0.snapshot(timelineID: timeline.id, name: label) }
        app.toast("Saved “\(label)”")
    }

    /// Before an automatic pass rewrites a timeline, keep what it was.
    func autoSnapshot(_ name: String) {
        guard let timeline = activeTimeline else { return }
        edit("Snapshot", coalesce: "auto-snapshot") { $0.snapshot(timelineID: timeline.id, name: name, automatic: true) }
    }

    func restoreSnapshot(_ id: UUID) {
        let name = document.snapshots.first { $0.id == id }?.name ?? "snapshot"
        edit("Restore Snapshot") { $0.restore(snapshotID: id) }
        selectedClipIDs = []
        app.toast("Restored “\(name)” — the version before it is in the list too")
    }

    func deleteSnapshot(_ id: UUID) {
        edit("Delete Snapshot") { $0.deleteSnapshot(id: id) }
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

    /// Timeline → Add Shape (#218): a colour layer shaped by its mask — rectangle, circle, a ring to point at
    /// something, or a thin line.
    enum ShapeKind: String, CaseIterable {
        case rectangle, circle, ring, line

        var displayName: String {
            switch self {
            case .rectangle: return "Rectangle"
            case .circle: return "Circle"
            case .ring: return "Highlight Ring"
            case .line: return "Line"
            }
        }
    }

    func addShape(_ kind: ShapeKind) {
        let t = playhead
        editTimeline("Add \(kind.displayName)") { timeline in
            let trackID = timeline.freeTrack(kind: .video, for: TimeRange(start: t, duration: 3))
            let accent = RGBAColor(hex: "#FFD60A")!
            var clip = TimelineClip(name: kind.displayName, content: .solid(kind == .ring ? RGBAColor(red: 0, green: 0, blue: 0, alpha: 0) : accent),
                                    start: t, sourceDuration: 3, role: .graphic)
            switch kind {
            case .rectangle:
                clip.transform.scale = AnimatedDouble(0.35)
                clip.style.cornerRadius = 0.08
            case .circle:
                clip.transform.scale = AnimatedDouble(0.3)
                clip.style.mask = .circle
            case .ring:
                clip.transform.scale = AnimatedDouble(0.3)
                clip.style.mask = .circle
                clip.style.borderWidth = 10
                clip.style.borderColor = accent
            case .line:
                clip.transform.scale = AnimatedDouble(0.5)
                clip.transform.crop = NormRect(x: 0, y: 0.48, width: 1, height: 0.04)
            }
            clip.transform.positionX = AnimatedDouble(0.5)
            clip.transform.positionY = AnimatedDouble(0.5)
            try timeline.insert(clip, onTrack: trackID)
            selectedClipIDs = [clip.id]
        }
    }

    /// Places a media asset at the playhead (video + linked audio).
    func placeAsset(_ assetID: UUID, at time: Seconds? = nil, trackID: UUID? = nil) {
        guard let asset = document.asset(id: assetID) else { return }
        let start = time ?? playhead
        let duration = asset.kind == .image ? 5 : max(asset.metadata.duration, 0.1)
        let mode: InsertMode = insertMode ? .insert : .overwrite
        editTimeline("Add \(asset.name)") { t in
            let group = UUID()
            if asset.kind == .video || asset.kind == .image {
                let range = TimeRange(start: start, duration: duration)
                let vt = trackID.flatMap { id in t.tracks.first { $0.id == id && $0.kind == .video }?.id } ?? t.freeTrack(kind: .video, for: range)
                var video = TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: start, sourceDuration: duration,
                                         linkGroup: asset.metadata.hasAudio ? group : nil, role: asset.role == .webcam ? .webcam : (asset.role == .gameplay ? .gameplay : .main))
                video.transform.fit = .fill
                try t.insert(video, onTrack: vt, mode: mode)
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
                try t.insert(audio, onTrack: at, mode: mode)
            }
        }
    }

    func newTimeline(canvas: CanvasSettings, name: String = "Timeline") {
        let timeline = Timeline.empty(name: name, canvas: canvas)
        edit("New Timeline") { $0.timelines.append(timeline) }
        open(timelineID: timeline.id)
    }

    /// What the layout engine needs to know about a timeline's sources (main file, facecam file or region, faces).
    func layoutContext(for timeline: Timeline) -> (context: LayoutContext, assetID: UUID?) {
        let assetID = timeline.origin?.assetID ?? timeline.allClips.first { $0.isVisual && $0.role != .webcam && $0.assetID != nil }?.assetID ?? timeline.assetIDs.first
        let size = assetID.flatMap { document.asset(id: $0)?.metadata.size } ?? Size2(1920, 1080)
        var context = LayoutContext(analysis: analysis(for: timeline), sourceSize: size.isEmpty ? Size2(1920, 1080) : size)
        // A separate facecam recording (screen + webcam sessions).
        if let camID = timeline.allClips.first(where: { $0.role == .webcam && $0.assetID != nil && $0.assetID != assetID })?.assetID,
           let cam = document.asset(id: camID) {
            context.webcamSourceSize = cam.metadata.size.isEmpty ? Size2(1280, 720) : cam.metadata.size
            context.webcamRegion = .full
            context.webcamFaceCenter = analyses[camID]?.webcam?.face.center
        }
        return (context, assetID)
    }

    func applyLayout(_ preset: LayoutPreset) {
        guard let timeline = activeTimeline else { return }
        let (context, assetID) = layoutContext(for: timeline)
        let analysis = analysis(for: timeline)
        editTimeline("Layout: \(preset.displayName)") { t in
            if preset.usesWebcam, context.webcamRegion != nil, let assetID { LayoutEngine.ensureWebcamLayer(in: &t, assetID: assetID) }
            LayoutEngine.apply(preset == .dynamic ? .splitScreen : preset, to: &t, context: context)
            t.layout = preset
            if preset == .dynamic, context.webcamRegion != nil, let assetID, let analysis {
                ShortBuilder.applyDynamicLayout(to: &t, assetID: assetID, analysis: analysis, context: context)
            }
        }
        if preset == .dynamic, let t = activeTimeline {
            app.toast(t.layoutChanges.isEmpty ? "No layout changes needed — the energy is even" : "\(t.layoutChanges.count) AI layout changes, morphing smoothly")
        }
    }

    /// Morphs to `preset` starting at the playhead.
    func addLayoutChange(_ preset: LayoutPreset, duration: Seconds) {
        guard let timeline = activeTimeline else { return }
        let (context, assetID) = layoutContext(for: timeline)
        let time = playhead
        editTimeline("Change Layout to \(preset.displayName)") { t in
            if preset.usesWebcam, context.webcamRegion != nil, let assetID { LayoutEngine.ensureWebcamLayer(in: &t, assetID: assetID) }
            if t.layout == nil { t.layout = LayoutMorpher.preset(at: 0, in: t) }
            LayoutMorpher.addChange(preset, at: time, duration: duration, to: &t, context: context)
        }
    }

    func removeLayoutChange(_ id: UUID) {
        guard let timeline = activeTimeline else { return }
        let (context, _) = layoutContext(for: timeline)
        editTimeline("Remove Layout Change") { t in LayoutMorpher.removeChange(id: id, from: &t, context: context) }
    }

    func setLayoutChangeDuration(_ id: UUID, _ duration: Seconds) {
        guard let timeline = activeTimeline else { return }
        let (context, _) = layoutContext(for: timeline)
        editTimeline("Layout Morph Length", coalesce: "morph-\(id)") { t in
            guard let i = t.layoutChanges.firstIndex(where: { $0.id == id }) else { return }
            t.layoutChanges[i].duration = duration
            LayoutMorpher.rebuild(&t, context: context)
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

/// The viewer's direct-manipulation modes (#192).
enum CanvasTool: String, CaseIterable {
    case transform
    case crop
}
