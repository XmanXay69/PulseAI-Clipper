import AVFoundation
import Combine
import CoreImage
import Foundation
import PulseCore

/// Drives the editor viewer: rebuilds the live composition when the timeline changes (debounced),
/// keeps the playhead, and offers frame-accurate transport.
/// The playhead position, published on its own so only the few views that show live time (playhead,
/// timecode, handles) redraw while playing or scrubbing — not the whole timeline and inspector.
@MainActor
public final class PlayheadClock: ObservableObject {
    @Published public internal(set) var time: Seconds = 0
    public init() {}
}

@MainActor
public final class PlaybackController: ObservableObject {
    /// ~30 updates a second: playhead line, timecode, canvas handles.
    public let clock = PlayheadClock()
    /// About 4 updates a second: heavier panels (transcript, captions word list, inspector).
    public let slowClock = PlayheadClock()

    /// Not @Published on purpose (see `clock`).
    public private(set) var currentTime: Seconds {
        get { clock.time }
        set {
            clock.time = newValue
            if abs(newValue - slowClock.time) >= 0.25 { slowClock.time = newValue }
        }
    }
    @Published public private(set) var duration: Seconds = 0
    @Published public private(set) var isPlaying = false
    /// The player's live rate (0 when paused, 1 for normal play, ±2/4/8 while shuttling, negative backwards).
    /// Drives the transport bar's speed readout so J/K/L presses are visible, not just audible.
    @Published public private(set) var playbackRate: Float = 0
    @Published public private(set) var isBuilding = false
    /// Playback fell behind real time for a stretch (#187): the app drops the viewer quality a step
    /// when it's allowed to. Reset on every rebuild.
    @Published public private(set) var isStruggling = false
    /// What the current composition renders at (1 = canvas size).
    @Published public private(set) var renderScale: Double = 1
    /// The picture that was showing when the last rebuild started (#204): the viewer keeps it, dimmed,
    /// until the new composition is ready instead of flashing black.
    @Published public private(set) var lastFrame: CGImage?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var lastTimelineID: UUID?
    private lazy var snapshotContext = CIContext(options: [.cacheIntermediates: false])
    private var paceSamples = 0
    private var laggingSamples = 0
    private var lastTick: (wall: TimeInterval, media: Seconds)?
    /// Processed audio for the open edit is still rendering (the picture is already showing).
    @Published public private(set) var isEnhancingAudio = false
    /// 0…1 while leveled audio renders.
    @Published public private(set) var enhanceProgress: Double = 0
    @Published public private(set) var missingAssetIDs: Set<UUID> = []
    @Published public private(set) var lastError: String?
    @Published public var loopEnabled = false
    /// Hear a short blip of audio when the scrub settles (#156).
    public var audioScrub = false
    private var scrubBlip: Task<Void, Never>?
    /// With `loopEnabled`, loop this stretch instead of the whole timeline (in → out, #159).
    @Published public var loopRange: TimeRange?
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
                // While scrubbing the playhead already shows where the mouse is.
                guard let self, !self.isSeekingForScrub else { return }
                self.currentTime = time.secondsValue
                self.samplePace(media: time.secondsValue)
                if self.loopEnabled, self.isPlaying, let r = self.loopRange, r.duration > 0.1, self.currentTime >= r.end - 0.03 {
                    self.seek(to: r.start)
                    self.player.play()
                }
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let rate = player.rate
            Task { @MainActor in
                guard let self, self.scrubBlip == nil else { return }   // a scrub blip is not "playing"
                self.isPlaying = rate != 0
                self.playbackRate = rate
            }
        }
    }

    /// Media time should advance with the clock while playing at 1×; when it keeps falling short the
    /// renderer can't keep up with the canvas size.
    private func samplePace(media: Seconds) {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastTick = (now, media) }
        guard isPlaying, abs(playbackRate - 1) < 0.01, let last = lastTick else { return }
        let wall = now - last.wall
        guard wall > 0.02, wall < 0.5 else { return }
        paceSamples += 1
        if media - last.media < wall * 0.7 { laggingSamples += 1 }
        if paceSamples >= 45 {   // ~1.5 s of playback
            if laggingSamples >= paceSamples / 3, !isStruggling { isStruggling = true }
            paceSamples = 0
            laggingSamples = 0
        }
    }

    /// Rebuilds the composition for `timeline`. Rapid successive calls (slider drags) are coalesced.
    /// `renderScale` shrinks the viewer's frames (#187): 0.5 renders at half the canvas size.
    public func load(timeline: Timeline, assets: [UUID: MediaAsset], compounds: [UUID: Timeline] = [:], useProxies: Bool,
                     safeArea: SafeAreaPlatform? = nil, debounce: Double = 0.08, renderScale: Double = 1) {
        buildTask?.cancel()
        buildGeneration += 1
        isEnhancingAudio = false
        let generation = buildGeneration
        frameRate = timeline.canvas.frameRate
        if lastTimelineID != timeline.id { lastFrame = nil; lastTimelineID = timeline.id } else if !isBuilding { captureLastFrame() }
        isBuilding = true
        isStruggling = false
        paceSamples = 0
        laggingSamples = 0
        lastTick = nil
        self.renderScale = renderScale
        var renderSize: CGSize?
        if renderScale < 0.999 {
            let quality = PlaybackQuality.allCases.first { abs($0.scale - renderScale) < 0.01 } ?? .half
            let size = quality.renderSize(width: timeline.canvas.width, height: timeline.canvas.height)
            renderSize = CGSize(width: size.width, height: size.height)
        }
        buildTask = Task { [weak self] in
            if debounce > 0 { try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000)) }
            if Task.isCancelled { return }
            do {
                let built = try await CompositionBuilder.build(timeline: timeline, assets: assets,
                                                               options: Self.options(useProxies: useProxies, safeArea: safeArea, compounds: compounds, renderSize: renderSize))
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
                                                                  options: Self.options(useProxies: useProxies, safeArea: safeArea, compounds: compounds, renderSize: renderSize))
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

    nonisolated static func options(useProxies: Bool, safeArea: SafeAreaPlatform?, compounds: [UUID: Timeline], renderSize: CGSize? = nil) -> CompositionBuilder.Options {
        var options = CompositionBuilder.Options(renderSize: renderSize, useProxies: useProxies, showSafeArea: safeArea)
        options.compounds = compounds
        options.renderEnhancements = false
        return options
    }

    /// Renders the enhance chains a few at a time (each is one decode + DSP pass of a short range).
    nonisolated static func render(_ requests: [BuiltComposition.EnhanceRequest], progress: @escaping @Sendable (Double) -> Void) async {
        // Few at a time and below playback's priority, so the viewer stays responsive meanwhile.
        let width = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 3))
        let tally = ProgressTally(count: requests.count)
        await withTaskGroup(of: Void.self) { group in
            for (i, r) in requests.enumerated() {
                if Task.isCancelled { break }
                // Keep at most `width` renders in flight.
                if i >= width { _ = await group.next() }
                group.addTask(priority: .medium) {
                    _ = try? await AudioEnhancer.shared.render(sourceURL: r.sourceURL, range: r.range, settings: r.settings,
                                                               cacheDirectory: r.cacheDirectory, priority: .medium,
                                                               progress: { f in progress(tally.set(i, f)) })
                    progress(tally.set(i, 1))
                }
            }
            await group.waitForAll()
        }
    }

    /// The frame the player is showing right now, for scopes and grade matching (#310).
    public func currentFrame() -> CGImage? {
        guard let output = videoOutput, let item = player.currentItem,
              let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil) else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        return snapshotContext.createCGImage(image, from: image.extent)
    }

    /// Copies the frame the player is showing right now into `lastFrame`.
    private func captureLastFrame() {
        guard let output = videoOutput, let item = player.currentItem else { return }
        let time = item.currentTime()
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        if let cg = snapshotContext.createCGImage(image, from: image.extent) { lastFrame = cg }
    }

    private func install(_ built: BuiltComposition) {
        let time = player.currentTime()
        let wasPlaying = isPlaying
        let item = built.makePlayerItem()
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        videoOutput = output
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.loopEnabled else { return }
                self.seek(to: self.loopRange?.start ?? 0)
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
        scrubBlip?.cancel()
        scrubBlip = nil
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

    public func pause() { player.pause(); shuttleRate = 0 }

    /// J/K/L shuttle: L plays forward (1×, then 2×, 4×, 8× on each press), J the same backwards when the
    /// composition can play in reverse (otherwise it jumps back a second per press), K stops.
    public private(set) var shuttleRate: Float = 0

    public func shuttle(_ direction: Int) {
        guard direction != 0 else { pause(); return }
        let forward = direction > 0
        let sameWay = forward ? shuttleRate > 0 : shuttleRate < 0
        let magnitude: Float = sameWay ? min(abs(shuttleRate) * 2, 8) : 1
        if !forward, !(player.currentItem?.canPlayReverse ?? false) {
            seek(to: max(0, currentTime - 1))
            shuttleRate = 0
            return
        }
        if forward, currentTime >= duration - 0.05 { seek(to: 0) }
        shuttleRate = forward ? magnitude : -magnitude
        player.playImmediately(atRate: shuttleRate)
    }

    public func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Frame-accurate seek.
    public func seek(to seconds: Seconds) {
        if isBuilding { pendingSeek = max(0, seconds) }
        let t = max(0, min(seconds, duration))
        currentTime = t
        chaseTarget = nil
        player.seek(to: .seconds(t), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Scrubbing: the playhead follows the mouse instantly; the picture follows as fast as the decoder can.
    /// Only one seek is in flight — while it runs, newer targets replace each other and the latest is
    /// sought next ("chase" seeking), so dragging never queues up a backlog of exact-frame decodes.
    public func scrub(to seconds: Seconds) {
        let t = max(0, min(seconds, duration))
        currentTime = t
        if isBuilding { pendingSeek = t; return }
        chaseTarget = t
        guard !isSeekingForScrub else { return }
        chaseNext()
    }

    private var chaseTarget: Seconds?
    private var isSeekingForScrub = false

    private func chaseNext() {
        guard let target = chaseTarget else {
            isSeekingForScrub = false
            if audioScrub, !isPlaying { blip() }
            return
        }
        chaseTarget = nil
        isSeekingForScrub = true
        player.seek(to: .seconds(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.chaseNext() }
        }
    }

    /// Audio scrub (#156): play about 90 ms from the new position, then stop where we were.
    private func blip() {
        scrubBlip?.cancel()
        let position = player.currentTime()
        scrubBlip = Task { @MainActor [weak self] in
            guard let self else { return }
            self.player.playImmediately(atRate: 1)
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled, self.scrubBlip != nil else { return }
            self.player.pause()
            _ = await self.player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
            self.scrubBlip = nil
        }
    }

    /// Lands exactly on frame starts (#178), so a hundred steps at 29.97 are still a hundred frames.
    public func step(frames: Int) {
        pause()
        seek(to: Timecode.stepped(currentTime, frames: frames, fps: max(frameRate, 1)))
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
    private var parts: [Double]

    init(count: Int) { parts = Array(repeating: 0, count: max(count, 1)) }

    /// Records one job's fraction and returns the overall fraction.
    func set(_ index: Int, _ fraction: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        if parts.indices.contains(index) { parts[index] = max(parts[index], fraction) }
        return parts.reduce(0, +) / Double(parts.count)
    }
}
