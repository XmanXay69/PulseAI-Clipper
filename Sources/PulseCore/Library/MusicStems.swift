import Foundation

/// Instrumental versions of music (#295): when the library holds "Song (Instrumental)" next to "Song",
/// the instrumental goes under the talking.
public enum MusicStems {
    static let markers = ["instrumental", "no vocals", "no vocal", "karaoke", "inst.", "(inst)", "- inst", "_inst", " inst version", "backing track"]

    /// "Song (Instrumental)" → true.
    public static func isInstrumental(_ name: String) -> Bool {
        let lower = name.lowercased()
        return markers.contains { lower.contains($0) } || lower.hasSuffix(" inst")
    }

    /// The title without the stem marker and any surrounding punctuation: "Song (Instrumental)" → "song".
    public static func baseTitle(_ name: String) -> String {
        var lower = name.lowercased()
        for marker in markers + [" inst"] {
            lower = lower.replacingOccurrences(of: marker, with: " ")
        }
        lower = lower.replacingOccurrences(of: "version", with: " ")
        let stripped = lower.map { ("()[]-_–—.".contains($0)) ? " " : $0 }
        return String(stripped).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The instrumental of `bed` in `library`, if there is one.
    public static func instrumental(for bed: MediaAsset, in library: [MediaAsset]) -> MediaAsset? {
        guard !isInstrumental(bed.name) else { return nil }
        let base = baseTitle(bed.name)
        guard !base.isEmpty else { return nil }
        return library.first { $0.id != bed.id && $0.kind == .audio && !$0.isTrashed && isInstrumental($0.name) && baseTitle($0.name) == base }
    }

    /// Every bed swapped for its instrumental where one exists; the rest stay as they are.
    public static func preferringInstrumentals(_ beds: [MediaAsset], library: [MediaAsset]) -> [MediaAsset] {
        beds.map { instrumental(for: $0, in: library) ?? $0 }
    }
}
