import AVFoundation
import Foundation
import PulseCore

/// An AVFoundation composition ready for playback or export.
public final class BuiltComposition: @unchecked Sendable {
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix
    public let duration: Seconds
    public let scene: RenderScene
    /// Clips whose media couldn't be found (shown as "Media Offline").
    public let missingAssetIDs: Set<UUID>
    /// Enhance renders that weren't cached yet (`Options.renderEnhancements == false`): the clips
    /// play their original audio until these are rendered and the composition is rebuilt.
    public internal(set) var pendingEnhancements: [EnhanceRequest] = []

    public struct EnhanceRequest: Sendable {
        public var sourceURL: URL
        public var range: TimeRange
        public var settings: AudioSettings
        public var cacheDirectory: URL
    }

    init(composition: AVComposition, videoComposition: AVVideoComposition, audioMix: AVAudioMix, duration: Seconds, scene: RenderScene, missingAssetIDs: Set<UUID>) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.duration = duration
        self.scene = scene
        self.missingAssetIDs = missingAssetIDs
    }

    public func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        item.audioTimePitchAlgorithm = .spectral
        return item
    }
}

/// Turns a PULSE `Timeline` into AVComposition + custom video composition + audio mix.
/// Nothing is ever rendered into the source files — every edit stays live and non-destructive.
public enum CompositionBuilder {
    public struct Options: Sendable {
        /// Output pixel size; nil = canvas size.
        public var renderSize: CGSize?
        /// Use proxy media when available (playback only).
        public var useProxies: Bool
        public var includeCaptions: Bool
        public var showSafeArea: SafeAreaPlatform?
        /// Where rendered "Enhance" audio is cached; nil disables the enhance chain.
        public var enhanceCacheDirectory: URL?
        /// Nested timelines of compound clips (`ProjectDocument.compounds`).
        public var compounds: [UUID: Timeline] = [:]
        /// false = use only enhance renders that are already cached and report the rest as
        /// `pendingEnhancements` (the viewer: picture first, processed audio a moment later).
        /// Exports keep true and wait for every render.
        public var renderEnhancements = true

        public init(renderSize: CGSize? = nil, useProxies: Bool = false, includeCaptions: Bool = true, showSafeArea: SafeAreaPlatform? = nil,
                    enhanceCacheDirectory: URL? = PulseDirectories.cache("Enhanced Audio")) {
            self.renderSize = renderSize
            self.useProxies = useProxies
            self.includeCaptions = includeCaptions
            self.showSafeArea = showSafeArea
            self.enhanceCacheDirectory = enhanceCacheDirectory
        }
    }

