import AppKit
import Foundation
import PulseCore
import PulseEngine

/// "Edit Like a Reference": studies a video whose editing you like and keeps the measured style
/// (saved in settings, so it can be reused on any VOD or in the overnight batch).
@MainActor
final class ReferenceController: ObservableObject {
    @Published private(set) var isStudying = false
    @Published private(set) var studyingName = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var stage = ""
    @Published private(set) var remaining: String?
    @Published private(set) var failure: String?
    /// A language model is reading a studied video's words.
    @Published private(set) var isAsking = false
    @Published private(set) var askFailure: String?
    /// The style the sheet is working with (just measured, or picked from the saved ones).
    @Published var current: ReferenceStyle?
    weak var app: AppModel?
    private var job: BackgroundJob?

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "ts", "flv", "avi"]

    var saved: [ReferenceStyle] { app?.settings.referenceStyles ?? [] }

    /// Measures a reference video. Runs as a background job, so the sheet can be closed meanwhile.
    func study(_ url: URL) {
        guard let app, !isStudying else { return }
        guard Self.videoExtensions.contains(url.pathExtension.lowercased()) else {
            failure = "That doesn't look like a video file. Use an .mp4, .mov, .mkv or .webm."
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        begin(name: name, stage: "Opening the video")
        PulseLog.info("Studying reference: \(url.lastPathComponent)")
        job = app.jobs.start("Studying reference · \(name)", kind: .analysis) { [weak self] job in
            guard let self else { return }
            do {
                let study = try await Self.scan(url, app: app, job: job, cache: app.cacheFolder, light: false, estimate: true) { [weak self] p in
                    self?.show(p, job: job)
                }
                self.finish(study, named: nil)
            } catch {
                self.fail(error, job: job)
                throw error
            }
        }
    }

    /// Studies a YouTube video from its link: fetches it, measures it, keeps its words, and deletes the
    /// download. Only youtube.com is contacted.
    func study(link: String) {
        guard let app, !isStudying else { return }
        guard let videoID = YouTubeURL.videoID(from: link) else {
            failure = "That doesn't look like a YouTube link. Paste the address of the video's page."
            return
        }
        begin(name: "the linked video", stage: "Finding the video")
        PulseLog.info("Studying linked reference: \(videoID)")
        job = app.jobs.start("Studying a linked video", kind: .analysis) { [weak self] job in
            guard let self else { return }
            // The download and everything made while studying it live in one folder, removed at the end.
            let work = PulseDirectories.cache("Study Downloads", root: app.cacheFolder).appendingPathComponent(videoID, isDirectory: true)
            try? FileManager.default.removeItem(at: work)
            defer { try? FileManager.default.removeItem(at: work) }
            do {
                let title = await VODDownloader.title(videoID: videoID)
                if let title { self.studyingName = title }
                let file = try await VODDownloader.download(videoID: videoID, into: work) { message in
                    Task { @MainActor [weak self] in
                        self?.stage = message
                        job.detail = message
                    }
                }
                let study = try await Self.scan(file, app: app, job: job, cache: work, light: false, estimate: true) { [weak self] p in
                    self?.show(p, job: job)
                }
                self.finish(study, named: title ?? "YouTube video \(videoID)")
            } catch {
                self.fail(error, job: job)
                throw error
            }
        }
    }

    /// Scans one video file as part of a background job. `cache` is where anything made along the way goes.
    /// With `estimate`, the job is told how long this video should take.
    static func scan(_ url: URL, app: AppModel, job: BackgroundJob, cache: URL, light: Bool, estimate: Bool,
                     progress: @escaping @MainActor @Sendable (EngineProgress) -> Void) async throws -> ReferenceScanner.Study {
        let plan = ImportPlan.make(urls: [url], existingPaths: [])
        guard let item = plan.items.first else { throw EngineError.fileMissing(url) }
        let asset = try await MediaImporter.makeAsset(for: item, cacheRoot: cache)
        if estimate {
            let base = app.settings.ai.analysisSpeed.estimate(duration: asset.metadata.duration, hasAudio: asset.metadata.hasAudio, transcribe: true,
                                                              hasVideo: asset.metadata.hasVideo).total
            // The finer frame pass and text reading add roughly half again.
            job.expect(base * 1.5 + 5)
        }
        return try await ReferenceScanner.study(asset: asset, ai: app.settings.ai, cacheDirectory: PulseDirectories.cache("Reference", root: cache),
                                                progress: { p in Task { @MainActor in progress(p) } },
                                                isCancelled: job.isCancelledCheck, light: light)
    }

    private func begin(name: String, stage: String) {
        isStudying = true
        studyingName = name
        progress = 0
        self.stage = stage
        remaining = nil
        failure = nil
        current = nil
    }

    private func show(_ p: EngineProgress, job: BackgroundJob) {
        job.progress = p.fraction
        job.detail = p.stage
        progress = p.fraction
        stage = p.stage
        remaining = job.remainingText
    }

    /// Keeps a finished study: the style in settings, its words in the cache. `title` renames a style whose
    /// file was named by a video id.
    private func finish(_ study: ReferenceScanner.Study, named title: String?) {
        guard let app else { return }
        var style = study.style
        if let title, !title.isEmpty { style.name = title }
        keep(study.material, for: style)
        app.settings.rememberStyle(style)
        current = style
        isStudying = false
        app.logActivity(.analysis, title: "Studied the editing of “\(style.name)”", detail: style.summary, location: .local)
        app.toast("Got it — \(style.summary.lowercased())")
    }

    private func fail(_ error: Error, job: BackgroundJob) {
        isStudying = false
        if !Task.isCancelled, job.state == .running {
            failure = "Couldn't study that video: \(error.localizedDescription)"
        }
    }

    func cancel() {
        job?.cancel()
        isStudying = false
    }

    func forget(_ style: ReferenceStyle) {
        app?.settings.referenceStyles.removeAll { $0.id == style.id }
        if current?.id == style.id { current = nil }
        objectWillChange.send()
    }

    func clearFailure() { failure = nil }

    // MARK: What it teaches

    private func materialURL(for id: UUID) -> URL? {
        guard let app else { return nil }
        return PulseDirectories.cache("Reference", root: app.cacheFolder).appendingPathComponent("\(id.uuidString).words.json")
    }

    private func keep(_ material: StyleStudyMaterial, for style: ReferenceStyle) {
        guard !material.isEmpty, let url = materialURL(for: style.id), let data = try? JSONEncoder().encode(material) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// What was said in a studied video and the text on its frames, when they were kept. They live in the
    /// cache, so clearing it loses them, and styles studied before this existed have none.
    func material(for style: ReferenceStyle) -> StyleStudyMaterial? {
        guard let url = materialURL(for: style.id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StyleStudyMaterial.self, from: data)
    }

    /// Asks the language model set up in Settings what a studied video teaches. It reads what was said, the
    /// text on the frames and PULSE's measurements, and its lessons are saved with the style. Only text is sent.
    func askWhatItTeaches(_ style: ReferenceStyle) {
        guard let app, !isAsking else { return }
        askFailure = nil
        guard let provider = AIProviders.styleStudyProvider(settings: app.settings.ai) else {
            app.presentMessage(title: "No language model is set up",
                               message: "A model can read what is said in this video and tell PULSE the editing rules it teaches or follows. Choose Claude, or a model running on this Mac, in Settings → AI Processing.")
            return
        }
        if provider.location == .cloud && app.settings.ai.processingPolicy == .alwaysLocal {
            app.presentMessage(title: "Cloud AI is off", message: AIProviderError.cloudNotPermitted.localizedDescription)
            return
        }
        // A model on this Mac usually reads far less in one go than a hosted one.
        let budget = provider.location == .local ? 80_000 : 400_000
        guard let words = self.material(for: style), let brief = StyleStudy.brief(style: style, material: words, budget: budget) else {
            app.presentMessage(title: "This video's words weren't kept",
                               message: "The model reads what was said in the video and the text on its frames. PULSE keeps those in its cache when it studies a video, and it has none for “\(style.name)”. Study the video again, then ask.")
            return
        }
        if provider.location == .cloud && app.settings.ai.processingPolicy != .allowCloud {
            let alert = NSAlert()
            alert.messageText = "Send this video's words to \(provider.displayName)?"
            var text = "About \(brief.wordCount.formatted()) words are sent: what was said in “\(style.name)”, with timecodes, the text PULSE read off its frames, and PULSE's measurements. Video and audio never leave your Mac."
            if brief.leftOut > 1 {
                text += " The video is longer than one request holds, so about \(Timecode.duration(brief.leftOut)) from its middle is left out."
            }
            alert.informativeText = text
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isAsking = true
        PulseLog.info("Asking \(provider.displayName) what “\(style.name)” teaches (\(brief.wordCount) words)")
        Task { [weak self] in
            do {
                let lessons = try await provider.studyStyle(brief: brief)
                guard let self else { return }
                var updated = style
                updated.lessons = lessons
                app.settings.rememberStyle(updated)
                if self.current?.id == style.id { self.current = updated }
                self.isAsking = false
                self.objectWillChange.send()
                let count = lessons.lessons.count
                app.logActivity(.analysis, title: "Learned \(count) editing rule\(count == 1 ? "" : "s") from “\(style.name)”",
                                detail: lessons.summary, location: provider.location)
                app.toast("\(count) rule\(count == 1 ? "" : "s") learned from “\(style.name)”")
            } catch {
                self?.isAsking = false
                self?.askFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
