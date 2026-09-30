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
        case finishing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
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
    @Published var showsCursor = true
    @Published var hidePulse = true
    @Published var countdown = true
    @Published var analyzeAfter = true

    private let recorder = SessionRecorder()
    private var ticker: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

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

    func start(app: AppModel) {
        guard phase == .idle, let source = sources.first(where: { $0.id == selectedSourceID }) else { return }
        let options = RecordingOptions(source: source, captureSystemAudio: captureSystemAudio, cameraID: cameraID, microphoneID: microphoneID,
                                       frameRate: frameRate, showsCursor: showsCursor, excludeSelf: hidePulse,
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
                ticker = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard let self else { return }
                        self.elapsed = self.recorder.elapsed
                    }
                }
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

    func stop(app: AppModel) {
        guard phase == .recording else { return }
        phase = .finishing
        ticker?.cancel()
        Task {
            do {
                let result = try await recorder.stop()
                phase = .idle
                if app.session == nil {
                    app.newProject(name: "Recording \(Date().formatted(date: .abbreviated, time: .shortened))")
                }
                app.session?.importRecording(result, analyzeAfter: analyzeAfter)
                app.toast("Recording saved — \(Timecode.duration(result.duration))")
            } catch {
                phase = .idle
                app.present(error, title: "The recording couldn't be saved")
            }
        }
    }
}
