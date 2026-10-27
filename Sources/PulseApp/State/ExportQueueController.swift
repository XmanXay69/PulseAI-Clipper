import AppKit
import Foundation
import PulseCore
import PulseEngine

/// Background export queue. Jobs snapshot their timeline + media at enqueue time, so the user can
/// keep editing (or close the project) while exports render.
@MainActor
final class ExportQueueController: ObservableObject {
    @Published private(set) var jobs: [ExportJob] = []
    @Published private(set) var isRunning = false
    /// Finish the current job, then wait (#339).
    @Published var isPaused = false {
        didSet { if !isPaused { startIfNeeded() } }
    }

    private struct Payload {
        var timeline: Timeline
        var assets: [UUID: MediaAsset]
        var compounds: [UUID: Timeline]
    }

    private var payloads: [UUID: Payload] = [:]
    private var worker: Task<Void, Never>?
    private var cancelFlags: [UUID: CancelFlag] = [:]
    var onJobFinished: ((ExportJob) -> Void)?

    var summary: ExportQueueSummary { ExportQueueSummary(jobs: jobs) }

    /// The whole queue (#340): the running job's own estimate, plus the average of the finished jobs for each
    /// one still waiting. Nil until there's something to go on.
    var queueRemaining: TimeInterval? {
        let running = jobs.compactMap { $0.estimatedRemaining() }
        let waiting = jobs.filter { $0.status == .queued }.count
        let finished = jobs.compactMap { job -> TimeInterval? in
            guard case .completed = job.status, let started = job.startedAt, let ended = job.finishedAt else { return nil }
            return ended.timeIntervalSince(started)
        }
        guard !running.isEmpty || (waiting > 0 && !finished.isEmpty) else { return nil }
        let average = finished.isEmpty ? 0 : finished.reduce(0, +) / Double(finished.count)
        return running.reduce(0, +) + Double(waiting) * average
    }

    func enqueue(timelines: [Timeline], document: ProjectDocument, settings: ExportSettings, range: TimeRange? = nil) {
        let assets = Dictionary(uniqueKeysWithValues: document.media.map { ($0.id, $0) })
        for timeline in timelines {
            var job = ExportJob(projectID: document.id, projectName: document.name, timelineID: timeline.id, timelineName: timeline.name, settings: settings)
            job.range = range
            payloads[job.id] = Payload(timeline: timeline, assets: assets, compounds: document.compoundsByID)
            jobs.append(job)
        }
        startIfNeeded()
    }

    /// Jobs that open in the default player when done (#360).
    private var previewJobIDs: Set<UUID> = []

    /// Ten seconds from the in point (or the top) with the real encoder settings, into a temporary folder,
    /// opened when it's done — bitrate artifacts show up before the full export (#360).
    func enqueuePreview(timeline: Timeline, document: ProjectDocument, settings: ExportSettings, from start: Seconds) {
        var settings = settings
        settings.outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("PULSE Previews", isDirectory: true).path
        settings.folderPerProject = false
        settings.exportSRT = false
        let begin = min(max(0, start), max(0, timeline.duration - 1))
        let range = TimeRange(start: begin, end: min(timeline.duration, begin + 10))
        let before = Set(jobs.map(\.id))
        enqueue(timelines: [timeline], document: document, settings: settings, range: range)
        for job in jobs where !before.contains(job.id) { previewJobIDs.insert(job.id) }
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if jobs[index].status.isActive {
            cancelFlags[id]?.set()
        } else if jobs[index].status == .queued {
            jobs[index].status = .cancelled
            payloads[id] = nil
        }
    }

