import Foundation

/// The first clips from a long recording before the rest of it is analyzed (#1061). The first ten minutes
/// are cut out, analyzed on their own (sound, words and the facecam; no banners, reactions or speakers) and the best three
/// moments are shown as real clips with titles and captions, usually inside two minutes, while the full
/// analysis carries on behind them. The sample project proves the app; this proves it on your own stream.
public enum HeadStart {
    /// How much of the start is analyzed first, in seconds.
    public static let length: Seconds = 600
    /// How many clips are shown.
    public static let clipCount = 3

    /// Worth doing for a recording long enough that the full analysis is a wait: twenty minutes or more.
    public static func isWorthIt(duration: Seconds) -> Bool { duration >= 1200 }

    /// The best `count` moments of the head, as clips of the main recording. `analysis` is the head's own
    /// analysis: it starts at the same instant as the recording, so its times are the recording's times. The
    /// clips are marked preliminary: the full pass replaces any you haven't opened or favorited.
    public static func clips(from analysis: MediaAnalysis, assetID: UUID, settings: ClipGenerationSettings, taste: TasteProfile = TasteProfile(),
                             count: Int = HeadStart.clipCount) -> [ClipCandidate] {
        let found = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: settings).generate()
            .applyingTaste(taste).sorted { $0.potential > $1.potential }
        var picked: [ClipCandidate] = []
        for candidate in found where picked.count < count {
            // Nothing that runs off the end of the head, and no two clips of the same moment.
            guard candidate.range.end <= analysis.duration + 0.5, !picked.contains(where: { $0.range.iou(candidate.range) > 0.3 }) else { continue }
            var clip = candidate
            clip.assetID = assetID
            clip.preliminary = true
            picked.append(clip)
        }
        return picked
    }

    /// The clips already there that a head-start clip would duplicate: first-look clips found from the sound
    /// alone, which the head-start clips (found with the words as well) replace.
    public static func superseded(by fresh: [ClipCandidate], among existing: [ClipCandidate]) -> Set<UUID> {
        Set(existing.filter { old in
            old.preliminary == true && old.status == .new && !old.isFavorite && fresh.contains { $0.assetID == old.assetID && $0.range.iou(old.range) > 0.3 }
        }.map(\.id))
    }
}
