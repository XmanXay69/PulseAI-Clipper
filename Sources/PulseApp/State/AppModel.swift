import AppKit
import Combine
import Foundation
import PulseCore
import PulseEngine
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

enum SidebarSection: String, CaseIterable, Identifiable {
    case home, projects, importMedia, aiClips, editor, captions, media, templates, exports, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .projects: return "Projects"
        case .importMedia: return "Import"
        case .aiClips: return "AI Clips"
        case .editor: return "Editor"
        case .captions: return "Captions"
        case .media: return "Media"
        case .templates: return "Templates"
        case .exports: return "Exports"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .projects: return "square.grid.2x2"
        case .importMedia: return "square.and.arrow.down"
        case .aiClips: return "sparkles"
        case .editor: return "timeline.selection"
        case .captions: return "captions.bubble"
        case .media: return "photo.stack"
        case .templates: return "rectangle.3.group"
        case .exports: return "square.and.arrow.up"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .home: return "1"
        case .projects: return "2"
        case .importMedia: return "3"
        case .aiClips: return "4"
        case .editor: return "5"
        case .captions: return "6"
        case .media: return "7"
        case .templates: return "8"
        case .exports: return "9"
        case .settings: return nil
        }
    }

    /// Full-width working pages: the sidebar folds to icons so the timeline gets the room.
    var isWorkspace: Bool {
        switch self {
        case .aiClips, .editor, .captions: return true
        default: return false
        }
    }

    var needsProject: Bool {
        switch self {
        case .aiClips, .editor, .captions, .media: return true
        default: return false
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    /// An action on the toast, like Undo after an edit (#411).
    var action: (title: String, run: @MainActor () -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Application-wide state.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persistSettings()
            EngagementLexicon.customProfanity = settings.ai.normalizedExtraProfanity
            EmphasisDetector.learned = settings.ai.emphasisLearned
            if settings.watchFolder != oldValue.watchFolder { watchFolderChanged() }
        }
    }
    @Published var section: SidebarSection = .home
    @Published var showImportURLSheet = false
    /// The running app model, for App Intents (#462, #463).
    nonisolated(unsafe) static weak var current: AppModel?
    @Published private(set) var session: ProjectSession?
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var activity: [ActivityRecord] = []
    @Published var alert: AppAlert?
    @Published var toastMessage: Toast?
    @Published var pendingRecoveries: [RecoverySnapshot] = []
    @Published var showOnboarding = false
    @Published var showNewProjectSheet = false
    @Published var showGlobalSearch = false
    @Published var globalTemplates: [ClipTemplate] = []
    @Published private(set) var diskInfo: DiskInfo = DiskInfo()

    let jobs = JobCenter()
    let exports = ExportQueueController()
    let recording = RecordingController()
    @Published var showRecordSheet = false
    /// "Edit My VOD" — the long-form YouTube edit sheet.
    @Published var showLongFormSheet = false
    /// Set to open the "Make Thumbnail" sheet (Thumbnail Studio tie-in).
    @Published var thumbnailRequest: ThumbnailRequest?
    @Published var showReportProblem = false
    @Published var showBatchSheet = false
    let batch = BatchController()
    /// "Edit Like a Reference": studies a video whose editing you like.
    let reference = ReferenceController()
    /// In-app updates from GitHub Releases.
    let updater = AppUpdater()
    private var updaterObserver: AnyCancellable?
    @Published var showReferenceSheet = false
    /// "Set up for my stream" (#441).
    @Published var showSetupWizard = false
    private var recordingObserver: AnyCancellable?
    let store = ProjectStore()
    let recovery = RecoveryManager(directory: PulseDirectories.recovery)
    let library: LibraryDatabase?
    private var toastTask: Task<Void, Never>?
    private var sessionObserver: AnyCancellable?

    struct DiskInfo {
        var projectsBytes: Int64 = 0
        var cacheBytes: Int64 = 0
        var mediaBytes: Int64 = 0
        var availableBytes: Int64 = 0
        var totalBytes: Int64 = 0
        /// The "Enhance" audio renders (#290).
        var enhancedAudioBytes: Int64 = 0
        /// Each cache folder with its size, biggest first (#388, #456).
        var cacheBreakdown: [CacheFolder] = []
    }

    struct CacheFolder: Identifiable {
        let name: String
        let bytes: Int64
        var id: String { name }
    }

    nonisolated static let cacheFolderNames = ["Thumbnails", "Waveforms", "Analysis", "Proxies", "Converted", "Enhanced Audio", "Reference", "Beats"]

    init() {
        defer { AppModel.current = self }
        PulseLog.info("PULSE \(AppModel.versionString) launched on macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(ProblemReporter.machineModel), \(ProcessInfo.processInfo.activeProcessorCount) cores, \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")
        settings = AppModel.loadSettings()
        library = try? LibraryDatabase(url: LibraryDatabase.defaultURL())
        store.backupsToKeep = settings.backupsToKeep
        recovery.beginSession()
        pendingRecoveries = recovery.pendingRecoveries()
        showOnboarding = !settings.hasCompletedOnboarding
        globalTemplates = AppModel.loadTemplates()
        jobs.onFinished = { [weak self] job in
            guard let self else { return }
            if case .failed(let message) = job.state {
                self.present(title: "\(job.title) failed", message: message)
            }
        }
        exports.onJobFinished = { [weak self] job in
            guard let self else { return }
            switch job.status {
            case .completed(let path):
                PulseLog.info("Export finished: \(job.timelineName) → \((path as NSString).lastPathComponent)")
                self.notifyIfInBackground(title: "Export finished", body: "“\(job.timelineName)” is ready — \((path as NSString).lastPathComponent)")
                self.rememberPrediction(timelineID: job.timelineID, fileName: ((path as NSString).lastPathComponent as NSString).deletingPathExtension)
                self.logActivity(.export, title: "Exported “\(job.timelineName)”", detail: (path as NSString).lastPathComponent)
                self.session?.edit("Mark Exported") { doc in doc.exportCount += 1 }
                self.settings.stats.note { $0.exportsFinished += 1 }
            case .failed(let message):
                PulseLog.error("Export failed: \(job.timelineName) — \(message)")
                self.logActivity(.export, title: "Export failed: \(job.timelineName)", detail: message)
            default: break
            }
        }
        batch.app = self
        EngagementLexicon.customProfanity = settings.ai.normalizedExtraProfanity
        noteVersionChange()
        reference.app = self
        updaterObserver = updater.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            self.updater.onFound = { [weak self] release in
                self?.toast("PULSE \(release.version.description) is out — click Update (top right) to install")
            }
            self.updater.startWatching()
        }
        recordingObserver = recording.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        refreshProjects()
        refreshActivity()
        refreshDiskInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.remindAboutDeadlines() }
        EmphasisDetector.learned = settings.ai.emphasisLearned
        watchFolderChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.checkDependencies() }
    }

    // MARK: Folders

    var projectsFolder: URL {
        settings.projectFolder.isEmpty ? PulseDirectories.defaultProjects : URL(fileURLWithPath: settings.projectFolder, isDirectory: true)
    }

    var exportFolder: URL {
        settings.exportFolder.isEmpty ? PulseDirectories.defaultExports : URL(fileURLWithPath: settings.exportFolder, isDirectory: true)
    }

    var cacheFolder: URL {
        settings.cacheFolder.isEmpty ? PulseDirectories.caches : URL(fileURLWithPath: settings.cacheFolder, isDirectory: true)
    }

    // MARK: Settings persistence

    static var settingsURL: URL { PulseDirectories.applicationSupport.appendingPathComponent("Settings.json") }
    static var templatesURL: URL { PulseDirectories.applicationSupport.appendingPathComponent("Templates.json") }

    static func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    private func persistSettings() {
        store.backupsToKeep = settings.backupsToKeep
        if let data = try? ProjectStore.makeEncoder(pretty: true).encode(settings) {
            try? data.write(to: AppModel.settingsURL, options: .atomic)
        }
    }

    static func loadTemplates() -> [ClipTemplate] {
        guard let data = try? Data(contentsOf: templatesURL),
              let templates = try? ProjectStore.makeDecoder().decode([ClipTemplate].self, from: data) else { return [] }
        return templates
    }

    func addGlobalTemplate(_ template: ClipTemplate) {
        globalTemplates.append(template)
        persistTemplates()
    }

    func deleteGlobalTemplate(_ id: UUID) {
        globalTemplates.removeAll { $0.id == id }
        persistTemplates()
    }

    private func persistTemplates() {
        if let data = try? ProjectStore.makeEncoder(pretty: true).encode(globalTemplates) {
            try? data.write(to: AppModel.templatesURL, options: .atomic)
        }
    }

    var allTemplates: [ClipTemplate] { ClipTemplate.builtIns + globalTemplates }

    // MARK: Projects

    func refreshProjects() {
        var list = library?.projects() ?? []
        let known = Set(list.map(\.path))
        for summary in store.listProjects(in: projectsFolder) where !known.contains(summary.path) {
            list.append(summary)
        }
        projects = list.filter { FileManager.default.fileExists(atPath: $0.path) }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func newProject(name: String) {
        do {
            let (package, document) = try store.create(name: name, in: projectsFolder)
            openSession(package: package, document: document)
            session?.save()
            section = .importMedia
        } catch {
            present(error, title: "Couldn't create the project")
        }
    }

    func openProject(at url: URL) {
        let package = ProjectPackage(url: url)
        do {
            let (document, recovered) = try store.load(package)
            openSession(package: package, document: document)
            settings.noteRecentProject(url.path)
            if recovered {
                presentMessage(title: "Project restored from backup", message: ProjectStoreError.recoveredFromBackup(url).localizedDescription)
            }
            section = document.timelines.isEmpty ? (document.candidates.isEmpty ? .importMedia : .aiClips) : .editor
        } catch {
            present(error, title: "Couldn't open the project")
        }
    }

    func openProject(_ summary: ProjectSummary) {
        openProject(at: URL(fileURLWithPath: summary.path, isDirectory: true))
    }

    private func openSession(package: ProjectPackage, document: ProjectDocument) {
        session?.close()
        let newSession = ProjectSession(package: package, document: document, app: self)
        session = newSession
        newSession.startEditingClock()
        // Menus, sidebar badges and the top bar reflect session state (undo labels, clip counts…).
        sessionObserver = newSession.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        library?.index(document, path: package.url.path, thumbnailPath: document.thumbnailPath.map { package.url.appendingPathComponent($0).path })
        refreshProjects()
    }

    func closeProject() {
        session?.close()
        sessionObserver = nil
        session = nil
        section = .home
        refreshProjects()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectPackage.fileExtension) ?? .folder, .folder]
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = projectsFolder
        panel.prompt = "Open Project"
        if panel.runModal() == .OK, let url = panel.url {
            if url.pathExtension == ProjectPackage.fileExtension {
                openProject(at: url)
            } else {
                presentMessage(title: "Not a PULSE project", message: "Choose a folder ending in .pulse.")
            }
        }
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = (MediaTypes.allImportableExtensions + Array(MediaTypes.transcriptExtensions)).compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Import"
        panel.message = "Choose videos, audio, images or transcripts (SRT/VTT) — or a folder of them"
        // Where this project last imported from (#8).
        if let folder = session?.document.lastImportFolder, !folder.isEmpty, FileManager.default.fileExists(atPath: folder) {
            panel.directoryURL = URL(fileURLWithPath: folder)
        }
        if panel.runModal() == .OK {
            importMedia(panel.urls)
        }
    }

    /// Imports into the open project, creating a project named after the first file if needed. Folders bring
    /// in their media (#2).
    func importMedia(_ dropped: [URL]) {
        let urls = ImportPlan.expandingFolders(dropped)
        guard !urls.isEmpty else {
            if !dropped.isEmpty { toast("No videos, audio or transcripts in there") }
            return
        }
        if session == nil {
            let name = urls.first.map { $0.deletingPathExtension().lastPathComponent } ?? "New Project"
            newProject(name: name)
        }
        session?.importMedia(urls)
        section = .importMedia
    }

    /// "VOD → shorts + YouTube video" in one go (#460): pick recordings (or a folder of them) and the batch
    /// analyzes each, builds the top shorts and the YouTube edit with your saved answers, and keeps the Mac awake.
    func runFullPipeline() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Make Shorts + YouTube Video"
        panel.message = "Choose one or more recordings (or a folder). Each becomes a project with its best shorts and a YouTube edit."
        guard panel.runModal() == .OK else { return }
        batch.options.makeYouTubeEdit = true
        batch.add(panel.urls)
        showBatchSheet = true
        batch.start()
    }

    func renameProject(_ summary: ProjectSummary, to name: String) {
        let package = ProjectPackage(url: URL(fileURLWithPath: summary.path))
        if session?.package == package {
            session?.edit("Rename Project") { $0.name = name }
            session?.save()
        } else if var doc = try? store.load(package).document {
            doc.name = name
            try? store.save(doc, to: package)
            library?.index(doc, path: package.url.path, thumbnailPath: summary.thumbnailPath)
        }
        refreshProjects()
    }

    func duplicateProject(_ summary: ProjectSummary) {
        do {
            let copy = try store.duplicate(ProjectPackage(url: URL(fileURLWithPath: summary.path)), newName: summary.name + " copy")
            if let doc = try? store.load(copy).document { library?.index(doc, path: copy.url.path, thumbnailPath: nil) }
            refreshProjects()
            toast("Duplicated “\(summary.name)”")
        } catch {
            present(error, title: "Couldn't duplicate the project")
        }
    }

    func setTrashed(_ summary: ProjectSummary, _ trashed: Bool) {
        let package = ProjectPackage(url: URL(fileURLWithPath: summary.path))
        if var doc = try? store.load(package).document {
            doc.isTrashed = trashed
            try? store.save(doc, to: package)
            library?.index(doc, path: package.url.path, thumbnailPath: summary.thumbnailPath)
        }
        if trashed, session?.package == package { closeProject() }
        refreshProjects()
    }

    // MARK: Watch folder (#3) and nightly batch (#461)

    private var watchTimer: Timer?
    private var watchSeen: [String: Int64] = [:]
    private var watchPrimed = false

    func watchFolderChanged() {
        watchTimer?.invalidate()
        watchTimer = nil
        watchSeen = [:]
        watchPrimed = false
        let path = (settings.watchFolder as NSString).expandingTildeInPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollWatchFolder() }
        }
        pollWatchFolder()
    }

    /// New media that has stopped growing is imported; the first pass only learns what's there already.
    func pollWatchFolder() {
        let folder = URL(fileURLWithPath: (settings.watchFolder as NSString).expandingTildeInPath)
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return }
        var ready: [URL] = []
        var sizes: [String: Int64] = [:]
        for url in items where MediaTypes.allImportableExtensions.contains(url.pathExtension.lowercased()) && !url.lastPathComponent.hasPrefix(".") {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            sizes[url.path] = size
            guard watchPrimed, let previous = watchSeen[url.path] else { continue }
            if previous == size, previous > 0, !watchImported.contains(url.path) { ready.append(url) }
        }
        // Files still being written are kept in `watchSeen` until their size settles.
        for (path, size) in sizes where watchSeen[path] == nil || watchSeen[path] != size { watchSeen[path] = size }
        for path in watchSeen.keys where sizes[path] == nil { watchSeen.removeValue(forKey: path); watchImported.remove(path) }
        if !watchPrimed {
            watchPrimed = true
            watchImported = Set(sizes.keys)   // what was already there isn't "new"
            return
        }
        guard !ready.isEmpty else { runNightlyIfDue(); return }
        for url in ready { watchImported.insert(url.path) }
        PulseLog.info("Watch folder: \(ready.count) new file\(ready.count == 1 ? "" : "s")")
        toast("\(ready.count) new recording\(ready.count == 1 ? "" : "s") in the watch folder — importing")
        if settings.nightlyBatchHour != nil {
            nightlyQueue.append(contentsOf: ready.map(\.path))
        } else {
            importMedia(ready)
            if settings.watchFolderAnalyzes, let session, let last = session.document.media.last { session.analyze(assetID: last.id) }
        }
        runNightlyIfDue()
    }

    private var watchImported = Set<String>()
    private var nightlyQueue: [String] = []

    /// At the chosen hour, the day's watch-folder recordings go through the overnight batch (#461).
    func runNightlyIfDue() {
        guard let hour = settings.nightlyBatchHour, Calendar.current.component(.hour, from: Date()) == hour, !nightlyQueue.isEmpty else { return }
        let key = "pulse.nightly.lastRun"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        let urls = nightlyQueue.map { URL(fileURLWithPath: $0) }
        nightlyQueue.removeAll()
        batch.options.makeYouTubeEdit = true
        batch.add(urls)
        batch.start()
        PulseLog.info("Nightly batch: \(urls.count) recording\(urls.count == 1 ? "" : "s") from the watch folder")
        notifyIfInBackground(title: "Nightly batch started", body: "\(urls.count) recording\(urls.count == 1 ? "" : "s") from the watch folder — shorts and a YouTube edit by morning")
    }

    /// What's missing for the features you've chosen (#391), once per launch.
    func checkDependencies() {
        var problems: [String] = []
        let wantsWhisper = settings.ai.transcriptionEngine == .whisperCpp || !settings.ai.whisperModelPath.isEmpty
        if wantsWhisper {
            if WhisperCppTranscriber.locateExecutable(preferred: settings.ai.whisperExecutablePath) == nil { problems.append("whisper.cpp isn't installed") }
            else if WhisperCppTranscriber.locateModel(preferred: settings.ai.whisperModelPath) == nil { problems.append("no Whisper model is downloaded") }
        }
        if !settings.ai.brollFolder.isEmpty, !FileManager.default.fileExists(atPath: (settings.ai.brollFolder as NSString).expandingTildeInPath) { problems.append("the B-roll folder is missing") }
        if !settings.ai.musicFolder.isEmpty, !FileManager.default.fileExists(atPath: (settings.ai.musicFolder as NSString).expandingTildeInPath) { problems.append("the music folder is missing") }
        guard !problems.isEmpty else { return }
        toast("Heads-up: \(problems.joined(separator: ", ")) — Settings → Diagnostics has the fixes")
    }

    // MARK: Archive (#470)

    /// The project and every file it references, zipped where you choose: media copied into Media/ so it opens
    /// anywhere.
    func archiveProject(_ summary: ProjectSummary) {
        let package = ProjectPackage(url: URL(fileURLWithPath: summary.path))
        if session?.package == package { session?.save() }
        guard let doc = try? store.load(package).document else { presentMessage(title: "Couldn't read the project", message: summary.name); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportSettings.cleanComponent(summary.name) + ".pulsearchive.zip"
        panel.allowedContentTypes = [.zip]
        panel.prompt = "Archive"
        let total = doc.media.map(\.metadata.fileSize).reduce(0, +)
        panel.message = "Project plus \(doc.media.count) media file\(doc.media.count == 1 ? "" : "s") (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        jobs.start("Archiving \(summary.name)", kind: .export) { job in
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-archive-\(UUID().uuidString)", isDirectory: true)
            let root = work.appendingPathComponent(ExportSettings.cleanComponent(summary.name), isDirectory: true)
            let mediaDir = root.appendingPathComponent("Media", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: package.url, to: root.appendingPathComponent(package.url.lastPathComponent))
                var copied = 0
                for (i, asset) in doc.media.enumerated() where FileManager.default.fileExists(atPath: asset.path) {
                    job.detail = asset.name
                    job.progress = Double(i) / Double(max(doc.media.count, 1))
                    let target = mediaDir.appendingPathComponent(URL(fileURLWithPath: asset.path).lastPathComponent)
                    if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: URL(fileURLWithPath: asset.path), to: target) }
                    copied += 1
                }
                try "PULSE archive. Open the .pulse project in PULSE; media that moved is found in Media/ by name.".write(to: root.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
                try? FileManager.default.removeItem(at: destination)
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-c", "-k", "--keepParent", root.path, destination.path]
                try ditto.run()
                ditto.waitUntilExit()
                try? FileManager.default.removeItem(at: work)
                guard ditto.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
                await MainActor.run {
                    self.logActivity(.export, title: "Archived “\(summary.name)”", detail: "\(copied) media files · \(destination.lastPathComponent)")
                    self.toast("Archived “\(summary.name)” with \(copied) media file\(copied == 1 ? "" : "s")")
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
            } catch {
                try? FileManager.default.removeItem(at: work)
                await MainActor.run { self.present(error, title: "Couldn't archive the project") }
            }
        }
    }

    /// Unpacks an archive next to your projects, relinks media to its Media/ folder by name, and opens it.
    func restoreArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.message = "Choose a PULSE archive (.pulsearchive.zip)"
        panel.prompt = "Restore"
        guard panel.runModal() == .OK, let zip = panel.url else { return }
        let target = projectsFolder.appendingPathComponent("Restored " + zip.deletingPathExtension().deletingPathExtension().lastPathComponent, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, target.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
            guard let enumerator = FileManager.default.enumerator(at: target, includingPropertiesForKeys: nil),
                  let projectURL = enumerator.compactMap({ $0 as? URL }).first(where: { $0.pathExtension == ProjectPackage.fileExtension }) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let mediaDir = projectURL.deletingLastPathComponent().appendingPathComponent("Media", isDirectory: true)
            let package = ProjectPackage(url: projectURL)
            var doc = try store.load(package).document
            var relinked = 0
            for i in doc.media.indices where !FileManager.default.fileExists(atPath: doc.media[i].path) {
                let candidate = mediaDir.appendingPathComponent(URL(fileURLWithPath: doc.media[i].path).lastPathComponent)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    doc.media[i].path = candidate.path
                    doc.media[i].bookmark = MediaAccess.bookmark(for: candidate)
                    doc.media[i].availability = .online
                    relinked += 1
                }
            }
            try store.save(doc, to: package)
            library?.index(doc, path: package.url.path, thumbnailPath: nil)
            refreshProjects()
            openProject(at: projectURL)
            toast("Restored “\(doc.name)”\(relinked > 0 ? " — \(relinked) media file\(relinked == 1 ? "" : "s") relinked" : "")")
        } catch {
            present(error, title: "Couldn't restore the archive")
        }
    }

    // MARK: Links (#1, #467)

    /// Pasted anywhere outside a text field: a YouTube link downloads the VOD; a file path imports it.
    func importPastedText(_ text: String) {
        if let id = YouTubeURL.videoID(from: text) {
            importFromYouTube(videoID: id)
        } else if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.isFileURL {
            importMedia([url])
        }
    }

    /// A YouTube VOD by link: fetched the way the B-roll library fetches clips (YouTube's own MP4 with sound,
    /// usually 720p) into ~/Movies/PULSE Downloads, then imported.
    func importFromYouTube(videoID: String) {
        jobs.start("Downloading VOD \(videoID)", kind: .importMedia) { [weak self] job in
            guard let self else { return }
            do {
                let url = try await VODDownloader.download(videoID: videoID) { status in Task { @MainActor in job.detail = status } }
                self.logActivity(.importMedia, title: "Downloaded VOD \(videoID)", detail: url.lastPathComponent)
                self.importMedia([url])
            } catch {
                self.present(error, title: "Couldn't download the VOD")
            }
        }
    }

    // MARK: Highlight reel (#492)

    /// The best moments of the last `days` days across every project, cut as one short in a new project.
    func makeHighlightReel(days: Int = 30) {
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        let recent = projects.filter { !$0.isTrashed && $0.modifiedAt > since }
        guard !recent.isEmpty else { toast("No projects edited in the last \(days) days"); return }
        session?.save()
        jobs.start("Highlight reel", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            var picks: [(candidate: ClipCandidate, asset: MediaAsset, analysis: MediaAnalysis?)] = []
            for summary in recent {
                let package = ProjectPackage(url: URL(fileURLWithPath: summary.path))
                guard let doc = try? self.store.load(package).document else { continue }
                for candidate in doc.visibleCandidates.sorted(by: { $0.potential > $1.potential }).prefix(3) {
                    guard let asset = doc.asset(id: candidate.assetID), FileManager.default.fileExists(atPath: asset.path) else { continue }
                    picks.append((candidate, asset, self.store.loadAnalysis(assetID: asset.id, in: package)))
                }
            }
            picks.sort { $0.candidate.potential > $1.candidate.potential }
            let chosen = Array(picks.prefix(10)).sorted { ($0.asset.importedAt, $0.candidate.range.start) < ($1.asset.importedAt, $1.candidate.range.start) }
            guard chosen.count >= 2 else { self.toast("Not enough moments yet — analyze a couple of streams first"); return }
            var reel: Timeline?
            var media: [MediaAsset] = []
            let options = ShortBuildOptions(settings: self.settings.ai, mode: .oneClick)
            for pick in chosen {
                job.detail = pick.candidate.title
                let piece = ShortBuilder.build(ShortBuildInput(candidate: pick.candidate, asset: pick.asset, analysis: pick.analysis), options: options)
                if reel == nil { reel = piece } else { reel?.append(piece) }
                if !media.contains(where: { $0.id == pick.asset.id }) { media.append(pick.asset) }
            }
            guard var timeline = reel else { return }
            let month = Date().formatted(.dateTime.month(.wide).year())
            timeline.name = "Highlights · \(month)"
            timeline.id = UUID()
            do {
                let created = try self.store.create(name: "Highlights \(month)", in: self.projectsFolder)
                let package = created.0
                var doc = created.1
                doc.media = media
                doc.primaryAssetID = media.first?.id
                doc.timelines = [timeline]
                doc.activeTimelineID = timeline.id
                try self.store.save(doc, to: package)
                for pick in chosen { if let analysis = pick.analysis { try? self.store.saveAnalysis(analysis, in: package) } }
                self.library?.index(doc, path: package.url.path, thumbnailPath: nil)
                self.refreshProjects()
                self.openProject(at: package.url)
                self.settings.stats.note { $0.shortsBuilt += 1 }
                self.toast("Highlight reel: \(chosen.count) moments from \(Set(chosen.map(\.asset.id)).count) streams — \(Timecode.duration(timeline.duration))")
            } catch {
                self.present(error, title: "Couldn't make the highlight reel")
            }
        }
    }

    /// When the project needs to be posted (#475); nil clears it.
    func setDeadline(_ summary: ProjectSummary, _ deadline: Date?) {
        let package = ProjectPackage(url: URL(fileURLWithPath: summary.path))
        if session?.package == package {
            session?.edit("Deadline") { $0.deadline = deadline }
            session?.save()
        } else if var doc = try? store.load(package).document {
            doc.deadline = deadline
            try? store.save(doc, to: package)
            library?.index(doc, path: package.url.path, thumbnailPath: summary.thumbnailPath)
        }
        refreshProjects()
    }

    /// A reminder for projects due within two days, once per launch (#475).
    func remindAboutDeadlines() {
        let soon = projects.filter { p in !p.isTrashed && p.status != .exported && (p.deadline.map { $0.timeIntervalSinceNow < 2 * 86400 } ?? false) }
        guard !soon.isEmpty else { return }
        let names = soon.prefix(3).map { "“\($0.name)” (\($0.deadline!.formatted(.relative(presentation: .named))))" }.joined(separator: ", ")
        toast(soon.count == 1 ? "Due soon: \(names)" : "\(soon.count) projects due soon: \(names)")
    }

    func setFavorite(_ summary: ProjectSummary, _ favorite: Bool) {
        let package = ProjectPackage(url: URL(fileURLWithPath: summary.path))
        if session?.package == package {
            session?.edit("Favorite") { $0.isFavorite = favorite }
            session?.save()
        } else if var doc = try? store.load(package).document {
            doc.isFavorite = favorite
            try? store.save(doc, to: package)
            library?.index(doc, path: package.url.path, thumbnailPath: summary.thumbnailPath)
        }
        refreshProjects()
    }

    func deleteProjectPermanently(_ summary: ProjectSummary) {
        let url = URL(fileURLWithPath: summary.path)
        if session?.package.url == url { closeProject() }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            library?.removeProject(id: summary.id)
            refreshProjects()
        } catch {
            present(error, title: "Couldn't move the project to the Trash")
        }
    }

    // MARK: Demo

    func openDemoProject() {
        jobs.start("Preparing sample project", kind: .importMedia) { [weak self] job in
            guard let self else { return }
            let mediaDir = PulseDirectories.applicationSupport.appendingPathComponent("Sample Media", isDirectory: true)
            job.detail = "Generating sample stream"
            let demo = try await DemoMediaGenerator.generate(in: mediaDir) { p in
                Task { @MainActor in job.progress = p * 0.5 }
            }
            let (package, document) = try self.store.create(name: "PULSE Sample Stream", in: self.projectsFolder)
            self.openSession(package: package, document: document)
            guard let session = self.session else { return }
            let meta = try await MediaProbe.probe(demo.videoURL)
            let asset = MediaAsset(name: "PULSE Demo Stream", path: demo.videoURL.path, bookmark: nil, kind: .video, role: .main, metadata: meta, generatedBy: "demo")
            session.edit("Import Sample") { doc in
                doc.media.append(asset)
                doc.primaryAssetID = asset.id
            }
            job.detail = "Analyzing"
            let pipeline = AnalysisPipeline(cacheDirectory: PulseDirectories.cache("Analysis", root: self.cacheFolder))
            let output = try await pipeline.run(asset: asset, options: .init(transcribe: false, detectFaces: true, ai: self.settings.ai, importedTranscript: demo.transcript),
                                                progress: { p in Task { @MainActor in job.progress = 0.5 + p.fraction * 0.45 } })
            var analysis = output.analysis
            if analysis.webcam == nil {
                analysis.visual?.faces = demo.faces
                analysis.webcam = WebcamEstimator.estimate(faces: demo.faces, frameSize: meta.size)
                analysis.profile = .gameplayWithFacecam
            }
            session.setAnalysis(analysis)
            session.edit("Analyze Sample") { doc in doc.updateAsset(id: asset.id) { $0.preparation.analysisState = .complete } }
            let candidates = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings(targetDuration: 15, aggressiveness: 0.7, minimumPotential: 0)).generate()
            session.edit("Generate AI Clips") { doc in doc.candidates = candidates }
            if let best = candidates.first {
                session.createShort(from: best.id, open: false)
            }
            session.save()
            self.logActivity(.clipGeneration, title: "\(candidates.count) potential clips found", detail: "Sample project")
            self.section = .aiClips
            self.toast("\(candidates.count) potential clips found")
        }
    }

    // MARK: Recovery

    func recover(_ snapshot: RecoverySnapshot) {
        let url = URL(fileURLWithPath: snapshot.projectPath, isDirectory: true)
        let package = ProjectPackage(url: url)
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            try store.save(snapshot.document, to: package)
            recovery.discard(snapshot)
            pendingRecoveries.removeAll { $0.id == snapshot.id }
            openProject(at: url)
            toast("Recovered “\(snapshot.document.name)”")
        } catch {
            present(error, title: "Couldn't recover the project")
        }
    }

    func discardRecovery(_ snapshot: RecoverySnapshot) {
        recovery.discard(snapshot)
        pendingRecoveries.removeAll { $0.id == snapshot.id }
    }

    func applicationWillTerminate() {
        session?.close()
        recovery.endSession()
    }

    // MARK: Activity & disk

    func logActivity(_ kind: ActivityRecord.Kind, title: String, detail: String = "", location: ProcessingLocation = .local) {
        library?.logActivity(kind: kind, title: title, detail: detail, location: location, projectID: session?.document.id)
        refreshActivity()
    }

    func refreshActivity() {
        activity = library?.recentActivity(limit: 30) ?? []
    }

    func refreshDiskInfo() {
        let projectsFolder = self.projectsFolder
        let cacheFolder = self.cacheFolder
        let mediaBytes = library?.stats().mediaBytes ?? 0
        Task.detached(priority: .utility) {
            let info = DiskInfo(projectsBytes: DiskSpace.size(of: projectsFolder), cacheBytes: DiskSpace.size(of: cacheFolder), mediaBytes: mediaBytes,
                                availableBytes: DiskSpace.available(at: projectsFolder), totalBytes: DiskSpace.total(at: projectsFolder),
                                enhancedAudioBytes: DiskSpace.size(of: cacheFolder.appendingPathComponent("Enhanced Audio")),
                                cacheBreakdown: AppModel.cacheFolderNames.map { CacheFolder(name: $0, bytes: DiskSpace.size(of: cacheFolder.appendingPathComponent($0))) }
                                    .filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes })
            await MainActor.run { [weak self] in self?.diskInfo = info }
        }
    }

    /// Drops one cache folder; everything in it comes back on demand (#388).
    func clearCacheFolder(_ name: String) {
        let folder = cacheFolder.appendingPathComponent(name)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: folder)
            await MainActor.run { [weak self] in
                self?.refreshDiskInfo()
                self?.toast("\(name) cache cleared")
            }
        }
        if name == "Thumbnails" { Task { await ThumbnailService.shared.clearMemory() } }
    }

    /// Settings as a JSON file, to move to another Mac (#444).
    func exportSettingsFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PULSE Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(settings).write(to: url)
            toast("Settings saved to \(url.lastPathComponent)")
        } catch {
            present(error, title: "Couldn't save the settings file")
        }
    }

    func importSettingsFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a PULSE Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var imported = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
            // Paths and the project list stay this Mac's own.
            imported.recentProjectPaths = settings.recentProjectPaths
            imported.projectFolder = settings.projectFolder
            imported.cacheFolder = settings.cacheFolder
            imported.exportFolder = settings.exportFolder
            imported.mediaFolder = settings.mediaFolder
            settings = imported
            toast("Settings imported from \(url.lastPathComponent)")
        } catch {
            present(error, title: "That isn't a PULSE settings file")
        }
    }

    /// Everything support would ask for (#447), as text.
    func diagnosticsText() -> String {
        let info = ProcessInfo.processInfo
        var chip = "unknown"
        var size = 0
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 { chip = String(cString: buffer) }
        }
        let transcription = TranscriptionEngineFactory.friendlyStatus(settings: settings.ai)
        var lines = [
            "PULSE \(AppModel.versionString)",
            "macOS \(info.operatingSystemVersionString) · \(chip) · \(info.processorCount) cores · \(ByteCountFormatter.string(fromByteCount: Int64(info.physicalMemory), countStyle: .memory)) RAM",
            "Hardware encoders: H.264 \(VideoEncoders.hardwareAvailable(for: .h264) ? "yes" : "no") · HEVC \(VideoEncoders.hardwareAvailable(for: .hevc) ? "yes" : "no") · ProRes \(VideoEncoders.hardwareAvailable(for: .proRes422) ? "yes" : "no")",
            "Transcription: \(transcription.text)",
            "Cache: \(cacheFolder.path) (\(ByteCountFormatter.string(fromByteCount: diskInfo.cacheBytes, countStyle: .file))) · free \(ByteCountFormatter.string(fromByteCount: diskInfo.availableBytes, countStyle: .file))",
            "Processing policy: \(settings.ai.processingPolicy) · cloud provider: \(settings.ai.cloudProvider.displayName) · online music: \(settings.ai.onlineMusic)",
            "Open project: \(session?.document.name ?? "none") · \(session?.document.timelines.count ?? 0) timelines · \(session?.document.media.count ?? 0) media",
            "",
            "Last log lines:",
        ]
        lines += PulseLog.tail(25)
        return lines.joined(separator: "\n")
    }

    /// Drops the "Enhance" audio renders only; they come back on demand (#290).
    func clearEnhancedAudioCache() {
        let folder = cacheFolder.appendingPathComponent("Enhanced Audio")
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: folder)
            await MainActor.run { [weak self] in
                self?.refreshDiskInfo()
                self?.toast("Audio renders cleared — they come back as clips play")
            }
        }
    }

    func clearCache() {
        let folder = cacheFolder
        Task.detached(priority: .utility) {
            for sub in ["Thumbnails", "Waveforms", "Analysis", "Proxies", "Converted", "Enhanced Audio"] {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(sub))
            }
            await MainActor.run { [weak self] in
                self?.refreshDiskInfo()
                self?.toast("Cache cleared")
            }
        }
        Task { await ThumbnailService.shared.clearMemory() }
    }

    // MARK: Messages

    func present(_ error: Error, title: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        PulseLog.error("\(title): \(message)")
        alert = AppAlert(title: title, message: message)
    }

    func present(title: String, message: String) {
        PulseLog.warning("\(title): \(message)")
        alert = AppAlert(title: title, message: message)
    }

    /// After an update, say so once and point at the release notes (Help → What's New).
    func noteVersionChange() {
        let key = "pulse.lastLaunchedVersion"
        let current = AppModel.shortVersion
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(current, forKey: key)
        guard let previous, previous != current, current != "dev" else { return }
        PulseLog.info("Updated from \(previous) to \(current)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.toast("Updated to PULSE \(current) — Help → What's New shows what changed")
        }
    }

    /// The release page for this build (the notes PULSE ships with).
    func openWhatsNew() {
        let version = AppModel.shortVersion
        let url = version == "dev" ? URL(string: "https://github.com/XmanXay69/PulseAI-Clipper/releases")!
            : URL(string: "https://github.com/XmanXay69/PulseAI-Clipper/releases/tag/v\(version)")!
        NSWorkspace.shared.open(url)
    }

    /// A system notification when PULSE isn't the active app (a toast is enough when it is). Only from the real
    /// .app bundle — the notification center refuses bare executables (the CI harness).
    func notifyIfInBackground(title: String, body: String) {
        guard !NSApp.isActive, Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// ⌘E: the current timeline into the export queue with the project's last export settings, no sheet.
    func quickExport(range: TimeRange? = nil) {
        guard let session, let timeline = session.activeTimeline else {
            toast("Open a timeline to export")
            return
        }
        var export = session.document.exportSettings
        if ExportPreset.preset(id: export.presetID) == nil {
            export = ExportSettings(preset: ExportPreset.preset(id: settings.defaultExportPresetID) ?? .tiktok)
        }
        if export.outputDirectory.isEmpty { export.outputDirectory = exportFolder.path }
        if EditFormat.of(timeline) == .longForm, ["tiktok", "shorts", "reels"].contains(export.presetID) {
            let folder = export.outputDirectory
            export = ExportSettings(preset: .youtube)
            export.outputDirectory = folder
        }
        if let problem = export.validationError(for: timeline.canvas) {
            presentMessage(title: "Can't export yet", message: problem)
            return
        }
        exports.enqueue(timelines: [timeline], document: session.document, settings: export, range: range)
        toast("Exporting “\(timeline.name)”")
        section = .exports
    }

    func presentMessage(title: String, message: String) {
        PulseLog.warning("\(title): \(message)")
        alert = AppAlert(title: title, message: message)
    }

    // MARK: Performance history (for calibrating the coach)

    @Published private(set) var performanceHistory: [PerformanceRecord] = AppModel.loadPerformanceHistory()

    static var performanceHistoryURL: URL { PulseDirectories.applicationSupport.appendingPathComponent("performance-history.json") }

    static func loadPerformanceHistory() -> [PerformanceRecord] {
        guard let data = try? Data(contentsOf: performanceHistoryURL) else { return [] }
        return (try? JSONDecoder().decode([PerformanceRecord].self, from: data)) ?? []
    }

    func savePerformanceHistory() {
        if let data = try? JSONEncoder().encode(performanceHistory) { try? data.write(to: Self.performanceHistoryURL, options: .atomic) }
    }

    /// What the coach predicted for an export, kept so real views can be matched to it later.
    func rememberPrediction(timelineID: UUID, fileName: String) {
        guard let session, let timeline = session.document.timeline(id: timelineID), let review = session.review(of: timeline) else { return }
        var titles = [timeline.name, fileName]
        if let copy = timeline.copy { titles += copy.titles + [copy.shortsTitle] }
        performanceHistory.removeAll { $0.titles.first == timeline.name && $0.views == nil && $0.predictedScore == review.prediction.score }
        performanceHistory.append(PerformanceRecord(review: review, titles: titles, duration: timeline.duration))
        if performanceHistory.count > 2000 { performanceHistory.removeFirst(performanceHistory.count - 2000) }
        savePerformanceHistory()
    }

    /// Reads a YouTube Studio / TikTok analytics CSV, matches it to past exports and recalibrates the coach.
    func importAnalytics(_ url: URL) -> (rows: Int, matched: Int) {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16)) else { return (0, 0) }
        let rows = AnalyticsImporter.parse(text)
        var records = performanceHistory
        let matched = AnalyticsImporter.match(rows, into: &records)
        performanceHistory = records
        savePerformanceHistory()
        settings.ai.coachCalibration = CoachCalibrator.fit(records)
        PulseLog.info("Analytics import: \(rows.count) rows, \(matched) matched, \(records.filter { $0.views != nil }.count) total with views")
        return (rows.count, matched)
    }

    func resetCalibration() {
        settings.ai.coachCalibration = nil
        for i in performanceHistory.indices { performanceHistory[i].views = nil; performanceHistory[i].averagePercentViewed = nil }
        savePerformanceHistory()
    }

    /// "1.1.0" from the bundle, or "dev" when run from source.
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// "1.0.1 (68)" from the bundle, or "dev" when run from source.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        return "\(v) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    func toast(_ message: String) {
        toastMessage = Toast(message: message)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if !Task.isCancelled { self?.toastMessage = nil }
        }
    }

    /// A toast with an Undo button for the edit that just happened (#411); stays a little longer.
    func toast(_ message: String, undo: Bool) {
        guard undo, let session else { return toast(message) }
        toastMessage = Toast(message: message, action: ("Undo", { [weak session] in session?.undo() }))
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { self?.toastMessage = nil }
        }
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        showOnboarding = false
    }
}
