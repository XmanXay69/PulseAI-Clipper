import Foundation

public enum VideoCodec: String, Codable, CaseIterable, Sendable {
    case h264
    case hevc
    case proRes422

    public var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        case .proRes422: return "Apple ProRes 422"
        }
    }

    public var fileExtension: String { self == .proRes422 ? "mov" : "mp4" }
}

public enum ExportQuality: String, Codable, CaseIterable, Sendable {
    case draft, standard, high, maximum

    public var displayName: String { rawValue.capitalized }

    /// Multiplier applied to the preset's base bitrate.
    public var bitrateFactor: Double {
        switch self {
        case .draft: return 0.5
        case .standard: return 1
        case .high: return 1.5
        case .maximum: return 2.2
        }
    }
}

/// A named export configuration.
public struct ExportPreset: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    /// nil = timeline frame rate.
    public var frameRate: Double?
    public var codec: VideoCodec
    /// Video bitrate in bits per second at `.standard` quality.
    public var videoBitrate: Int
    public var audioBitrate: Int
    public var symbolName: String

    public init(id: String, name: String, width: Int, height: Int, frameRate: Double? = nil, codec: VideoCodec = .h264,
                videoBitrate: Int, audioBitrate: Int = 192_000, symbolName: String = "film") {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.videoBitrate = videoBitrate
        self.audioBitrate = audioBitrate
        self.symbolName = symbolName
    }

    public static let tiktok = ExportPreset(id: "tiktok", name: "TikTok", width: 1080, height: 1920, videoBitrate: 12_000_000, symbolName: "music.note")
    public static let shorts = ExportPreset(id: "shorts", name: "YouTube Shorts", width: 1080, height: 1920, videoBitrate: 12_000_000, symbolName: "play.rectangle")
    public static let reels = ExportPreset(id: "reels", name: "Instagram Reels", width: 1080, height: 1920, videoBitrate: 10_000_000, symbolName: "camera")
    public static let youtube = ExportPreset(id: "youtube", name: "YouTube 1080p", width: 1920, height: 1080, videoBitrate: 16_000_000, symbolName: "play.tv")
    public static let youtube4K = ExportPreset(id: "youtube4k", name: "4K", width: 3840, height: 2160, codec: .hevc, videoBitrate: 45_000_000, audioBitrate: 256_000, symbolName: "4k.tv")
    public static let twitter = ExportPreset(id: "twitter", name: "Twitter / X", width: 1920, height: 1080, videoBitrate: 10_000_000, symbolName: "bubble.left")
    public static let master = ExportPreset(id: "master", name: "ProRes Master", width: 1080, height: 1920, codec: .proRes422, videoBitrate: 120_000_000, audioBitrate: 320_000, symbolName: "film.stack")

    public static let builtIn: [ExportPreset] = [.tiktok, .shorts, .reels, .youtube, .youtube4K, .twitter, .master]

    public static func preset(id: String) -> ExportPreset? { builtIn.first { $0.id == id } }

    public var resolutionLabel: String { "\(width) × \(height)" }
}

/// Final export parameters for one job.
public struct ExportSettings: Codable, Hashable, Sendable {
    public var presetID: String
    public var width: Int
    public var height: Int
    /// nil = timeline frame rate.
    public var frameRate: Double?
    public var codec: VideoCodec
    public var videoBitrate: Int
    public var audioBitrate: Int
    public var quality: ExportQuality
    /// Tokens: {project} {clip} {preset} {date} {index}
    public var filenameTemplate: String
    public var outputDirectory: String
    public var useHardwareEncoding: Bool
    public var burnInCaptions: Bool
    public var exportSRT: Bool

    public init(preset: ExportPreset = .tiktok, outputDirectory: String = "", quality: ExportQuality = .high) {
        self.presetID = preset.id
        self.width = preset.width
        self.height = preset.height
        self.frameRate = preset.frameRate
        self.codec = preset.codec
        self.videoBitrate = preset.videoBitrate
        self.audioBitrate = preset.audioBitrate
        self.quality = quality
        self.filenameTemplate = "{clip}-{preset}"
        self.outputDirectory = outputDirectory
        self.useHardwareEncoding = true
        self.burnInCaptions = true
        self.exportSRT = false
    }

    public var effectiveVideoBitrate: Int {
        Int(Double(videoBitrate) * quality.bitrateFactor)
    }

    /// Output size preserving the timeline's aspect: the preset's long side is honoured and the
    /// short side follows the canvas so a 9:16 timeline never gets squashed into 16:9.
    public func outputSize(for canvas: CanvasSettings) -> (width: Int, height: Int) {
        let targetLong = max(width, height)
        let canvasLong = max(canvas.width, canvas.height)
        let k = Double(targetLong) / Double(max(canvasLong, 1))
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        return (even(Double(canvas.width) * k), even(Double(canvas.height) * k))
    }

