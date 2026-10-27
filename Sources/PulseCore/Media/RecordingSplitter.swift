import Foundation

/// Long recordings split into parts under a size limit (#322), so one file never outgrows a disk, a cloud
/// folder or a sync tool; the parts come back together on a timeline with seamless joins.
public enum RecordingSplitter {
    /// The stretches of a recording so each part stays under `maxBytes`: equal lengths on whole seconds, none
    /// shorter than `minimumPart` unless the whole file is. One stretch (the whole file) when it already fits.
    public static func plan(fileSize: Int64, duration: Seconds, maxBytes: Int64, minimumPart: Seconds = 60) -> [TimeRange] {
        guard duration > 0 else { return [] }
        let whole = [TimeRange(start: 0, end: duration)]
        guard maxBytes > 0, fileSize > maxBytes else { return whole }
        // A little margin: container overhead and keyframe alignment make parts slightly uneven.
        var parts = Int((Double(fileSize) / Double(maxBytes) * 1.03).rounded(.up))
        if duration / Double(parts) < minimumPart { parts = max(1, Int(duration / minimumPart)) }
        guard parts > 1 else { return whole }
        let length = duration / Double(parts)
        var ranges: [TimeRange] = []
        for i in 0..<parts {
            let start = i == 0 ? 0 : (Double(i) * length).rounded()
            let end = i == parts - 1 ? duration : (Double(i + 1) * length).rounded()
            if end > start { ranges.append(TimeRange(start: start, end: end)) }
        }
        return ranges
    }

    /// Bytes for a limit in gigabytes (0 or less = no limit).
    public static func bytes(gigabytes: Double) -> Int64 { gigabytes > 0 ? Int64(gigabytes * 1_000_000_000) : 0 }

    /// "ranked night part 2 of 5.mov"
    public static func partName(base: String, index: Int, count: Int, extension ext: String) -> String {
        "\(base) part \(index + 1) of \(count).\(ext)"
    }
}

extension ProjectDocument {
    /// The parts of a split recording in order, starting with any part of it (#322).
    public func sequenceParts(of asset: MediaAsset) -> [MediaAsset] {
        guard let group = asset.sequenceGroupID else { return [asset] }
        return media.filter { $0.sequenceGroupID == group && !$0.isTrashed }.sorted { ($0.sequenceIndex ?? 0) < ($1.sequenceIndex ?? 0) }
    }
}

/// Puts the parts of a split recording back to back on one timeline (#322): video and audio of each part
/// linked, a marker at every join, no gaps.
public enum SequenceJoiner {
    public static func timeline(parts: [MediaAsset], name: String? = nil) -> Timeline? {
        guard let first = parts.first else { return nil }
        let size = first.metadata.size.isEmpty ? Size2(1920, 1080) : first.metadata.size
        var canvas = size.aspect >= 1 ? CanvasSettings.landscape1080 : CanvasSettings(width: 1080, height: 1920, frameRate: 30)
        let fps = first.metadata.frameRate > 1 ? min(first.metadata.frameRate.rounded(), 60) : 30
        canvas.frameRate = fps
        let base = first.name.replacingOccurrences(of: #" part \d+ of \d+$"#, with: "", options: .regularExpression)
        var timeline = Timeline(name: name ?? "\(base) — joined", canvas: canvas, tracks: [
            Track(kind: .video, name: "V1 Recording"),
            Track(kind: .audio, name: "A1 Recording"),
        ])
        var cursor: Seconds = 0
        for (i, part) in parts.enumerated() {
            let duration = part.metadata.duration
            guard duration > 0 else { continue }
            let group = UUID()
            let role: MediaRole = part.role == .camera || part.role == .webcam ? part.role : (part.role == .gameplay ? .gameplay : .main)
            if part.metadata.hasVideo || part.kind == .video {
                timeline.tracks[0].clips.append(TimelineClip(name: part.name, content: .media(assetID: part.id), start: cursor, sourceIn: 0,
                                                             sourceDuration: duration, linkGroup: group, role: role))
            }
            if part.metadata.hasAudio || part.metadata.audioTrackCount > 0 {
                timeline.tracks[1].clips.append(TimelineClip(name: part.name, content: .media(assetID: part.id), start: cursor, sourceIn: 0,
                                                             sourceDuration: duration, linkGroup: group, role: .microphone))
            }
            if i > 0 { timeline.markers.append(Marker(time: cursor, name: "Part \(i + 1)", note: "Join between recording parts")) }
            cursor += duration
        }
        return timeline.allClips.isEmpty ? nil : timeline
    }
}
