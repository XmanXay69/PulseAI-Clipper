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
        isStudying = true
        studyingName = name
        progress = 0
        stage = "Opening the video"
        remaining = nil
        failure = nil
        current = nil
        PulseLog.info("Studying reference: \(url.lastPathComponent)")
        job = app.jobs.start("Studying reference · \(name)", kind: .analysis) { [weak self] job in
            guard let self else { return }
            do {
                let plan = ImportPlan.make(urls: [url], existingPaths: [])
                guard let item = plan.items.first else { throw EngineError.fileMissing(url) }
                let asset = try await MediaImporter.makeAsset(for: item, cacheRoot: app.cacheFolder)
                let speed = app.settings.ai.analysisSpeed
                let base = speed.estimate(duration: asset.metadata.duration, hasAudio: asset.metadata.hasAudio, transcribe: true,
                                          hasVideo: asset.metadata.hasVideo).total
                // The finer frame pass and text reading add roughly half again.
                job.expect(base * 1.5 + 5)
                let style = try await ReferenceScanner.scan(asset: asset, ai: app.settings.ai,
                                                            cacheDirectory: PulseDirectories.cache("Reference", root: app.cacheFolder),
                                                            progress: { p in
                    Task { @MainActor [weak self] in
                        job.progress = p.fraction
                        job.detail = p.stage
                        self?.progress = p.fraction
                        self?.stage = p.stage
                        self?.remaining = job.remainingText
                    }
                }, isCancelled: job.isCancelledCheck)
                app.settings.rememberStyle(style)
                self.current = style
                self.isStudying = false
                app.logActivity(.analysis, title: "Studied the editing of “\(name)”", detail: style.summary, location: .local)
                app.toast("Got it — \(style.summary.lowercased())")
            } catch {
                self.isStudying = false
                if !Task.isCancelled, job.state == .running {
                    self.failure = "Couldn't study that video: \(error.localizedDescription)"
                }
                throw error
            }
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
}