    /// Validates settings, returning a user-facing problem description.
    public func validationError(for canvas: CanvasSettings) -> String? {
        if outputDirectory.isEmpty { return "Choose an export folder in Settings → Files or in the export panel." }
        if videoBitrate < 250_000 { return "The video bitrate is too low to produce watchable video (minimum 0.25 Mbps)." }
        if let fps = frameRate, fps < 1 || fps > 240 { return "Frame rate must be between 1 and 240 fps." }
        let size = outputSize(for: canvas)
        if size.width > 8192 || size.height > 8192 { return "Resolution above 8K isn't supported by the hardware encoder." }
        if filenameTemplate.trimmingCharacters(in: .whitespaces).isEmpty { return "The filename can't be empty." }
        return nil
    }

    /// Expands the filename template into a safe filename (with extension).
    public func filename(project: String, clip: String, index: Int, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var name = filenameTemplate
            .replacingOccurrences(of: "{project}", with: project)
            .replacingOccurrences(of: "{clip}", with: clip)
            .replacingOccurrences(of: "{preset}", with: ExportPreset.preset(id: presetID)?.name ?? presetID)
            .replacingOccurrences(of: "{date}", with: formatter.string(from: date))
            .replacingOccurrences(of: "{index}", with: String(format: "%02d", index))
        name = ExportSettings.sanitize(name)
        if name.isEmpty { name = "PULSE Export \(index)" }
        return name + "." + codec.fileExtension
    }

    public static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t").union(.controlCharacters)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
        // Strip emoji & collapse whitespace for maximum compatibility with upload sites.
        let ascii = cleaned.unicodeScalars.filter { !$0.properties.isEmojiPresentation && $0.value != 0xFE0F }
        let collapsed = String(String.UnicodeScalarView(ascii)).split(separator: " ").joined(separator: " ")
        return String(collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " .-“”\"")).prefix(120))
    }

    /// Returns a URL that doesn't overwrite an existing file ("Clip (2).mp4").
    public static func uniqueURL(directory: URL, filename: String, fileExists: (URL) -> Bool) -> URL {
        var url = directory.appendingPathComponent(filename)
        guard fileExists(url) else { return url }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 2
        repeat {
            url = directory.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        } while fileExists(url) && n < 10_000
        return url
    }
}

public enum ExportJobStatus: Codable, Hashable, Sendable {
    case queued
    case preparing
    case rendering(progress: Double)
    case completed(path: String)
    case failed(message: String)
    case cancelled

    public var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .rendering: return true
        default: return false
        }
    }

    public var progress: Double {
        switch self {
        case .queued: return 0
        case .preparing: return 0.01
        case .rendering(let p): return p
        case .completed: return 1
        case .failed, .cancelled: return 0
        }
    }

    public var label: String {
        switch self {
        case .queued: return "Queued"
        case .preparing: return "Preparing"
        case .rendering(let p): return "Rendering \(Int((p * 100).rounded()))%"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

public struct ExportJob: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var projectName: String
    public var timelineID: UUID
    public var timelineName: String
    public var settings: ExportSettings
    public var status: ExportJobStatus
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var outputPath: String?

    public init(id: UUID = UUID(), projectID: UUID, projectName: String, timelineID: UUID, timelineName: String, settings: ExportSettings) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.timelineID = timelineID
        self.timelineName = timelineName
        self.settings = settings
        self.status = .queued
        self.createdAt = Date()
    }

    /// Linear ETA from elapsed time and progress.
    public func estimatedRemaining(now: Date = Date()) -> TimeInterval? {
        guard case .rendering(let p) = status, let startedAt, p > 0.02 else { return nil }
        let elapsed = now.timeIntervalSince(startedAt)
        return elapsed / p * (1 - p)
    }
}

/// Summary of a batch for the queue header.
public struct ExportQueueSummary: Hashable, Sendable {
    public var total: Int
    public var completed: Int
    public var failed: Int
    public var active: Int
    public var queued: Int
    public var overallProgress: Double
    public var estimatedRemaining: TimeInterval?

    public init(jobs: [ExportJob], now: Date = Date()) {
        total = jobs.count
        completed = jobs.filter { if case .completed = $0.status { return true }; return false }.count
        failed = jobs.filter { if case .failed = $0.status { return true }; return false }.count
        active = jobs.filter { $0.status.isActive }.count
        queued = jobs.filter { $0.status == .queued }.count
        let considered = jobs.filter { $0.status != .cancelled }
        overallProgress = considered.isEmpty ? 0 : considered.map(\.status.progress).reduce(0, +) / Double(considered.count)
        // ETA: average finished-job duration × remaining + current job's own ETA.
        let durations = jobs.compactMap { job -> TimeInterval? in
            guard case .completed = job.status, let s = job.startedAt, let f = job.finishedAt else { return nil }
            return f.timeIntervalSince(s)
        }
        let current = jobs.compactMap { $0.estimatedRemaining(now: now) }.first
        if let avg = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count) {
            estimatedRemaining = (current ?? 0) + avg * Double(queued)
        } else {
            estimatedRemaining = current
        }
    }
}
