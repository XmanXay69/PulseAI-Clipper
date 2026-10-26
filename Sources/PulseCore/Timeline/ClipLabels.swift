import Foundation

extension MarkerColor {
    public var displayName: String { rawValue.capitalized }
}

/// Colour labels on clips (#177): tag anything, then show only that colour or select it all at once.
extension Timeline {
    public func clips(label: MarkerColor) -> [TimelineClip] {
        allClips.filter { $0.labelColor == label }
    }

    /// The labels in use, in palette order.
    public var labelsInUse: [MarkerColor] {
        MarkerColor.allCases.filter { label in allClips.contains { $0.labelColor == label } }
    }

    /// Sets (or clears, nil) the label on these clips. Returns how many changed.
    @discardableResult
    public mutating func setLabel(_ label: MarkerColor?, clipIDs: Set<UUID>) -> Int {
        var count = 0
        for t in tracks.indices {
            for c in tracks[t].clips.indices where clipIDs.contains(tracks[t].clips[c].id) && tracks[t].clips[c].labelColor != label {
                tracks[t].clips[c].labelColor = label
                count += 1
            }
        }
        if count > 0 { touch() }
        return count
    }

    /// Where you asked the music to pull out for a beat (#288): markers you named "Drop" (or "Drop here",
    /// "drop the beat"), in order.
    public var musicDropTimes: [Seconds] {
        markers.filter { !$0.aiGenerated && $0.name.lowercased().hasPrefix("drop") }.map(\.time).sorted()
    }

    /// Cuts a minute on the main video track, ignoring cutaways (#102).
    public var cutsPerMinute: Double {
        guard duration > 1, let v = tracks.first(where: { $0.kind == .video }) else { return 0 }
        let cuts = max(0, v.clips.filter { $0.role != .graphic }.count - 1)
        return Double(cuts) / (duration / 60)
    }
}
