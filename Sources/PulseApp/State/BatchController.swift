import AppKit
import Foundation
import PulseCore
import PulseEngine
import UserNotifications

/// Overnight batch: queue several VODs, then for each one PULSE makes a project, analyzes it, builds the
/// top shorts and (optionally) a YouTube edit, and can export everything — keeping the Mac awake and
/// sending a notification when it's done.
@MainActor
final class BatchController: ObservableObject {
    struct Options: Codable, Hashable {
        var shortsPerVOD = 3
        var makeYouTubeEdit = true
        var exportEverything = false
        var exportPresetID = ExportPreset.tiktok.id
        var makeThumbnails = false

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Options()
            shortsPerVOD = (try? c.decodeIfPresent(Int.self, forKey: .shortsPerVOD)) ?? d.shortsPerVOD
            makeYouTubeEdit = (try? c.decodeIfPresent(Bool.self, forKey: .makeYouTubeEdit)) ?? d.makeYouTubeEdit
            exportEverything = (try? c.decodeIfPresent(Bool.self, forKey: .exportEverything)) ?? d.exportEverything
            exportPresetID = (try? c.decodeIfPresent(String.self, forKey: .exportPresetID)) ?? d.exportPresetID
            makeThumbnails = (try? c.decodeIfPresent(Bool.self, forKey: .makeThumbnails)) ?? d.makeThumbnails
        }
    }

    enum Status: Equatable {
        case queued
        case running(String)
        case done(String)
        case failed(String)
        case cancelled

        var isFinished: Bool {
            switch self {
            case .done, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        var url: URL
        var duration: Seconds?
        var status: Status = .queued
        var projectPath: String?
    }

    @Published var items: [Item] = []
    @Published var options: Options {
        didSet { if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: "batch.options") } }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var startedAt: Date?
    weak var app: AppModel?
    private var task: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    init() {
        if let data = UserDefaults.standard.data(forKey: "batch.options"), let saved = try? JSONDecoder().decode(Options.self, from: data) {
            options = saved
        } else {
            options = Options()
        }
    }

    // MARK: Queue

    func add(_ urls: [URL]) {
        let videos = urls.filter { ["mp4", "mov", "m4v", "mkv", "webm", "ts", "flv", "avi"].contains($0.pathExtension.lowercased()) }
        for url in videos where !items.contains(where: { $0.url == url && !$0.status.isFinished }) {
            var item = Item(url: url)
            item.duration = nil
            items.append(item)
            let id = item.id
            Task { [weak self] in
                let meta = try? await MediaProbe.probe(url)
                await MainActor.run { if let i = self?.items.firstIndex(where: { $0.id == id }) { self?.items[i].duration = meta?.duration } }
            }
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id && ($0.status == .queued || $0.status.isFinished) }
    }

    func clearFinished() { items.removeAll { $0.status.isFinished } }

    /// Rough total time for what's queued, from this Mac's measured speed.
    var estimatedTotal: Seconds? {
        guard let app else { return nil }
        let pending = items.filter { $0.status == .queued }
        guard !pending.isEmpty, pending.allSatisfy({ $0.duration != nil }) else { return nil }
        let speed = app.settings.ai.analysisSpeed
        return pending.reduce(0) { total, item in
            let d = item.duration ?? 0
            let analysis = speed.estimate(duration: d, hasAudio: true, transcribe: true, hasVideo: true).total
            let shorts = Double(options.shortsPerVOD) * 6
            let longForm = options.makeYouTubeEdit && d > 600 ? 60 + LongFormOptions().targetLength(forSource: d) / 240 * 25 : 0
            return total + analysis + shorts + longForm + 15
        }
    }

    // MARK: Run

    func start() {
        guard !isRunning, let app, items.contains(where: { $0.status == .queued }) else { return }
        isRunning = true
        startedAt = Date()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "PULSE is processing a batch of videos")
        requestNotificationPermission()
        PulseLog.info("Batch started: \(items.filter { $0.status == .queued }.count) videos")
        task = Task { [weak self] in
            guard let self else { return }
            while let next = self.items.first(where: { $0.status == .queued }) {
                if Task.isCancelled { break }
                await self.process(next.id, app: app)
            }
            // Let queued exports finish before calling it done.
            if self.options.exportEverything {
                self.setStatusOfLast(note: "Finishing exports…")
                while app.exports.isRunning && !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
            self.finish()
        }
    }

    func cancel() {
        task?.cancel()
        for i in items.indices where !items[i].status.isFinished { items[i].status = .cancelled }
        app?.jobs.running.forEach { $0.cancel() }
        finish()
    }

    private func finish() {
        guard isRunning else { return }
        isRunning = false
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        let done = items.filter { if case .done = $0.status { return true } else { return false } }.count
        let failed = items.filter { if case .failed = $0.status { return true } else { return false } }.count
        let elapsed = startedAt.map { DurationText.approximate(Date().timeIntervalSince($0)).replacingOccurrences(of: "about ", with: "") } ?? ""
        let summary = "\(done) video\(done == 1 ? "" : "s") done\(failed > 0 ? ", \(failed) failed" : "") in \(elapsed)"
        PulseLog.info("Batch finished: \(summary)")
        app?.toast("Batch finished — \(summary)")
        notify(title: "PULSE batch finished", body: summary)
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func setStatusOfLast(note: String) {
        if let i = items.lastIndex(where: { if case .done = $0.status { return true } else { return false } }), case .done(let s) = items[i].status {
            items[i].status = .done(s + " · " + note)
        }
    }

    private func set(_ id: UUID, _ status: Status) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].status = status
    }

    /// Waits until no background job has been running for a moment (steps start follow-up jobs).
    private func waitUntilIdle(_ app: AppModel, timeout: Seconds = 6 * 3600) async -> Bool {
        let start = Date()
        var quiet = 0
        while quiet < 3 {
            if Task.isCancelled { return false }
            if Date().timeIntervalSince(start) > timeout { return false }
            try? await Task.sleep(nanoseconds: 500_000_000)
            quiet = app.jobs.running.isEmpty ? quiet + 1 : 0
        }
        return true
    }

    private func process(_ index: UUID, app: AppModel) async {
        guard let url = items.first(where: { $0.id == index })?.url else { return }
        let name = url.deletingPathExtension().lastPathComponent
        PulseLog.info("Batch: \(name)")
        set(index, .running("Creating project"))
        app.newProject(name: name)
        guard let session = app.session else { return set(index, .failed("Couldn't create a project")) }
        if let i = items.firstIndex(where: { $0.id == index }) { items[i].projectPath = session.package.url.path }

        set(index, .running("Importing"))
        session.importMedia([url])
        guard await waitUntilIdle(app), let asset = session.document.primaryAsset else {
            return set(index, Task.isCancelled ? .cancelled : .failed("Couldn't import the video"))
        }

        set(index, .running("Analyzing (\(DurationText.approximate(session.analysisEstimate(for: asset))))"))
        session.analyze(assetID: asset.id, generateClips: true)
        guard await waitUntilIdle(app) else { return set(index, .cancelled) }
        guard session.analyses[asset.id] != nil else { return set(index, .failed("Analysis failed — see Help → Report a Problem")) }

        var made: [String] = []
        let top = session.document.visibleCandidates.sorted { $0.potential > $1.potential }.prefix(options.shortsPerVOD)
        if !top.isEmpty {
            set(index, .running("Building \(top.count) shorts"))
            for candidate in top { _ = session.createShort(from: candidate.id, open: false) }
            _ = await waitUntilIdle(app)
            made.append("\(top.count) short\(top.count == 1 ? "" : "s")")
        }

        if options.makeYouTubeEdit, asset.metadata.duration >= 600 {
            set(index, .running("Editing the YouTube video"))
            let before = Set(session.document.timelines.map(\.id))
            session.editMyVOD(options: LongFormOptions())
            _ = await waitUntilIdle(app)
            if let edit = session.document.timelines.first(where: { !before.contains($0.id) }) {
                made.append("YouTube edit \(Timecode.short(edit.duration))")
            }
        }

        if options.makeThumbnails {
            set(index, .running("Making thumbnail designs"))
            let target = session.document.timelines.first { EditFormat.of($0) == .longForm }
            if let setup = session.thumbnailSetup(for: ThumbnailRequest(timelineID: target?.id)),
               let designs = try? await session.writeThumbnailDesigns(asset: setup.asset, picks: Array(setup.picks.prefix(3)),
                                                                    layouts: [.fullFrame, .faceZoom]), !designs.isEmpty {
                made.append("\(designs.count) thumbnail designs")
            }
        }

        if options.exportEverything, !session.document.timelines.isEmpty {
            let folder = app.exportFolder.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for timeline in session.document.timelines {
                var settings = ExportSettings(preset: EditFormat.of(timeline) == .longForm ? .youtube : (ExportPreset.preset(id: options.exportPresetID) ?? .tiktok))
                settings.outputDirectory = folder.path
                app.exports.enqueue(timelines: [timeline], document: session.document, settings: settings)
            }
            made.append("exporting to \(folder.lastPathComponent)")
        }
        session.save()
        set(index, .done(made.isEmpty ? "No clips found" : made.joined(separator: " · ")))
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
