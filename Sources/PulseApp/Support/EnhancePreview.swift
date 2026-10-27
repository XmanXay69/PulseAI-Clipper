import AVFoundation
import Foundation
import PulseCore
import PulseEngine

/// Ten seconds of a clip, raw against processed (#261): both play in step and a switch picks which one you
/// hear, so a leveling or noise setting can be judged before it's committed to the whole clip.
@MainActor
final class EnhancePreview: ObservableObject {
    enum Hearing: String, CaseIterable { case raw, half, processed }

    @Published private(set) var isRendering = false
    @Published private(set) var isPlaying = false
    @Published var hearing: Hearing = .processed { didSet { applyVolumes() } }
    @Published private(set) var error: String?

    private var rawPlayer: AVPlayer?
    private var processedPlayer: AVPlayer?
    /// The same stretch at half strength (#276).
    private var halfPlayer: AVPlayer?
    private var stopTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    static let length: Seconds = 10

    /// Renders the window around `sourceTime` (clip-source seconds) with `settings` and starts both players.
    func start(sourceURL: URL, clip: TimelineClip, sourceTime: Seconds) {
        stop()
        let span = min(Self.length, clip.sourceDuration)
        let start = max(clip.sourceIn, min(sourceTime - span / 2, clip.sourceOut - span))
        let range = TimeRange(start: start, end: start + span)
        isRendering = true
        error = nil
        renderTask = Task { [weak self] in
            do {
                let processed = try await AudioEnhancer.shared.render(sourceURL: sourceURL, range: range, settings: clip.audio,
                                                                      cacheDirectory: PulseDirectories.cache("Enhanced Audio"))
                // Half strength (#276): the voice isolation at 50 %, everything else as set.
                var halfSettings = clip.audio
                halfSettings.noiseReduction *= 0.5
                let half = try await AudioEnhancer.shared.render(sourceURL: sourceURL, range: range, settings: halfSettings,
                                                                 cacheDirectory: PulseDirectories.cache("Enhanced Audio"))
                guard let self, !Task.isCancelled else { return }
                self.play(raw: sourceURL, half: half, processed: processed, range: range)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            self?.isRendering = false
        }
    }

    private func play(raw: URL, half: URL, processed: URL, range: TimeRange) {
        let rawPlayer = AVPlayer(url: raw)
        let halfPlayer = AVPlayer(url: half)
        let processedPlayer = AVPlayer(url: processed)
        rawPlayer.automaticallyWaitsToMinimizeStalling = false
        halfPlayer.automaticallyWaitsToMinimizeStalling = false
        processedPlayer.automaticallyWaitsToMinimizeStalling = false
        self.rawPlayer = rawPlayer
        self.halfPlayer = halfPlayer
        self.processedPlayer = processedPlayer
        applyVolumes()
        rawPlayer.seek(to: .seconds(range.start), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.rawPlayer === rawPlayer else { return }
                rawPlayer.playImmediately(atRate: 1)
                halfPlayer.playImmediately(atRate: 1)
                processedPlayer.playImmediately(atRate: 1)
                self.isPlaying = true
                self.stopTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(range.duration * 1_000_000_000))
                    if !Task.isCancelled { self?.stop() }
                }
            }
        }
    }

    private func applyVolumes() {
        rawPlayer?.volume = hearing == .raw ? 1 : 0
        halfPlayer?.volume = hearing == .half ? 1 : 0
        processedPlayer?.volume = hearing == .processed ? 1 : 0
    }

    func stop() {
        renderTask?.cancel()
        renderTask = nil
        stopTask?.cancel()
        stopTask = nil
        rawPlayer?.pause()
        halfPlayer?.pause()
        processedPlayer?.pause()
        rawPlayer = nil
        halfPlayer = nil
        processedPlayer = nil
        isPlaying = false
        isRendering = false
    }
}
