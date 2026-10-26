import Foundation

/// What each destination does with an upload, from the platforms' own upload guides: length limits, the
/// bitrate band that survives their re-encode, and a line of advice.
extension ExportPreset {
    /// The longest a video can be on this platform (nil = no practical limit).
    public var maximumDuration: Seconds? {
        switch id {
        case "tiktok": return 600
        case "shorts": return 180
        case "reels": return 180
        case "twitter": return 140
        default: return nil
        }
    }

    /// Where the length limit comes from, for the note.
    var platformName: String {
        switch id {
        case "tiktok": return "TikTok"
        case "shorts": return "YouTube Shorts"
        case "reels": return "Instagram Reels"
        case "youtube", "youtube4k": return "YouTube"
        case "twitter": return "X"
        default: return name
        }
    }

    /// The video bitrate band (bits per second) the platform recommends at a frame rate; below it the
    /// re-encode goes soft, far above it the file only gets bigger.
    public func recommendedBitrate(frameRate: Double) -> ClosedRange<Int>? {
        let high = frameRate > 40
        switch id {
        case "tiktok": return high ? 10_000_000...20_000_000 : 8_000_000...16_000_000
        case "shorts": return high ? 12_000_000...24_000_000 : 8_000_000...16_000_000
        case "reels": return high ? 8_000_000...16_000_000 : 6_000_000...12_000_000
        case "youtube": return high ? 12_000_000...24_000_000 : 8_000_000...16_000_000
        case "youtube4k": return high ? 53_000_000...80_000_000 : 35_000_000...68_000_000
        case "twitter": return 5_000_000...12_000_000
        default: return nil
        }
    }

    /// One or two sentences about what happens to the upload.
    public var platformGuidance: String? {
        switch id {
        case "tiktok":
            return "TikTok re-encodes every upload. 1080 × 1920 H.264 at 12–16 Mbps keeps the most detail through that; up to 10 minutes."
        case "shorts":
            return "YouTube re-encodes Shorts to VP9 at a lower bitrate — upload above 12 Mbps so detail survives. Under 3 minutes to count as a Short."
        case "reels":
            return "Instagram compresses hard; 1080 × 1920 at 10 Mbps is the sweet spot. Up to 3 minutes; 30 fps avoids a second re-encode on some devices."
        case "youtube":
            return "YouTube recommends 8 Mbps at 30 fps and 12 Mbps at 60 fps for 1080p, re-encoding to VP9. 16 Mbps leaves headroom; 1440p or 4K uploads get the better codec sooner."
        case "youtube4k":
            return "YouTube recommends 35–45 Mbps at 30 fps and 53–68 Mbps at 60 fps for 4K. HEVC halves the file at the same quality."
        case "twitter":
            return "X takes up to 1920 × 1200 and 512 MB; 2:20 without Premium. 10 Mbps H.264 is plenty — it re-encodes anyway."
        case "master":
            return "ProRes 422 is for archiving and re-editing (about 120 Mbps at 1080p). Don't upload it; export a platform preset from it."
        default:
            return nil
        }
    }
}

extension ExportSettings {
    /// m:ss (or h:mm:ss) for the length notes.
    static func clock(_ seconds: Seconds) -> String {
        let t = Int(seconds.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Notes for this export against the destination's specs: over its length limit, under its recommended
    /// bitrate for the frame rate, or wastefully above it. Empty means nothing to say.
    public func platformNotes(timelineDuration: Seconds, timelineFrameRate: Double) -> [String] {
        guard let preset = ExportPreset.preset(id: presetID) else { return [] }
        var notes: [String] = []
        if let limit = preset.maximumDuration, timelineDuration > limit + 0.5 {
            notes.append("\(preset.platformName) takes videos up to \(Self.clock(limit)); this one is \(Self.clock(timelineDuration)). Trim it, or it will be cut off or rejected.")
        }
        let fps = frameRate ?? timelineFrameRate
        if let band = preset.recommendedBitrate(frameRate: fps) {
            let bitrate = effectiveVideoBitrate
            let mbps = { (b: Int) in String(format: "%.0f", Double(b) / 1_000_000) }
            if bitrate < band.lowerBound {
                notes.append("\(mbps(bitrate)) Mbps is under \(preset.platformName)'s recommended \(mbps(band.lowerBound))–\(mbps(band.upperBound)) Mbps at \(Int(fps.rounded())) fps; detail goes soft after their re-encode. Raise Quality.")
            } else if bitrate > band.upperBound * 3 / 2 {
                notes.append("\(mbps(bitrate)) Mbps is well above the \(mbps(band.upperBound)) Mbps \(preset.platformName) keeps; the file is bigger for nothing.")
            }
        }
        return notes
    }
}
