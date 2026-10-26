import Foundation

/// Where the facecam is empty (#47): the streamer went full-screen, the cam dropped, or they stepped away. A
/// punch-in there would zoom into nothing, so Edit My VOD skips those stretches.
public enum FacecamPresence {
    /// Stretches of at least `minimum` seconds with no face inside the facecam region, in source time.
    public static func absentRanges(faces: [FaceSample], region: NormRect, duration: Seconds, minimum: Seconds = 5) -> [TimeRange] {
        guard region.width > 0.02, region.height > 0.02, !faces.isEmpty else { return [] }
        let samples = faces.sorted { $0.time < $1.time }
        var ranges: [TimeRange] = []
        var absentSince: Seconds?
        func overlaps(_ box: NormRect) -> Bool {
            box.x < region.x + region.width && box.x + box.width > region.x && box.y < region.y + region.height && box.y + box.height > region.y
        }
        for sample in samples {
            let present = sample.boxes.contains(where: overlaps)
            if present {
                if let since = absentSince, sample.time - since >= minimum { ranges.append(TimeRange(start: since, end: sample.time)) }
                absentSince = nil
            } else if absentSince == nil {
                absentSince = sample.time
            }
        }
        if let since = absentSince, duration - since >= minimum { ranges.append(TimeRange(start: since, end: duration)) }
        return ranges
    }
}
