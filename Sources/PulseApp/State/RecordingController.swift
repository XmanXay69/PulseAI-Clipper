import AppKit
import Foundation
import PulseCore
import PulseEngine

/// Drives screen + camera + mic recording for the Record sheet and the recording HUD.
@MainActor
final class RecordingController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case recording
        case paused
        case finishing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// Microphone / system audio level in dBFS while recording (#323), −60 when silent.
    @Published private(set) var audioLevelDB: Float = -60
    @Published var sources: [CaptureSource] = []
    @Published var cameras: [CaptureDevice] = []
    @Published var microphones: [CaptureDevice] = []
    @Published var loadError: String?
    @Published var isLoadingSources = false

    // Choices (remembered for the session).
    @Published var selectedSourceID: String?
    @Published var captureSystemAudio = true
    @Published var cameraID: String?
    @Published var microphoneID: String?
    @Published var frameRate = 60
    @Published var codec: VideoCodec = .hevc
    @Published var showsCursor = true
    @Published var hidePulse = true
    @Published var countdown = true
    @Published var analyzeAfter = true
    /// Moments marked with "clip it" (⇧⌘M, or the HUD button) since recording started, in seconds.
    @Published private(set) var markedMoments: [TimeInterval] = []
    /// Moments the live meter found on its own (#481): the voice jumping well above its usual level.
    @Published private(set) var liveMoments: [LiveMoment] = []
    private var liveDetector = LiveMomentDetector()
    /// Poll League / TFT's Live Client Data API for kills and objectives while recording (#488).
    @Published var riotEvents = false
    @Published private(set) var gameEvents: [HUDEvent] = []
    private var riotTask: Task<Void, Never>?

    private let recorder = SessionRecorder()
    private var ticker: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var keyMonitors: [Any] = []

    var isActive: Bool { phase != .idle }

    func refreshDevices() {
        isLoadingSources = true
        loadError = nil
        cameras = SessionRecorder.cameras()
        microphones = SessionRecorder.microphones()
        if microphoneID == nil { microphoneID = microphones.first?.id }
        Task {
            do {
                let list = try await SessionRecorder.sources()
                sources = list
                if selectedSourceID == nil || !list.contains(where: { $0.id == selectedSourceID }) {
                    selectedSourceID = list.first { $0.kind == .display }?.id ?? list.first?.id
                }
            } catch {
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoadingSources = false
        }
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func outputDirectory(app: AppModel) -> URL {
        let base = app.settings.mediaFolder.isEmpty
            ? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("PULSE Recordings", isDirectory: true)
            : URL(fileURLWithPath: app.settings.mediaFolder, isDirectory: true)
        return base
    }

    /// One-click setups (#319).
    func apply(_ preset: RecordingPreset) {
        frameRate = preset.frameRate
        captureSystemAudio = preset.captureSystemAudio
        showsCursor = preset.showsCursor
        codec = preset.codec
    }

    /// "2.8 GB an hour" for the chosen source, frame rate and codec (#319).
    var diskEstimate: String? {
        guard let source = sources.first(where: { $0.id == selectedSourceID }) else { return nil }
        let tracks = 1 + (captureSystemAudio ? 1 : 0)
        return RecordingEstimate.perHourText(width: source.width, height: source.height, fps: frameRate, codec: codec, audioTracks: tracks)
    }

    func start(app: AppModel) {
        guard phase == .idle, let source = sources.first(where: { $0.id == selectedSourceID }) else { return }
        let options = RecordingOptions(source: source, captureSystemAudio: captureSystemAudio, cameraID: cameraID, microphoneID: microphoneID,
                                       frameRate: frameRate, showsCursor: showsCursor, excludeSelf: hidePulse, codec: codec,
                                       outputDirectory: outputDirectory(app: app))
        countdownTask = Task {
            if countdown {
                for n in stride(from: 3, through: 1, by: -1) {
                    phase = .countdown(n)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { phase = .idle; return }
                }
            }
            do {
                try await recorder.start(options)
                phase = .recording
                elapsed = 0
                markedMoments = []
                liveMoments = []
                gameEvents = []
                liveDetector = LiveMomentDetector()
                installClipItHotkey()
                ticker = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard let self else { return }
                        self.elapsed = self.recorder.elapsed
                        self.audioLevelDB = self.recorder.audioLevelDB
                        // The live meter proposes moments as they happen (#481).
                        if self.phase == .recording, let moment = self.liveDetector.feed(levelDB: self.audioLevelDB, at: self.elapsed) {
                            self.liveMoments.append(moment)
                        }
                    }
                }
                if riotEvents { startRiotPolling() }
            } catch {
                phase = .idle
                app.present(error, title: "Couldn't start recording")
            }
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        phase = .idle
    }

    /// Kills, objectives and the result straight from the game client while it runs (#488).
    private func startRiotPolling() {
        riotTask?.cancel()
        let client = RiotLiveClient()
        riotTask = Task { [weak self] in
            var announced = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.phase == .recording || self.phase == .paused else { continue }
                let fresh = await client.poll(elapsed: self.recorder.elapsed)
                if !fresh.isEmpty {
                    self.gameEvents.append(contentsOf: fresh)
                    if !announced { announced = true; PulseLog.info("Riot live events: game found, stamping events on the recording") }
                }
            }
        }
    }

    var isCapturing: Bool { phase == .recording || phase == .paused }

    func pause() {
        guard phase == .recording else { return }
        recorder.pause()
        phase = .paused
        elapsed = recorder.elapsed
    }

    func resume() {
        guard phase == .paused else { return }
        recorder.resume()
        phase = .recording
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    /// "Clip it": remembers this moment so analysis treats it as a sure thing (#318).
    func markMoment() {
        guard phase == .recording else { return }
        markedMoments.append(recorder.elapsed)
        NSSound(named: "Tink")?.play()
    }

    /// ⇧⌘M marks a moment while PULSE is frontmost, and from the game too when macOS lets PULSE see keys
    /// (System Settings → Privacy & Security → Input Monitoring); without that, the HUD button still works.
    private func installClipItHotkey() {
        removeClipItHotkey()
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard Self.isClipIt(event) else { return event }
            MainActor.assumeIsolated { self?.markMoment() }
            return nil
        }) { keyMonitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard Self.isClipIt(event) else { return }
            Task { @MainActor in self?.markMoment() }
        }) { keyMonitors.append(global) }
    }

    nonisolated private static func isClipIt(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: [.command, .shift]) &&
            event.charactersIgnoringModifiers?.lowercased() == "m"
    }

    private func removeClipItHotkey() {
        for monitor in keyMonitors { NSEvent.removeMonitor(monitor) }
        keyMonitors.removeAll()
    }

    func stop(app: AppModel) {
        guard isCapturing else { return }
        phase = .finishing
        ticker?.cancel()
        riotTask?.cancel()
        removeClipItHotkey()
        let marked = markedMoments
        let seeded = GameEventLog.merge(gameEvents, adding: LiveMomentDetector.events(from: liveMoments))
        Task {
            do {
                var result = try await recorder.stop()
                // Files over the size limit become parts (#322); they join back up on a timeline on import.
                if app.settings.recordingSplitGB > 0 {
                    phase = .finishing
                    result = try await RecordingSplitter.splitLargeFiles(result, gigabytes: app.settings.recordingSplitGB)
                }
                phase = .idle
                if app.session == nil {
                    app.newProject(name: "Recording \(Date().formatted(date: .abbreviated, time: .shortened))")
                }
                app.session?.importRecording(result, analyzeAfter: analyzeAfter, markedMoments: marked, gameEvents: seeded)
                var note = "Recording saved — \(Timecode.duration(result.duration))"
                if !marked.isEmpty { note += ", \(marked.count) moment\(marked.count == 1 ? "" : "s") marked" }
                if !liveMoments.isEmpty { note += ", \(liveMoments.count) live moment\(liveMoments.count == 1 ? "" : "s")" }
                if !gameEvents.isEmpty { note += ", \(gameEvents.count) game event\(gameEvents.count == 1 ? "" : "s")" }
                app.toast(note)
            } catch {
                phase = .idle
                app.present(error, title: "The recording couldn't be saved")
            }
        }
    }
}
