import Foundation

/// OBS-style multi-track recordings (#11): one file, several audio tracks. The usual layout is the full
/// mix first, then the microphone, the game, music, and voice chat; each becomes its own lane.
public enum OBSTracks {
    public struct Lane: Hashable, Sendable {
        public var index: Int
        public var name: String
        public var role: MediaRole
        /// The full mix doubles everything else, so it starts muted when the parts are there too.
        public var startsMuted: Bool
    }

    /// Lanes for a recording with `count` audio tracks; a single track is just "Audio".
    public static func lanes(count: Int) -> [Lane] {
        guard count >= 2 else { return [Lane(index: 0, name: "Audio", role: .microphone, startsMuted: false)] }
        let names: [(String, MediaRole)] = [("Mix", .main), ("Mic", .microphone), ("Game", .gameplay), ("Music", .music), ("Chat", .microphone), ("Alerts", .soundEffect)]
        return (0..<count).map { i in
            let (name, role) = i < names.count ? names[i] : ("Track \(i + 1)", MediaRole.microphone)
            return Lane(index: i, name: name, role: role, startsMuted: i == 0)
        }
    }

    /// The lane names as the track headers show them.
    public static func trackName(for lane: Lane, of assetName: String) -> String { "\(lane.name) · \(assetName)" }
}