    public static func build(timeline: Timeline, assets: [UUID: MediaAsset], options: Options = Options()) async throws -> BuiltComposition {
        let composition = AVMutableComposition()
        let duration = max(timeline.duration, 0.1)
        let renderSize = options.renderSize ?? CGSize(width: timeline.canvas.width, height: timeline.canvas.height)
        let captionData: CaptionRenderData? = {
            guard options.includeCaptions, let captions = timeline.captions, captions.isEnabled else { return nil }
            return CaptionRenderData(track: captions, timeline: timeline)
        }()
        let scene = RenderScene(canvas: timeline.canvas, renderSize: renderSize, captions: captionData, showSafeArea: options.showSafeArea)

        // Background filler keeps a video track alive so the compositor always runs (text-only, gaps).
        let filler = try await BlackFiller.shared.asset()
        if let fillerTrack = try await filler.loadTracks(withMediaType: .video).first,
           let bg = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let fillerDuration = try await filler.load(.duration)
            var t = CMTime.zero
            let end = CMTime.seconds(duration)
            while t < end {
                let chunk = CMTimeMinimum(fillerDuration, end - t)
                try bg.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: fillerTrack, at: t)
                t = t + chunk
            }
        }

        var pending: [BuiltComposition.EnhanceRequest] = []
        var assetCache: [URL: AVURLAsset] = [:]
        func avAsset(_ url: URL) -> AVURLAsset {
            if let a = assetCache[url] { return a }
            let a = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            assetCache[url] = a
            return a
        }
        var missing = Set<UUID>()
        func url(for asset: MediaAsset) -> URL? {
            if options.useProxies, let proxy = asset.preparation.proxyPath, FileManager.default.fileExists(atPath: proxy) {
                return URL(fileURLWithPath: proxy)
            }
            let resolved = MediaAccess.resolve(asset)
            guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
            return resolved
        }

        // Visual layers: (timeline track index, clip, content).
        struct PlacedLayer {
            var trackIndex: Int
            var clip: TimelineClip
            var content: RenderLayerContent
            var trackOpacity: Double
            /// When set, the layer is only visible in this window (dissolve handles).
            var window: TimeRange? = nil
            /// Draw order tweak within a track (handles sit just below the clip they blend with).
            var orderBias: Double = 0

            /// Layers inside a compound clip (drawn as one group).
            var children: [PlacedLayer] = []
            /// Draw order inside a compound (nested track kind + index).
            var childRank: Double? = nil

            var span: TimeRange { window ?? clip.timelineRange }
        }
        var placed: [PlacedLayer] = []

        // Compound clips: nested video clips get their own composition tracks; nested audio is
        // collected and mixed with the parent's audio tracks below.
        var nestedAudio: [(key: String, clip: TimelineClip)] = []
        func loadVideoSource(_ fileURL: URL) async throws -> (AVAssetTrack, Size2, CGImagePropertyOrientation)? {
            guard let source = try await avAsset(fileURL).loadTracks(withMediaType: .video).first else { return nil }
            let (naturalSize, transform) = try await source.load(.naturalSize, .preferredTransform)
            let orientation = CGImagePropertyOrientation(transform: transform)
            let size = orientation.swapsDimensions ? Size2(Double(naturalSize.height), Double(naturalSize.width)) : Size2(Double(naturalSize.width), Double(naturalSize.height))
            return (source, size, orientation)
        }
        func compoundAudio(_ compound: TimelineClip, depth: Int, visited: Set<UUID>) {
            guard let id = compound.content.compoundID, depth < CompoundEditor.maximumDepth, !visited.contains(id),
                  let nested = options.compounds[id], !compound.audio.isMuted else { return }
            let gain = compound.audio.volume.value(at: 0) * pow(10, compound.audio.gainDB / 20)
            guard gain > 0.0001 else { return }
            for piece in CompoundEditor.flatten(compound, nested: nested) {
                if piece.clip.content.compoundID != nil {
                    compoundAudio(piece.clip, depth: depth + 1, visited: visited.union([id]))
                } else if piece.trackKind == .audio, piece.clip.content.assetID != nil {
                    var c = piece.clip
                    c.audio.gainDB += 20 * log10(gain)
                    nestedAudio.append(("\(compound.id)-\(piece.trackIndex)", c))
                }
            }
        }
        func compoundLayer(_ compound: TimelineClip, trackIndex: Int, depth: Int, visited: Set<UUID>) async throws -> PlacedLayer? {
            guard let id = compound.content.compoundID, depth < CompoundEditor.maximumDepth, !visited.contains(id),
                  let nested = options.compounds[id] else { return nil }
            var children: [PlacedLayer] = []
            var nestedTracks: [Int: AVMutableCompositionTrack] = [:]
            for piece in CompoundEditor.flatten(compound, nested: nested) where piece.trackKind != .audio {
                let rank = (piece.trackKind == .text ? 1000.0 : 0) + Double(piece.trackIndex)
                let child = piece.clip
                switch child.content {
                case .text(let element):
                    children.append(PlacedLayer(trackIndex: trackIndex, clip: child, content: .text(element), trackOpacity: 1, childRank: rank))
                case .solid(let color):
                    children.append(PlacedLayer(trackIndex: trackIndex, clip: child, content: .solid(color), trackOpacity: 1, childRank: rank))
                case .compound:
                    if var inner = try await compoundLayer(child, trackIndex: trackIndex, depth: depth + 1, visited: visited.union([id])) {
                        inner.childRank = rank
                        children.append(inner)
                    }
                case .media(let assetID):
                    guard let asset = assets[assetID] else { missing.insert(assetID); continue }
                    guard let fileURL = url(for: asset) else { missing.insert(assetID); continue }
                    if asset.kind == .image {
                        children.append(PlacedLayer(trackIndex: trackIndex, clip: child, content: .image(url: fileURL, size: asset.metadata.size), trackOpacity: 1, childRank: rank))
                        continue
                    }
                    guard let loaded = try await loadVideoSource(fileURL) else { continue }
                    let (source, size, orientation) = loaded
                    if nestedTracks[piece.trackIndex] == nil {
                        nestedTracks[piece.trackIndex] = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    guard let track = nestedTracks[piece.trackIndex] else { continue }
                    let sourceRange = CMTimeRange(start: .seconds(child.sourceIn), duration: .seconds(child.sourceDuration))
                    let at = CMTime.seconds(child.start)
                    do {
                        try track.insertTimeRange(sourceRange, of: source, at: at)
                        if abs(child.speed - 1) > 0.001 {
                            track.scaleTimeRange(CMTimeRange(start: at, duration: sourceRange.duration), toDuration: .seconds(child.duration))
                        }
                    } catch {
                        missing.insert(assetID)
                        continue
                    }
                    children.append(PlacedLayer(trackIndex: trackIndex, clip: child, content: .video(trackID: track.trackID, sourceSize: size, orientation: orientation),
                                                trackOpacity: 1, childRank: rank))
                }
            }
            return PlacedLayer(trackIndex: trackIndex, clip: compound, content: .group([]), trackOpacity: 1, children: children)
        }

        for (ti, track) in timeline.tracks.enumerated() where track.kind == .video || track.kind == .text {
            guard !track.isHidden else { continue }
            var compTrack: AVMutableCompositionTrack?
            for clip in track.clips where clip.isEnabled && clip.duration > 0.001 {
                switch clip.content {
                case .text(let element):
                    placed.append(PlacedLayer(trackIndex: ti, clip: clip, content: .text(element), trackOpacity: 1))
                case .solid(let color):
                    placed.append(PlacedLayer(trackIndex: ti, clip: clip, content: .solid(color), trackOpacity: 1))
                case .compound:
                    if let layer = try await compoundLayer(clip, trackIndex: ti, depth: 0, visited: []) { placed.append(layer) }
                    compoundAudio(clip, depth: 0, visited: [])
                case .media(let assetID):
                    guard let asset = assets[assetID] else { missing.insert(assetID); continue }
                    guard let fileURL = url(for: asset) else { missing.insert(assetID); continue }
                    if asset.kind == .image {
                        placed.append(PlacedLayer(trackIndex: ti, clip: clip, content: .image(url: fileURL, size: asset.metadata.size), trackOpacity: 1))
                        continue
                    }
                    let av = avAsset(fileURL)
                    guard let source = try await av.loadTracks(withMediaType: .video).first else { continue }
                    let (naturalSize, transform) = try await source.load(.naturalSize, .preferredTransform)
                    let orientation = CGImagePropertyOrientation(transform: transform)
                    let size = orientation.swapsDimensions ? Size2(Double(naturalSize.height), Double(naturalSize.width)) : Size2(Double(naturalSize.width), Double(naturalSize.height))
                    if compTrack == nil {
                        compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    guard let compTrack else { continue }
                    let sourceRange = CMTimeRange(start: .seconds(clip.sourceIn), duration: .seconds(clip.sourceDuration))
                    let at = CMTime.seconds(clip.start)
                    do {
                        try compTrack.insertTimeRange(sourceRange, of: source, at: at)
                        if abs(clip.speed - 1) > 0.001 {
                            compTrack.scaleTimeRange(CMTimeRange(start: at, duration: sourceRange.duration), toDuration: .seconds(clip.duration))
                        }
                    } catch {
                        missing.insert(assetID)
                        continue
                    }
                    placed.append(PlacedLayer(trackIndex: ti, clip: clip, content: .video(trackID: compTrack.trackID, sourceSize: size, orientation: orientation), trackOpacity: 1))
                }
            }

            // True cross-dissolves between adjacent clips: the neighbour keeps playing into its media
            // handle on a helper track underneath, so both pictures move during the blend. Without a
            // handle (clip already at the end/start of its media) the clip fades over what's below.
            let ordered = track.clips.filter { $0.isEnabled && $0.duration > 0.001 }.sorted { $0.start < $1.start }
            var handleTrack: AVMutableCompositionTrack?
            var handleTrackEnd = -Double.infinity
            for (a, b) in zip(ordered, ordered.dropFirst()) where abs(a.end - b.start) < 0.02 {
                guard case .media(let aID) = a.content, case .media(let bID) = b.content,
                      let aAsset = assets[aID], let bAsset = assets[bID], aAsset.kind == .video, bAsset.kind == .video,
                      let aURL = url(for: aAsset), let bURL = url(for: bAsset) else { continue }
                struct Handle { var clip: TimelineClip; var url: URL; var source: TimeRange; var window: TimeRange }
                var handles: [Handle] = []
                if let t = b.transitionIn, t.kind == .crossDissolve, t.duration > 0 {
                    // Incoming clip B dissolves in: A continues past its out point.
                    let d = min(t.duration, b.duration)
                    let handle = d * a.speed
                    if a.sourceOut + handle <= aAsset.metadata.duration + 0.001 {
                        var ghost = a
                        ghost.sourceDuration += handle
                        ghost.transitionIn = nil
                        ghost.transitionOut = nil
                        handles.append(Handle(clip: ghost, url: aURL, source: TimeRange(start: a.sourceOut, duration: handle), window: TimeRange(start: b.start, duration: d)))
                    }
                }
                if let t = a.transitionOut, t.kind == .crossDissolve, t.duration > 0 {
                    // Outgoing clip A dissolves out: B starts early from before its in point.
                    let d = min(t.duration, a.duration)
                    let handle = d * b.speed
                    if b.sourceIn - handle >= -0.001 {
                        var ghost = b
                        ghost.start -= d
                        ghost.sourceIn = max(0, b.sourceIn - handle)
                        ghost.sourceDuration += handle
                        ghost.transitionIn = nil
                        ghost.transitionOut = nil
                        handles.append(Handle(clip: ghost, url: bURL, source: TimeRange(start: ghost.sourceIn, duration: handle), window: TimeRange(start: a.end - d, duration: d)))
                    }
                }
                for handle in handles.sorted(by: { $0.window.start < $1.window.start }) where handle.window.start >= handleTrackEnd - 1e-6 {
                    let av = avAsset(handle.url)
                    guard let source = try await av.loadTracks(withMediaType: .video).first else { continue }
                    let (naturalSize, transform) = try await source.load(.naturalSize, .preferredTransform)
                    let orientation = CGImagePropertyOrientation(transform: transform)
                    let size = orientation.swapsDimensions ? Size2(Double(naturalSize.height), Double(naturalSize.width)) : Size2(Double(naturalSize.width), Double(naturalSize.height))
                    if handleTrack == nil {
                        handleTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    guard let handleTrack else { continue }
                    let range = CMTimeRange(start: .seconds(handle.source.start), duration: .seconds(handle.source.duration))
                    let at = CMTime.seconds(handle.window.start)
                    do {
                        try handleTrack.insertTimeRange(range, of: source, at: at)
                        if abs(handle.clip.speed - 1) > 0.001 {
                            handleTrack.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: .seconds(handle.window.duration))
                        }
                    } catch {
                        continue
                    }
                    handleTrackEnd = handle.window.end
                    placed.append(PlacedLayer(trackIndex: ti, clip: handle.clip, content: .video(trackID: handleTrack.trackID, sourceSize: size, orientation: orientation),
                                              trackOpacity: 1, window: handle.window, orderBias: -0.5))
                }
            }
        }

        // Instructions: split the timeline wherever the set of visible layers changes.
        var boundaries = Set<Double>([0, duration])
        func addBoundaries(_ layers: [PlacedLayer]) {
            for layer in layers {
                boundaries.insert(max(0, min(layer.span.start, duration)))
                boundaries.insert(max(0, min(layer.span.end, duration)))
                addBoundaries(layer.children)
            }
        }
        addBoundaries(placed)
        let sorted = boundaries.sorted()
        // Text tracks draw above video tracks; within a kind, later tracks draw on top.
        func order(_ layer: PlacedLayer) -> Double {
            if let rank = layer.childRank { return rank + layer.orderBias }
            let kindRank = timeline.tracks[layer.trackIndex].kind == .text ? 1000.0 : 0
            return kindRank + Double(layer.trackIndex) + layer.orderBias
        }
        func renderLayers(_ layers: [PlacedLayer], at mid: Double) -> [RenderLayer] {
            layers.filter { $0.span.start <= mid && $0.span.end > mid }.sorted { order($0) < order($1) }.map { layer in
                if case .group = layer.content {
                    return RenderLayer(content: .group(renderLayers(layer.children, at: mid)), clip: layer.clip, trackOpacity: layer.trackOpacity)
                }
                return RenderLayer(content: layer.content, clip: layer.clip, trackOpacity: layer.trackOpacity)
            }
        }
        var instructions: [PulseCompositionInstruction] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) where b - a > 1e-6 {
            let mid = (a + b) / 2
            let layers = renderLayers(placed, at: mid)
            let range = CMTimeRange(start: .seconds(a), end: .seconds(b))
            instructions.append(PulseCompositionInstruction(timeRange: range, layers: layers, scene: scene))
        }
        // Make the instruction ranges exactly contiguous in CMTime (required by AVFoundation).
        if !instructions.isEmpty {
            var fixed: [PulseCompositionInstruction] = []
            var cursor = CMTime.zero
            for (i, ins) in instructions.enumerated() {
                let end = i == instructions.count - 1 ? max(composition.duration, ins.timeRange.end) : ins.timeRange.end
                fixed.append(PulseCompositionInstruction(timeRange: CMTimeRange(start: cursor, end: end), layers: ins.layers, scene: scene))
                cursor = end
            }
            instructions = fixed
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = PulseVideoCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, timeline.canvas.frameRate.rounded())))
        videoComposition.instructions = instructions

        // Audio.
        let audioMix = AVMutableAudioMix()
        var mixParameters: [AVMutableAudioMixInputParameters] = []
        let anySolo = timeline.tracks.contains { $0.kind == .audio && $0.isSolo }
        let dialogue = DuckingPlanner.dialogueRanges(in: timeline)
        let allClips = timeline.allClips
        for track in timeline.tracks where track.kind == .audio && !track.isMuted {
            for clip in track.clips where clip.isEnabled && clip.content.compoundID != nil {
                compoundAudio(clip, depth: 0, visited: [])
            }
        }
        var audioTracks = timeline.tracks.filter { $0.kind == .audio }
        let nestedKeys = nestedAudio.reduce(into: [String]()) { keys, item in if !keys.contains(item.key) { keys.append(item.key) } }
        for key in nestedKeys {
            var track = Track(kind: .audio, name: "Compound audio")
            track.clips = nestedAudio.filter { $0.key == key }.map(\.clip).sorted { $0.start < $1.start }
            audioTracks.append(track)
        }
        for track in audioTracks {
            let trackGain = (track.isMuted || (anySolo && !track.isSolo)) ? 0 : track.volume
            let crossfades = Self.audioCrossfades(on: track, allClips: allClips, assets: assets)
            var compTrack: AVMutableCompositionTrack?
            var handleTrack: AVMutableCompositionTrack?
            var ramps: [(time: Seconds, gain: Double)] = []
            var handleRamps: [(time: Seconds, gain: Double)] = []
            // Enhance renders cover whole stretches of the source, not each jump-cut piece: a long edit
            // has hundreds of pieces but only a few dozen stretches, and every render costs a decode.
            let spans = Self.enhanceSpans(track.clips.filter { $0.isEnabled }.compactMap { clip -> EnhanceSpanInput? in
                guard clip.audio.needsEnhanceRender, case .media(let id) = clip.content else { return nil }
                let tailLength = crossfades.tail[clip.id]?.sourceLength ?? 0
                return EnhanceSpanInput(clipID: clip.id, group: "\(id)|\(clip.audio.enhanceFingerprint)",
                                        range: TimeRange(start: clip.sourceIn, end: clip.sourceOut + tailLength))
            })
            for original in track.clips.sorted(by: { $0.start < $1.start }) where original.isEnabled {
                var clip = original
                if let fade = crossfades.fadeIn[clip.id] { clip.audio.fadeIn = max(clip.audio.fadeIn, fade) }
                let tail = crossfades.tail[clip.id]
                guard case .media(let assetID) = clip.content, let asset = assets[assetID] else { continue }
                guard let fileURL = url(for: asset) else { missing.insert(assetID); continue }
                let av = avAsset(fileURL)
                guard let source = try await av.loadTracks(withMediaType: .audio).first else { continue }
                if compTrack == nil {
                    compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                guard let compTrack else { continue }
                let at = CMTime.seconds(clip.start)
                var insertedDuration: CMTime?
                // What the tail handle (audio crossfade) is read from: same file as the clip body so
                // enhanced/normalized clips keep a consistent level through the fade.
                var tailSource: (track: AVAssetTrack, start: CMTime)?
                // Enhance chain: use the cached processed render of exactly this range (plus any
                // crossfade tail). Decoding can end a few samples short, so clamp to what was
                // rendered; on any problem fall back to the original audio.
                let renderRange = spans[clip.id] ?? TimeRange(start: clip.sourceIn, end: clip.sourceOut + (tail?.sourceLength ?? 0))
                let offset = max(0, clip.sourceIn - renderRange.start)
                var enhancedFile: URL?
                if clip.audio.needsEnhanceRender, let cacheDirectory = options.enhanceCacheDirectory {
                    if options.renderEnhancements {
                        enhancedFile = try? await AudioEnhancer.shared.render(sourceURL: fileURL, range: renderRange, settings: clip.audio, cacheDirectory: cacheDirectory)
                    } else {
                        enhancedFile = AudioEnhancer.cachedRender(sourceURL: fileURL, range: renderRange, settings: clip.audio, cacheDirectory: cacheDirectory)
                        if enhancedFile == nil, !pending.contains(where: { $0.sourceURL == fileURL && $0.range == renderRange && $0.settings.enhanceFingerprint == clip.audio.enhanceFingerprint }) {
                            pending.append(BuiltComposition.EnhanceRequest(sourceURL: fileURL, range: renderRange, settings: clip.audio, cacheDirectory: cacheDirectory))
                        }
                    }
                }
                if let enhancedURL = enhancedFile,
                   // Tracks only weakly reference their asset, so keep it in the builder's cache.
                   let enhancedTrack = try? await avAsset(enhancedURL).loadTracks(withMediaType: .audio).first,
                   let available = try? await enhancedTrack.load(.timeRange) {
                    let duration = CMTimeMinimum(CMTime.seconds(clip.sourceDuration), available.duration - CMTime.seconds(offset))
                    if duration.secondsValue > 0.01,
                       (try? compTrack.insertTimeRange(CMTimeRange(start: .seconds(offset), duration: duration), of: enhancedTrack, at: at)) != nil {
                        insertedDuration = duration
                        tailSource = (enhancedTrack, .seconds(offset + clip.sourceDuration))
                    }
                }
                if insertedDuration == nil {
                    let sourceRange = CMTimeRange(start: .seconds(clip.sourceIn), duration: .seconds(clip.sourceDuration))
                    do {
                        try compTrack.insertTimeRange(sourceRange, of: source, at: at)
                        insertedDuration = sourceRange.duration
                        tailSource = (source, .seconds(clip.sourceOut))
                    } catch {
                        missing.insert(assetID)
                        continue
                    }
                }
                if let insertedDuration, abs(clip.speed - 1) > 0.001 {
                    compTrack.scaleTimeRange(CMTimeRange(start: at, duration: insertedDuration),
                                             toDuration: .seconds(insertedDuration.secondsValue / clip.speed))
                }
                ramps.append(contentsOf: gainAutomation(for: clip, trackGain: trackGain, dialogue: dialogue))

                // Crossfade tail: this clip keeps playing past its out point on a helper track and
                // fades out while the next clip fades in.
                if let tail, let tailSource {
                    if handleTrack == nil {
                        handleTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    if let handleTrack {
                        let range = CMTimeRange(start: tailSource.start, duration: .seconds(tail.sourceLength))
                        let tailAt = CMTime.seconds(clip.end)
                        if (try? handleTrack.insertTimeRange(range, of: tailSource.track, at: tailAt)) != nil {
                            if abs(clip.speed - 1) > 0.001 {
                                handleTrack.scaleTimeRange(CMTimeRange(start: tailAt, duration: range.duration), toDuration: .seconds(tail.duration))
                            }
                            var body = clip
                            body.audio.fadeOut = 0
                            let endGain = body.audio.gain(at: clip.duration, clipDuration: clip.duration) * trackGain
                            handleRamps.append((clip.end, endGain))
                            handleRamps.append((clip.end + tail.duration, 0))
                        }
                    }
                }
            }
            if let compTrack {
                let params = AVMutableAudioMixInputParameters(track: compTrack)
                applyRamps(ramps, to: params)
                mixParameters.append(params)
            }
            if let handleTrack {
                let params = AVMutableAudioMixInputParameters(track: handleTrack)
                applyRamps(handleRamps, to: params)
                mixParameters.append(params)
            }
        }
        audioMix.inputParameters = mixParameters

        let built = BuiltComposition(composition: composition.copy() as! AVComposition, videoComposition: videoComposition.copy() as! AVVideoComposition,
                                     audioMix: audioMix.copy() as! AVAudioMix, duration: duration, scene: scene, missingAssetIDs: missing)
        built.pendingEnhancements = pending
        return built
    }

    /// Audio crossfades under video dissolves. For adjacent clips A → B on an audio track where B (or
    /// its linked video) dissolves in, or A (or its linked video) dissolves out, A gets a tail of
    /// `duration` that fades out under B, and B fades in. Needs media after A's out point.
    struct AudioCrossfades {
        struct Tail { var duration: Seconds; var sourceLength: Seconds }
        var tail: [UUID: Tail] = [:]
        var fadeIn: [UUID: Seconds] = [:]
    }

    struct EnhanceSpanInput {
        var clipID: UUID
        /// Same source + same enhance settings.
        var group: String
        var range: TimeRange
    }

    /// Joins clips of the same source and settings whose source ranges are close (≤ 20 s apart) into
    /// stretches of at most 2 minutes (short enough that progress moves). Returns each clip's stretch.
    static func enhanceSpans(_ inputs: [EnhanceSpanInput], gap: Seconds = 20, maxLength: Seconds = 120) -> [UUID: TimeRange] {
        var result: [UUID: TimeRange] = [:]
        for (_, items) in Dictionary(grouping: inputs, by: \.group) {
            var current: (range: TimeRange, ids: [UUID])?
            func flush() {
                if let current { for id in current.ids { result[id] = current.range } }
            }
            for item in items.sorted(by: { $0.range.start < $1.range.start }) {
                if var c = current, item.range.start - c.range.end <= gap, max(c.range.end, item.range.end) - c.range.start <= maxLength {
                    c.range = TimeRange(start: c.range.start, end: max(c.range.end, item.range.end))
                    c.ids.append(item.clipID)
                    current = c
                } else {
                    flush()
                    current = (item.range, [item.clipID])
                }
            }
            flush()
        }
        return result
    }

    static func audioCrossfades(on track: Track, allClips: [TimelineClip], assets: [UUID: MediaAsset]) -> AudioCrossfades {
        var result = AudioCrossfades()
        func dissolve(_ clip: TimelineClip, incoming: Bool) -> Seconds? {
            let own = incoming ? clip.transitionIn : clip.transitionOut
            if let own, own.kind == .crossDissolve, own.duration > 0 { return own.duration }
            guard let group = clip.linkGroup else { return nil }
            for other in allClips where other.linkGroup == group && other.id != clip.id && other.isVisual {
                let t = incoming ? other.transitionIn : other.transitionOut
                if let t, t.kind == .crossDissolve, t.duration > 0 { return t.duration }
            }
            return nil
        }
        let ordered = track.clips.filter(\.isEnabled).sorted { $0.start < $1.start }
        for (a, b) in zip(ordered, ordered.dropFirst()) where abs(a.end - b.start) < 0.02 {
            guard let d = dissolve(b, incoming: true) ?? dissolve(a, incoming: false),
                  case .media(let assetID) = a.content, let asset = assets[assetID] else { continue }
            let duration = min(d, b.duration, a.duration)
            let sourceLength = duration * a.speed
            guard duration > 0.01, a.sourceOut + sourceLength <= asset.metadata.duration + 0.001 else { continue }
            result.tail[a.id] = AudioCrossfades.Tail(duration: duration, sourceLength: sourceLength)
            result.fadeIn[b.id] = duration
        }
        return result
    }

    /// Samples a clip's gain (volume keyframes, gain, fades, ducking) into ramp points.
    static func gainAutomation(for clip: TimelineClip, trackGain: Double, dialogue: [TimeRange]) -> [(time: Seconds, gain: Double)] {
        let ducking = clip.audio.duckUnderDialogue ? DuckingPlanner.envelope(for: clip, dialogue: dialogue) : []
        func duckGain(at t: Seconds) -> Double {
            guard !ducking.isEmpty else { return 1 }
            guard let upper = ducking.firstIndex(where: { $0.time >= t }) else { return ducking.last!.gain }
            if upper == 0 { return ducking[0].gain }
            let a = ducking[upper - 1]
            let b = ducking[upper]
            let span = b.time - a.time
            return span > 0 ? a.gain + (b.gain - a.gain) * (t - a.time) / span : b.gain
        }
        let animated = clip.audio.volume.isAnimated || clip.audio.fadeIn > 0 || clip.audio.fadeOut > 0 || !ducking.isEmpty
        if !animated {
            let g = clip.audio.gain(at: 0, clipDuration: clip.duration) * trackGain
            return [(clip.start, g), (clip.end, g)]
        }
        var points: [(time: Seconds, gain: Double)] = []
        let step = 0.05
        var t = 0.0
        while t < clip.duration {
            let g = clip.audio.gain(at: t, clipDuration: clip.duration) * duckGain(at: clip.start + t) * trackGain
            points.append((clip.start + t, g))
            t += step
        }
        points.append((clip.end, clip.audio.gain(at: clip.duration, clipDuration: clip.duration) * duckGain(at: clip.end) * trackGain))
        // Drop redundant points (same gain as neighbours) to keep the mix light.
        var reduced: [(time: Seconds, gain: Double)] = []
        for (i, p) in points.enumerated() {
            if i > 0, i < points.count - 1, abs(p.gain - points[i - 1].gain) < 0.001, abs(p.gain - points[i + 1].gain) < 0.001 { continue }
            reduced.append(p)
        }
        return reduced
    }

    static func applyRamps(_ points: [(time: Seconds, gain: Double)], to params: AVMutableAudioMixInputParameters) {
        let sorted = points.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return }
        params.setVolume(Float(first.gain), at: .seconds(first.time))
        for (a, b) in zip(sorted, sorted.dropFirst()) where b.time - a.time > 0.0005 {
            params.setVolumeRamp(fromStartVolume: Float(a.gain), toEndVolume: Float(b.gain),
                                 timeRange: CMTimeRange(start: .seconds(a.time), end: .seconds(b.time)))
        }
    }
}

/// A tiny black H.264 movie inserted under everything so the compositor always has a video track.
public actor BlackFiller {
    public static let shared = BlackFiller()
    private var cached: AVURLAsset?

    public func asset() async throws -> AVURLAsset {
        if let cached { return cached }
        let url = PulseDirectories.cache("Support").appendingPathComponent("black-filler-v1.mov")
        if !FileManager.default.fileExists(atPath: url.path) {
            try await BlackFiller.write(to: url)
        }
        let asset = AVURLAsset(url: url)
        cached = asset
        return asset
    }

    static func write(to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw EngineError.exportFailed(writer.error?.localizedDescription ?? "filler") }
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 30
        for frame in 0..<(Int(fps) * 4) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw EngineError.exportFailed(writer.error?.localizedDescription ?? "couldn't create filler video")
        }
    }
}
