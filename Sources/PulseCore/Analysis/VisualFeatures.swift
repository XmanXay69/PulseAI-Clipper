import Foundation

/// Faces detected in one sampled frame (normalized, top-left origin).
public struct FaceSample: Codable, Hashable, Sendable {
    public var time: Seconds
    public var boxes: [NormRect]

    public init(time: Seconds, boxes: [NormRect]) {
        self.time = time
        self.boxes = boxes
    }
}

/// Coarse visual features sampled across a recording.
public struct VisualFeatureSeries: Codable, Hashable, Sendable {
    /// Seconds between samples.
    public var hop: Seconds
    /// Mean absolute luminance difference between consecutive samples (0…1).
    public var motion: FloatSeries
    /// Mean luminance (0…1).
    public var brightness: FloatSeries
    /// Detected hard cuts / scene changes.
    public var sceneCuts: [Seconds]
    public var faces: [FaceSample]
    /// Where on screen the motion happened per sample (#56), normalized 0…1 from the left / top; 0.5 when
    /// nothing moved. Nil on analyses made before the action centre was tracked.
    public var actionX: FloatSeries?
    public var actionY: FloatSeries?

    public init(hop: Seconds, motion: [Float], brightness: [Float], sceneCuts: [Seconds], faces: [FaceSample],
                actionX: [Float]? = nil, actionY: [Float]? = nil) {
        self.hop = hop
        self.motion = FloatSeries(motion)
        self.brightness = FloatSeries(brightness)
        self.sceneCuts = sceneCuts
        self.faces = faces
        self.actionX = actionX.map(FloatSeries.init)
        self.actionY = actionY.map(FloatSeries.init)
    }

    public var count: Int { motion.count }

    /// True when the analysis tracked where the action was.
    public var tracksAction: Bool { (actionX?.count ?? 0) == count && count > 0 }

    /// Where the action was at `t` (#56), nil when it wasn't tracked.
    public func actionCenter(at t: Seconds) -> Vec2? {
        guard tracksAction, let xs = actionX, hop > 0 else { return nil }
        let i = Int((t / hop).rounded(.down)).clamped(0, count - 1)
        return Vec2(Double(xs[i]), Double(actionY.map { $0.count == count ? $0[i] : 0.5 } ?? 0.5))
    }

    public func motion(at t: Seconds) -> Float {
        guard count > 0, hop > 0 else { return 0 }
        return motion[Int((t / hop).rounded(.down)).clamped(0, count - 1)]
    }

    public func meanMotion(in range: TimeRange) -> Float {
        guard count > 0, hop > 0 else { return 0 }
        let a = Int((range.start / hop).rounded(.down)).clamped(0, count - 1)
        let b = max(a, Int((range.end / hop).rounded(.down)).clamped(0, count - 1))
        var s: Float = 0
        for i in a...b { s += motion[i] }
        return s / Float(b - a + 1)
    }

    public func sceneCuts(in range: TimeRange) -> [Seconds] {
        sceneCuts.filter { range.contains($0) }
    }

    public func faces(in range: TimeRange) -> [FaceSample] {
        faces.filter { range.contains($0.time) }
    }
}

/// What kind of recording this looks like; drives default layouts.
public enum ContentProfile: String, Codable, CaseIterable, Sendable {
    /// Gameplay/screen with a small facecam overlay (typical Twitch VOD).
    case gameplayWithFacecam
    /// Gameplay/screen without a detectable face.
    case gameplay
    /// A person filling most of the frame (vlog, podcast camera, interview).
    case talkingHead
    /// Audio-first content.
    case podcast
    case unknown

    public var displayName: String {
        switch self {
        case .gameplayWithFacecam: return "Gameplay + Facecam"
        case .gameplay: return "Gameplay / Screen"
        case .talkingHead: return "Talking Head"
        case .podcast: return "Podcast"
        case .unknown: return "General"
        }
    }
}

/// Result of estimating where the streamer's webcam is inside a single-file recording.
public struct WebcamEstimate: Codable, Hashable, Sendable {
    /// Webcam overlay region (head + shoulders), normalized source coordinates.
    public var region: NormRect
    /// Average face box inside the region.
    public var face: NormRect
    /// Fraction of sampled frames where this face was found (0…1).
    public var persistence: Double
    public var profile: ContentProfile
}

/// Where the facecam sat during one stretch of a long stream (#46): overlays move between segments.
public struct WebcamSegment: Codable, Hashable, Sendable {
    public var range: TimeRange
    public var estimate: WebcamEstimate

    public init(range: TimeRange, estimate: WebcamEstimate) {
        self.range = range
        self.estimate = estimate
    }
}

