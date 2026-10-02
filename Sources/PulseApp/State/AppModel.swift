import AppKit
import Combine
import Foundation
import PulseCore
import PulseEngine
import SwiftUI
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
}

/// Application-wide state.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persistSettings() }
    }
    @Published var section: SidebarSection = .home
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
    @Published var showReportProblem = false
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
    }

    init() {
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
                self.logActivity(.export, title: "Exported “\(job.timelineName)”", detail: (path as NSString).lastPathComponent)
                self.session?.edit("Mark Exported") { doc in doc.exportCount += 1 }
            case .failed(let message):
                PulseLog.error("Export failed: \(job.timelineName) — \(message)")
                self.logActivity(.export, title: "Export failed: \(job.timelineName)", detail: message)
            default: break
            }
        }
        recordingObserver = recording.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        refreshProjects()
        refreshActivity()
        refreshDiskInfo()
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
        panel.canChooseDirectories = false
        panel.allowedContentTypes = (MediaTypes.allImportableExtensions + Array(MediaTypes.transcriptExtensions)).compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Import"
        panel.message = "Choose videos, audio, images or transcripts (SRT/VTT)"
        if panel.runModal() == .OK {
            importMedia(panel.urls)
        }
    }

    /// Imports into the open project, creating a project named after the first file if needed.
    func importMedia(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if session == nil {
            let name = urls.first.map { $0.deletingPathExtension().lastPathComponent } ?? "New Project"
            newProject(name: name)
        }
        session?.importMedia(urls)
        section = .importMedia
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
                                availableBytes: DiskSpace.available(at: projectsFolder), totalBytes: DiskSpace.total(at: projectsFolder))
            await MainActor.run { [weak self] in self?.diskInfo = info }
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

    func presentMessage(title: String, message: String) {
        PulseLog.warning("\(title): \(message)")
        alert = AppAlert(title: title, message: message)
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

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        showOnboarding = false
    }
}
