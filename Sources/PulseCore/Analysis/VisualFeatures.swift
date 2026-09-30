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

    public init(hop: Seconds, motion: [Float], brightness: [Float], sceneCuts: [Seconds], faces: [FaceSample]) {
        self.hop = hop
        self.motion = FloatSeries(motion)
        self.brightness = FloatSeries(brightness)
        self.sceneCuts = sceneCuts
        self.faces = faces
    }

    public var count: Int { motion.count }

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

public enum WebcamEstimator {
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