    func cancelAll() {
        for job in jobs where !job.status.isFinished { cancel(job.id) }
    }

    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), payloads[id] != nil else { return }
        jobs[index].status = .queued
        jobs[index].startedAt = nil
        jobs[index].finishedAt = nil
        startIfNeeded()
    }

    /// Moves a queued job one place earlier or later among the queued ones (#339).
    func move(_ id: UUID, up: Bool) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status == .queued else { return }
        let queued = jobs.indices.filter { jobs[$0].status == .queued }
        guard let position = queued.firstIndex(of: index) else { return }
        let target = up ? position - 1 : position + 1
        guard queued.indices.contains(target) else { return }
        jobs.swapAt(index, queued[target])
    }

    func clearFinished() {
        let finished = jobs.filter { $0.status.isFinished }.map(\.id)
        jobs.removeAll { finished.contains($0.id) }
        for id in finished where jobs.first(where: { $0.id == id }) == nil { payloads[id] = nil }
    }

    func reveal(_ job: ExportJob) {
        guard let path = job.outputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        isRunning = true
        defer {
            isRunning = false
            worker = nil
        }
        while let index = jobs.firstIndex(where: { $0.status == .queued }) {
            if isPaused { return }   // resuming calls startIfNeeded again
            let job = jobs[index]
            guard let payload = payloads[job.id] else {
                jobs[index].status = .failed(message: "The export data was lost. Queue it again from the editor.")
                continue
            }
            let flag = CancelFlag()
            cancelFlags[job.id] = flag
            update(job.id) {
                $0.status = .preparing
                $0.startedAt = Date()
            }
            let directory = job.settings.outputDirectoryURL(projectName: job.projectName)
            do {
                if let problem = job.settings.validationError(for: payload.timeline.canvas) {
                    throw EngineError.exportFailed(problem)
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let index = jobs.firstIndex(where: { $0.id == job.id }) ?? 0
                let filename = job.settings.filename(project: job.projectName, clip: job.timelineName + (job.range.map { " \(Timecode.short($0.start))-\(Timecode.short($0.end))" } ?? ""), index: index + 1)
                let url = ExportSettings.uniqueURL(directory: directory, filename: filename) { FileManager.default.fileExists(atPath: $0.path) }
                let jobID = job.id
                let settings = job.settings, range = job.range
                let exportStart = Date()
                // Low priority keeps the editor smooth while it renders (#342).
                try await Task.detached(priority: settings.lowPriority ? .utility : .userInitiated) {
                    try await ExportEngine().export(timeline: payload.timeline, assets: payload.assets, compounds: payload.compounds, settings: settings, to: url, range: range, progress: { p in
                        Task { @MainActor [weak self] in
                            self?.update(jobID) { $0.status = .rendering(progress: p) }
                        }
                    }, isCancelled: { flag.isSet })
                }.value
                PerfLog.record("Export \(job.timelineName) (\(Int((range?.duration ?? payload.timeline.duration).rounded())) s)", seconds: Date().timeIntervalSince(exportStart))
                // The description, ready to paste: title ideas, chapters, credits, hashtags.
                let sidecar = ExportSidecar.text(for: payload.timeline, projectName: job.projectName)
                if !sidecar.isEmpty {
                    try? sidecar.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                }
                // Captions not burned in → an .srt beside the file for the platform's own subtitles.
                if !job.settings.burnInCaptions, let captions = payload.timeline.captions, captions.isEnabled {
                    let srt = CaptionLayoutEngine.srt(track: captions, timeline: payload.timeline)
                    if !srt.isEmpty { try? srt.write(to: url.deletingPathExtension().appendingPathExtension("srt"), atomically: true, encoding: .utf8) }
                }
                // Make sure the file really plays and is the right length before calling it done.
                let probed = try await MediaProbe.probe(url)
                let expected = max(payload.timeline.duration, 0.1)
                if probed.duration < expected - 1.5 {
                    throw EngineError.exportFailed("the file came out \(Int((expected - probed.duration).rounded())) s short — check the log and try again")
                }
                update(job.id) {
                    $0.status = .completed(path: url.path)
                    $0.outputPath = url.path
                    $0.finishedAt = Date()
                }
                if previewJobIDs.remove(job.id) != nil { NSWorkspace.shared.open(url) }
                else {
                    // Every finished edit teaches "my style" (#489); previews and audio-only files don't count.
                    if !job.settings.audioOnly, let style = ReferenceStyleAnalyzer.measure(timeline: payload.timeline, assets: Array(payload.assets.values)) {
                        AppModel.current?.settings.noteOwnEdit(style)
                    }
                    // A thumbnail for the finished edit, when asked (#357).
                    if AppModel.current?.settings.thumbnailAfterExport == true, let session = AppModel.current?.session,
                       session.document.timeline(id: payload.timeline.id) != nil {
                        let timelineID = payload.timeline.id
                        Task { @MainActor in await session.thumbnailAfterExport(timelineID: timelineID) }
                    }
                }
            } catch EngineError.cancelled {
                update(job.id) {
                    $0.status = .cancelled
                    $0.finishedAt = Date()
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                update(job.id) {
                    $0.status = .failed(message: message)
                    $0.finishedAt = Date()
                }
            }
            cancelFlags[job.id] = nil
            if let finished = jobs.first(where: { $0.id == job.id }) { onJobFinished?(finished) }
        }
    }

    private func update(_ id: UUID, _ body: (inout ExportJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        var copy = jobs[index]
        body(&copy)
        // A late progress callback must never overwrite a final state.
        if jobs[index].status.isFinished && !copy.status.isFinished { return }
        jobs[index] = copy
    }
}