public enum WebcamEstimator {
    /// The facecam position per stretch of the recording (#46): face detections are grouped into windows,
    /// each window estimated on its own, and consecutive windows whose facecam regions overlap are joined.
    /// Returns [] when the facecam never moved (one position for the whole recording), so callers fall back
    /// to the single estimate. Windows without a persistent face continue the previous stretch.
    public static func segments(faces samples: [FaceSample], frameSize: Size2, duration: Seconds,
                                window: Seconds = 60, minimumSegment: Seconds = 90) -> [WebcamSegment] {
        guard duration > 0, window > 0, !samples.isEmpty else { return [] }
        let count = max(1, Int((duration / window).rounded(.up)))
        var buckets = [[FaceSample]](repeating: [], count: count)
        for sample in samples where sample.time >= 0 {
            let i = min(count - 1, Int(sample.time / window))
            buckets[i].append(sample)
        }
        struct Run { var start: Int; var end: Int; var samples: [FaceSample]; var region: NormRect }
        var runs: [Run] = []
        for (i, bucket) in buckets.enumerated() {
            guard bucket.count >= 3, let estimate = estimate(faces: bucket, frameSize: frameSize), estimate.profile == .gameplayWithFacecam else {
                if !runs.isEmpty { runs[runs.count - 1].end = i }
                continue
            }
            if !runs.isEmpty, runs[runs.count - 1].region.iou(estimate.region) >= 0.4 {
                runs[runs.count - 1].end = i
                runs[runs.count - 1].samples += bucket
                continue
            }
            runs.append(Run(start: i, end: i, samples: bucket, region: estimate.region))
        }
        // Short detours (a quick move and back) fold into the stretch before them, and stretches that land back
        // on the same spot join up.
        var merged: [Run] = []
        for run in runs {
            let length = Double(run.end - run.start + 1) * window
            if var last = merged.last {
                if length < minimumSegment {
                    last.end = run.end
                    merged[merged.count - 1] = last
                    continue
                }
                if last.region.iou(run.region) >= 0.4 {
                    last.end = run.end
                    last.samples += run.samples
                    merged[merged.count - 1] = last
                    continue
                }
            }
            merged.append(run)
        }
        guard merged.count >= 2 else { return [] }
        var segments: [WebcamSegment] = []
        for (k, run) in merged.enumerated() {
            guard let estimate = estimate(faces: run.samples, frameSize: frameSize) else { continue }
            let start = k == 0 ? 0 : Double(run.start) * window
            let end = k == merged.count - 1 ? duration : min(duration, Double(run.end + 1) * window)
            segments.append(WebcamSegment(range: TimeRange(start: start, end: end), estimate: estimate))
        }
        return segments.count >= 2 ? segments : []
    }

    /// Clusters face detections over time to find a persistent face. Small persistent faces near an
    /// edge are a facecam overlay; large central faces mean talking-head footage.
    public static func estimate(faces samples: [FaceSample], frameSize: Size2) -> WebcamEstimate? {
        let sampleCount = samples.count
        guard sampleCount > 0 else { return nil }
        struct Cluster {
            var sumX = 0.0, sumY = 0.0, sumW = 0.0, sumH = 0.0
            var hits = 0
            var center: Vec2 { Vec2(sumX / Double(hits), sumY / Double(hits)) }
            var meanBox: NormRect {
                let w = sumW / Double(hits)
                let h = sumH / Double(hits)
                return NormRect(center: center, width: w, height: h)
            }
        }
        var clusters: [Cluster] = []
        for sample in samples {
            for box in sample.boxes where box.width > 0.01 && box.height > 0.01 {
                let c = box.center
                if let idx = clusters.firstIndex(where: { $0.center.distance(to: c) < max($0.meanBox.width, box.width) * 0.9 }) {
                    clusters[idx].sumX += c.x
                    clusters[idx].sumY += c.y
                    clusters[idx].sumW += box.width
                    clusters[idx].sumH += box.height
                    clusters[idx].hits += 1
                } else {
                    var cl = Cluster()
                    cl.sumX = c.x
                    cl.sumY = c.y
                    cl.sumW = box.width
                    cl.sumH = box.height
                    cl.hits = 1
                    clusters.append(cl)
                }
            }
        }
        guard let best = clusters.max(by: { $0.hits < $1.hits }) else { return nil }
        let persistence = Double(best.hits) / Double(sampleCount)
        guard persistence >= 0.25 else { return nil }
        let face = best.meanBox
        let faceArea = face.area
        let nearEdge = face.minX < 0.3 || face.maxX > 0.7 || face.minY < 0.3 || face.maxY > 0.7
        if faceArea > 0.035 && !(nearEdge && faceArea < 0.06) {
            // Big face → the camera IS the frame.
            let region = NormRect(center: face.center, width: min(face.width * 3.2, 1), height: min(face.height * 3.0, 1)).clampedToUnit()
            return WebcamEstimate(region: region, face: face, persistence: persistence, profile: .talkingHead)
        }
        // Facecam overlay: expand face box to a typical 16:9 or 4:3 webcam window, face in upper-middle.
        let frameAspect = frameSize.aspect
        let camHeight = min(face.height * 2.8, 0.6)
        // Webcams are usually ~4:3–16:9 in pixels; convert to normalized width.
        let camWidth = min(camHeight * (16.0 / 9.0) / frameAspect * 0.85, 0.6)
        var region = NormRect(x: face.center.x - camWidth / 2, y: face.center.y - camHeight * 0.42, width: camWidth, height: camHeight)
        // Overlays are usually flush with a frame edge — snap when close.
        let snap = 0.05
        if region.minX < snap { region.x = 0 }
        if region.minY < snap { region.y = 0 }
        if 1 - region.maxX < snap { region.x = 1 - region.width }
        if 1 - region.maxY < snap { region.y = 1 - region.height }
        return WebcamEstimate(region: region.clampedToUnit(), face: face, persistence: persistence, profile: .gameplayWithFacecam)
    }

