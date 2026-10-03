import AVFoundation
import Combine
import Foundation
import PulseCore

/// Drives the editor viewer: rebuilds the live composition when the timeline changes (debounced),
/// keeps the playhead, and offers frame-accurate transport.
@MainActor
public final class PlaybackController: ObservableObject {
    @Published public private(set) var currentTime: Seconds = 0
    @Published public private(set) var duration: Seconds = 0
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isBuilding = false
    /// Processed audio for the open edit is still rendering (the picture is already showing).
    @Published public private(set) var isEnhancingAudio = false
    /// 0…1 while leveled audio renders.
    @Published public private(set) var enhanceProgress: Double = 0
    @Published public private(set) var missingAssetIDs: Set<UUID> = []
    @Published public private(set) var lastError: String?
    @Published public var loopEnabled = false
    @Published public var volume: Float = 1 {
        didSet { player.volume = volume }
    }

    public let player = AVPlayer()
    public private(set) var frameRate: Double = 30
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?
    private var buildTask: Task<Void, Never>?
    private var buildGeneration = 0
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    /// A seek requested while a composition is building; applied once it's installed.
    private var pendingSeek: Seconds?

    public init() {
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.secondsValue
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let playing = player.rate != 0
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    /// Rebuilds the composition for `timeline`. Rapid successive calls (slider drags) are coalesced.
    public func load(timeline: Timeline, assets: [UUID: MediaAsset], compounds: [UUID: Timeline] = [:], useProxies: Bool,
                     safeArea: SafeAreaPlatform? = nil, debounce: Double = 0.08) {
        buildTask?.cancel()
        buildGeneration += 1
        isEnhancingAudio = false
        let generation = buildGeneration
        frameRate = timeline.canvas.frameRate
        isBuilding = true
        buildTask = Task { [weak self] in
            if debounce > 0 { try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000)) }
            if Task.isCancelled { return }
            do {
                let built = try await CompositionBuilder.build(timeline: timeline, assets: assets,
                                                               options: Self.options(useProxies: useProxies, safeArea: safeArea, compounds: compounds))
                guard let self, !Task.isCancelled, generation == self.buildGeneration else { return }
                // Picture first: the edit shows immediately with the original audio…
                self.install(built)
                // …then any processed ("Enhance"/normalized) audio renders in the background and is
                // swapped in without moving the playhead.
                let pending = built.pendingEnhancements
                guard !pending.isEmpty else { return }
                self.isEnhancingAudio = true
                self.enhanceProgress = 0
                await Self.render(pending) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.buildGeneration else { return }
                        self.enhanceProgress = fraction
                    }
                }
                guard !Task.isCancelled, generation == self.buildGeneration else { return }
                let finished = try await CompositionBuilder.build(timeline: timeline, assets: assets,
                                                                  options: Self.options(useProxies: useProxies, safeArea: safeArea, compounds: compounds))
                guard !Task.isCancelled, generation == self.buildGeneration else { return }
                self.install(finished)
                self.isEnhancingAudio = false
            } catch {
                guard let self, generation == self.buildGeneration else { return }
                self.lastError = error.localizedDescription
                self.isBuilding = false
            }
        }
    }

    nonisolated static func options(useProxies: Bool, safeArea: SafeAreaPlatform?, compounds: [UUID: Timeline]) -> CompositionBuilder.Options {
        var options = CompositionBuilder.Options(useProxies: useProxies, showSafeArea: safeArea)
        options.compounds = compounds
        options.renderEnhancements = false
        return options
    }

    /// Renders the enhance chains a few at a time (each is one decode + DSP pass of a short range).
    nonisolated static func render(_ requests: [BuiltComposition.EnhanceRequest], progress: @escaping @Sendable (Double) -> Void) async {
        // Few at a time and below playback's priority, so the viewer stays responsive meanwhile.
        let width = max(2, min(3, ProcessInfo.processInfo.activeProcessorCount / 4))
        let total = Double(max(requests.count, 1))
        let done = ProgressTally()
        await withTaskGroup(of: Void.self) { group in
            for (i, r) in requests.enumerated() {
                if Task.isCancelled { break }
                // Keep at most `width` renders in flight.
                if i >= width { _ = await group.next() }
                group.addTask(priority: .utility) {
                    _ = try? await AudioEnhancer.shared.render(sourceURL: r.sourceURL, range: r.range, settings: r.settings,
                                                               cacheDirectory: r.cacheDirectory, priority: .utility)
                    progress(Double(done.increment()) / total)
                }
            }
            await group.waitForAll()
        }
    }

    private func install(_ built: BuiltComposition) {
        let time = player.currentTime()
        let wasPlaying = isPlaying
        let item = built.makePlayerItem()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.loopEnabled else { return }
                self.seek(to: 0)
                self.player.play()
            }
        }
        // A composition AVFoundation can't play would otherwise just sit there: say why.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Playback failed"
            Task { @MainActor in
                PulseLog.error("Viewer item failed: \(message)")
                self?.lastError = message
            }
        }
        player.replaceCurrentItem(with: item)
        duration = built.duration
        missingAssetIDs = built.missingAssetIDs
        lastError = nil
        let target = min(pendingSeek ?? time.secondsValue, max(built.duration - 1 / max(frameRate, 1), 0))
        pendingSeek = nil
        player.seek(to: .seconds(target), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        if wasPlaying { player.play() }
        isBuilding = false
    }

    // MARK: Transport

    public func play() {
        if currentTime >= duration - 0.05 { seek(to: 0) }
        player.playImmediately(atRate: 1)
    }

    /// For diagnostics: what the player item is doing.
    public var itemStatusDescription: String {
        guard let item = player.currentItem else { return "no item" }
        switch item.status {
        case .readyToPlay: return "ready"
        case .failed: return "failed: \(item.error?.localizedDescription ?? "?")"
        default: return "loading"
        }
    }

    public func pause() { player.pause() }

    public func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Frame-accurate seek.
    public func seek(to seconds: Seconds) {
        if isBuilding { pendingSeek = max(0, seconds) }
        let t = max(0, min(seconds, duration))
        currentTime = t
        player.seek(to: .seconds(t), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func step(frames: Int) {
        pause()
        seek(to: currentTime + Double(frames) / max(frameRate, 1))
    }

    /// J/K/L-style shuttle.
    public func shuttle(rate: Float) {
        player.rate = rate
    }

    public func goToStart() { seek(to: 0) }
    public func goToEnd() { seek(to: duration) }
}

/// Thread-safe tally for background progress.
final class ProgressTally: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
