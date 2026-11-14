import AppKit
import Foundation
import PulseCore
import PulseEngine

/// The study library: links to videos about editing each kind of video, worked through one after another.
/// Each video is downloaded, measured on this Mac, read by the language model set up in Settings and then
/// deleted. Only what it taught is kept. When a genre's videos are done, their lessons are merged into
/// the rules they agree on, and Plan with the model follows those for that genre.
@MainActor
final class StudyLibraryController: ObservableObject {
    @Published private(set) var library: StudyLibrary
    @Published private(set) var isStudying = false
    @Published private(set) var isFinding = false
    @Published private(set) var isMerging = false
    /// What is happening now, in a line.
    @Published private(set) var status = ""
    /// What the video being studied is doing (downloading, listening, reading).
    @Published private(set) var detail = ""
    @Published private(set) var currentID: String?
    @Published private(set) var progress: Double = 0
    @Published var problem: String?
    weak var app: AppModel?
    private var job: BackgroundJob?

    static var fileURL: URL { PulseDirectories.applicationSupport.appendingPathComponent("StudyLibrary.json") }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), var saved = try? JSONDecoder().decode(StudyLibrary.self, from: data) {
            // A newer PULSE can ship more links; what was studied stays.
            saved.addShipped()
            library = saved
        } else {
            library = .preloaded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    var isBusy: Bool { isStudying || isFinding || isMerging }

    // MARK: Filling the list

    /// Searches YouTube from this Mac for the most-watched videos that teach editing this kind of video, and
    /// adds them until the genre holds a hundred. Only youtube.com is contacted.
    func findTop(for genre: VideoGenre) {
        guard !isBusy else { return }
        isFinding = true
        problem = nil
        status = "Searching YouTube for videos that teach editing: \(genre.displayName)"
        Task { [weak self] in
            var results: [VideoSearchResult] = []
            var refused = 0
            let queries = StudyFinder.queries(for: genre)
            for (index, query) in queries.enumerated() {
                for filter in [YouTubeSearchParser.videosFilter, YouTubeSearchParser.videosByViewsFilter] {
                    do {
                        results += try await OnlineMusicLibrary.shared.searchVideos(query, filter: filter)
                    } catch {
                        refused += 1
                    }
                    // Unhurried, so YouTube has no reason to turn the searches away.
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
                self?.status = "Searching YouTube: \(index + 1) of \(queries.count) phrases"
            }
            guard let self else { return }
            let ranked = StudyFinder.rank(results, for: genre, excluding: Set(self.library.videos.map(\.videoID)))
            let added = self.library.add(ranked, to: genre)
            self.save()
            self.isFinding = false
            self.status = ""
            if added == 0, refused == queries.count * 2 {
                self.problem = "YouTube couldn't be reached, so nothing was added. Check the connection and try again."
            } else if added == 0 {
                self.app?.toast(self.library.count(in: genre) >= StudyLibrary.perGenre ? "\(genre.displayName) already holds \(StudyLibrary.perGenre) videos" : "No new videos found for \(genre.displayName)")
            } else {
                self.app?.toast("Added \(added) video\(added == 1 ? "" : "s") to \(genre.displayName)")
            }
        }
    }

    /// Adds one video by its link. Its title is looked up afterwards.
    @discardableResult
    func add(link: String, to genre: VideoGenre) -> Bool {
        problem = nil
        guard let videoID = YouTubeURL.videoID(from: link) else {
            problem = "That doesn't look like a YouTube link. Paste the address of the video's page."
            return false
        }
        if let existing = library.videos.first(where: { $0.videoID == videoID }) {
            problem = "That video is already in the library, under \(existing.genre.displayName)."
            return false
        }
        library.videos.append(LibraryVideo(videoID: videoID, title: "YouTube video \(videoID)", genre: genre, origin: .added))
        save()
        Task { [weak self] in
            guard let title = await VODDownloader.title(videoID: videoID), let self,
                  let index = self.library.videos.firstIndex(where: { $0.videoID == videoID }) else { return }
            self.library.videos[index].title = title
            self.save()
        }
        return true
    }

    func remove(_ video: LibraryVideo) {
        guard currentID != video.videoID else { return }
        library.remove(video.videoID)
        save()
    }

    func retryFailed(in genre: VideoGenre) {
        if library.retryFailed(in: genre) > 0 { save() }
    }

    // MARK: Studying

    /// Why one video's study ended without lessons.
    private enum Stop: Error {
        /// The model can't be reached or won't answer for now: the run stops, the video stays queued.
        case model(String)
        /// This video can't be studied: it is marked and the run goes on.
        case video(String)
    }

    /// The provider, when studying may go ahead under the processing policy. Says why not otherwise.
    private func studyProvider(for what: String) -> StyleStudyProvider? {
        guard let app else { return nil }
        guard let provider = AIProviders.styleStudyProvider(settings: app.settings.ai) else {
            app.presentMessage(title: "No language model is set up",
                               message: "\(what) needs a language model to read what is said in each video. Choose Claude, or a model running on this Mac, in Settings → AI Processing.")
            return nil
        }
        if provider.location == .cloud && app.settings.ai.processingPolicy == .alwaysLocal {
            app.presentMessage(title: "Cloud AI is off", message: AIProviderError.cloudNotPermitted.localizedDescription)
            return nil
        }
        return provider
    }

    /// Studies the waiting videos of one genre, or of every genre, one after another. It can be stopped and
    /// carried on later: what is done stays done.
    func study(_ genre: VideoGenre?) {
        guard let app, !isBusy else { return }
        problem = nil
        let waiting = genre.map { library.count(in: $0, state: .queued) } ?? library.videos.filter { $0.state == .queued }.count
        guard waiting > 0 else {
            app.toast("Nothing is waiting to be studied")
            return
        }
        guard let provider = studyProvider(for: "Studying these videos") else { return }
        if provider.location == .cloud && app.settings.ai.processingPolicy != .allowCloud {
            let alert = NSAlert()
            alert.messageText = "Study \(waiting) video\(waiting == 1 ? "" : "s") with \(provider.displayName)?"
            alert.informativeText = "Each video is downloaded from YouTube, measured on this Mac and deleted when it is done. What is said in it, the text on its frames and PULSE's measurements are sent to \(provider.displayName), one request a video, and one more at the end to merge what they teach. Nothing of yours is sent. A video takes a few minutes; stop whenever you like and carry on later."
            alert.addButton(withTitle: "Study")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isStudying = true
        progress = 0
        let scope = genre?.displayName ?? "every genre"
        PulseLog.info("Study library: \(waiting) videos waiting in \(scope), read by \(provider.displayName)")
        job = app.jobs.start("Studying editing videos · \(scope)", kind: .analysis, location: provider.location) { [weak self] job in
            guard let self else { return }
            var done = 0
            var learned = 0
            var unreadableInARow = 0
            var touched: [VideoGenre] = []
            while !job.isCancelledCheck(), let video = self.library.next(in: genre) {
                self.currentID = video.videoID
                self.status = "\(done + 1) of \(waiting): \(video.title)"
                self.detail = ""
                job.detail = self.status
                do {
                    try await self.studyOne(video, provider: provider, job: job)
                    learned += 1
                    unreadableInARow = 0
                    if !touched.contains(video.genre) { touched.append(video.genre) }
                } catch {
                    if job.isCancelledCheck() || Task.isCancelled { break }
                    if case Stop.model(let said) = error {
                        self.problem = "Stopped: \(said) The videos already studied are kept; study again to carry on."
                        break
                    }
                    let reason: String
                    if case Stop.video(let said) = error { reason = said } else { reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
                    self.library.fail(video.videoID, reason: reason)
                    self.save()
                    unreadableInARow += 1
                    PulseLog.warning("Study library: “\(video.title)” failed: \(reason)")
                    if unreadableInARow >= 4 {
                        self.problem = "Stopped after four videos in a row couldn't be studied. The last reason: \(reason)"
                        break
                    }
                }
                done += 1
                job.progress = Double(done) / Double(max(waiting, 1))
                self.progress = job.progress
            }
            self.currentID = nil
            self.detail = ""
            // Merge what each touched genre's videos teach, unless the run was stopped by hand or by the model.
            if self.problem == nil, !job.isCancelledCheck() {
                for genre in touched {
                    self.status = "Merging what the videos in “\(genre.displayName)” teach"
                    job.detail = self.status
                    _ = await self.mergeNow(genre, provider: provider)
                }
            }
            self.isStudying = false
            self.status = ""
            if learned > 0 {
                app.logActivity(.analysis, title: "Studied \(learned) editing video\(learned == 1 ? "" : "s")", detail: scope, location: provider.location)
                app.toast("\(learned) video\(learned == 1 ? "" : "s") studied; the downloads are deleted")
            }
        }
    }

    func stop() {
        job?.cancel()
    }

    /// One video: download, measure, ask, record, delete.
    private func studyOne(_ video: LibraryVideo, provider: StyleStudyProvider, job: BackgroundJob) async throws {
        guard let app else { return }
        // The download and everything made while studying it live in one folder, removed when this returns.
        let work = PulseDirectories.cache("Study Downloads", root: app.cacheFolder).appendingPathComponent(video.videoID, isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        defer { try? FileManager.default.removeItem(at: work) }
        detail = "Fetching it from YouTube"
        let file = try await VODDownloader.download(videoID: video.videoID, into: work) { message in
            Task { @MainActor [weak self] in self?.detail = message }
        }
        let study = try await ReferenceController.scan(file, app: app, job: job, cache: work, light: true, estimate: false) { [weak self] p in
            self?.detail = p.stage
        }
        guard let brief = StyleStudy.brief(style: study.style, material: study.material, budget: provider.location == .local ? 80_000 : 400_000) else {
            throw Stop.video("Nothing is said in it and no text was read off its frames.")
        }
        detail = "\(provider.displayName) is reading what was said"
        let lessons: StyleLessons
        do {
            lessons = try await provider.studyStyle(brief: brief)
        } catch let error as AIProviderError {
            switch error {
            case .badResponse, .refused:
                // About this video, not about the model: carry on with the next.
                throw Stop.video(error.errorDescription ?? "The model's answer couldn't be read.")
            default:
                throw Stop.model(error.errorDescription ?? "The language model couldn't be reached.")
            }
        } catch {
            throw Stop.model(error.localizedDescription)
        }
        var measured = study.style
        measured.name = video.title
        library.record(lessons, measured: measured, for: video.videoID)
        save()
    }

    // MARK: Merging

    /// Merges a genre's lessons into the rules its videos agree on.
    func merge(_ genre: VideoGenre) {
        guard let app, !isBusy else { return }
        problem = nil
        guard let provider = studyProvider(for: "Merging what the videos teach") else { return }
        guard let brief = GenreStudy.brief(genre: genre, library: library, budget: provider.location == .local ? 60_000 : 500_000) else {
            app.toast("Study some of the videos in “\(genre.displayName)” first")
            return
        }
        if provider.location == .cloud && app.settings.ai.processingPolicy != .allowCloud {
            let alert = NSAlert()
            alert.messageText = "Send the rules from \(brief.entries.count) video\(brief.entries.count == 1 ? "" : "s") to \(provider.displayName)?"
            alert.informativeText = "\(brief.ruleCount) rules that were drawn from the videos in “\(genre.displayName)” are sent, about \(brief.wordCount.formatted()) words, to be merged into the ones they agree on. Nothing of yours is sent."
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isMerging = true
        status = "Merging what the videos in “\(genre.displayName)” teach"
        Task { [weak self] in
            guard let self else { return }
            if let learned = await self.mergeNow(genre, provider: provider) {
                app.toast("\(learned.rules.count) rule\(learned.rules.count == 1 ? "" : "s") from \(learned.videoCount) video\(learned.videoCount == 1 ? "" : "s") in “\(genre.displayName)”")
            }
            self.isMerging = false
            self.status = ""
        }
    }

    private func mergeNow(_ genre: VideoGenre, provider: StyleStudyProvider) async -> GenreKnowledge? {
        guard let brief = GenreStudy.brief(genre: genre, library: library, budget: provider.location == .local ? 60_000 : 500_000) else { return nil }
        do {
            let learned = try await provider.mergeLessons(brief: brief)
            library.setKnowledge(learned)
            save()
            PulseLog.info("Study library: \(learned.rules.count) rules for \(genre.displayName) from \(learned.videoCount) videos")
            return learned
        } catch {
            problem = "The lessons couldn't be merged: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return nil
        }
    }

    // MARK: For the planner

    /// The rules Plan with the model is given for a genre: what its studied videos agree on about openings,
    /// pacing and story. Empty until a genre's lessons have been merged.
    func planningGuidance(for genre: VideoGenre?) -> [String] {
        genre.flatMap { library.knowledge(for: $0) }?.planningGuidance ?? []
    }

    /// Shows the sheet as it looks part-way through a genre, for the CI walk-through. Nothing is saved.
    func showSample(genre: VideoGenre) {
        var sample = StudyLibrary.preloaded
        let lessons = StyleLessons(kind: .tutorial, summary: "A stand-in answer.", lessons: [StyleLessons.Lesson(topic: .hook, rule: "Open on the best moment; no greeting.")],
                                   writtenBy: "a stand-in (no model is asked in CI)")
        for video in sample.videos(in: genre).prefix(3) { sample.record(lessons, measured: nil, for: video.videoID) }
        if let fourth = sample.videos(in: genre).dropFirst(3).first { sample.fail(fourth.videoID, reason: "The video is private.") }
        sample.setKnowledge(GenreKnowledge(genre: genre, summary: "A stand-in for what a model would merge from the studied videos.",
                                           rules: [GenreKnowledge.Rule(topic: .hook, rule: "Open on the best moment of the video; no greeting, no logo.", support: 3, sources: ["A stand-in source"]),
                                                   GenreKnowledge.Rule(topic: .pacing, rule: "Cut every breath, and keep the laugh after the joke.", support: 2),
                                                   GenreKnowledge.Rule(topic: .sound, rule: "Effects sit under the voice.", support: 2)],
                                           videoCount: 3, writtenBy: "a stand-in (no model is asked in CI)"))
        library = sample
    }
}