    /// Crop for the gameplay panel that avoids the facecam where possible.
    public static func gameplayRegion(frameSize: Size2, webcam: NormRect?, targetAspect: Double) -> NormRect {
        var focus = Vec2(0.5, 0.5)
        if let webcam {
            // Shift the gameplay crop away from the webcam horizontally.
            focus.x = webcam.center.x < 0.5 ? 0.5 + min(webcam.width / 2, 0.15) : 0.5 - min(webcam.width / 2, 0.15)
        }
        return NormRect.crop(aspect: targetAspect, frameSize: frameSize, focus: focus)
    }
}

/// Everything PULSE learned about one media asset. Stored per asset in the project package.
public struct MediaAnalysis: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var assetID: UUID
    public var version: Int
    public var createdAt: Date
    public var duration: Seconds
    public var audio: AudioFeatureSeries?
    public var visual: VisualFeatureSeries?
    public var transcript: Transcript?
    public var webcam: WebcamEstimate?
    public var profile: ContentProfile
    /// Which steps ran locally vs in the cloud (shown in the privacy badge).
    public var processing: [String: ProcessingLocation]
    /// Imported chat replay (Twitch / YouTube), if any.
    public var chat: ChatLog?
    /// Banners read off the screen (wins, kills, deaths…) when the game banner reader ran; nil = not read.
    public var hudEvents: [HUDEvent]?
    /// Beat times of a music track once detected (#287): drawn as a grid on its clips.
    public var beats: [Seconds]?
    /// Where the facecam sat over the recording when it moved (#46); nil or empty = `webcam` everywhere.
    public var webcamSegments: [WebcamSegment]?

    /// The facecam estimate for a moment of the source (#46): the segment holding `time`, else the overall one.
    public func webcam(at time: Seconds) -> WebcamEstimate? {
        if let segments = webcamSegments, let hit = segments.first(where: { $0.range.contains(time) }) { return hit.estimate }
        return webcam
    }

    /// True when the facecam moved during the recording.
    public var facecamMoves: Bool { (webcamSegments?.count ?? 0) >= 2 }

    public init(assetID: UUID, duration: Seconds, audio: AudioFeatureSeries? = nil, visual: VisualFeatureSeries? = nil,
                transcript: Transcript? = nil, webcam: WebcamEstimate? = nil, profile: ContentProfile = .unknown,
                processing: [String: ProcessingLocation] = [:], createdAt: Date = Date()) {
        self.assetID = assetID
        self.version = MediaAnalysis.currentVersion
        self.createdAt = createdAt
        self.duration = duration
        self.audio = audio
        self.visual = visual
        self.transcript = transcript
        self.webcam = webcam
        self.profile = profile
        self.processing = processing
    }

    /// Infers the content profile from what was detected.
    public static func inferProfile(webcam: WebcamEstimate?, visual: VisualFeatureSeries?, transcript: Transcript?, hasVideo: Bool) -> ContentProfile {
        guard hasVideo else { return .podcast }
        if let webcam { return webcam.profile }
        if let visual, visual.count > 0 {
            let meanMotion = visual.motion.values.reduce(0, +) / Float(visual.count)
            if meanMotion > 0.015 || visual.sceneCuts.count > 3 { return .gameplay }
        }
        if let transcript, !transcript.isEmpty { return .unknown }
        return .unknown
    }
}
