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

    private struct Payload {
        var timeline: Timeline
        var assets: [UUID: MediaAsset]
    }

    private var payloads: [UUID: Payload] = [:]
    private var worker: Task<Void, Never>?
    private var cancelFlags: [UUID: CancelFlag] = [:]
    var onJobFinished: ((ExportJob) -> Void)?

    var summary: ExportQueueSummary { ExportQueueSummary(jobs: jobs) }

    func enqueue(timelines: [Timeline], document: ProjectDocument, settings: ExportSettings) {
        let assets = Dictionary(uniqueKeysWithValues: document.media.map { ($0.id, $0) })
        for timeline in timelines {
            let job = ExportJob(projectID: document.id, projectName: document.name, timelineID: timeline.id, timelineName: timeline.name, settings: settings)
            payloads[job.id] = Payload(timeline: timeline, assets: assets)
            jobs.append(job)
        }
        startIfNeeded()
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
            let directory = URL(fileURLWithPath: job.settings.outputDirectory, isDirectory: true)
            do {
                if let problem = job.settings.validationError(for: payload.timeline.canvas) {
                    throw EngineError.exportFailed(problem)
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let index = jobs.firstIndex(where: { $0.id == job.id }) ?? 0
                let filename = job.settings.filename(project: job.projectName, clip: job.timelineName, index: index + 1)
                let url = ExportSettings.uniqueURL(directory: directory, filename: filename) { FileManager.default.fileExists(atPath: $0.path) }
                let jobID = job.id
                try await ExportEngine().export(timeline: payload.timeline, assets: payload.assets, settings: job.settings, to: url, progress: { p in
                    Task { @MainActor [weak self] in
                        self?.update(jobID) { $0.status = .rendering(progress: p) }
                    }
                }, isCancelled: { flag.isSet })
                update(job.id) {
                    $0.status = .completed(path: url.path)
                    $0.outputPath = url.path
                    $0.finishedAt = Date()
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
