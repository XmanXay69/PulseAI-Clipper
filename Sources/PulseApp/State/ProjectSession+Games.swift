import Foundation
import PulseCore

extension ProjectSession {
    /// The per-game profile the clip scorer uses for a recording (#34): the one pinned in Project Settings,
    /// otherwise the one detected from the project and file names and from what gets said.
    func gameProfile(for analysis: MediaAnalysis) -> GameProfile? {
        if let id = document.overrides.gameProfileID { return GameProfile.profile(id: id) }
        return detectedGameProfile(for: analysis)
    }

    /// What the names and the transcript say the game is, ignoring any pin.
    func detectedGameProfile(for analysis: MediaAnalysis?) -> GameProfile? {
        var names = [document.name]
        if let analysis, let asset = document.asset(id: analysis.assetID) {
            names.append(asset.name)
        } else if let primary = document.primaryAsset {
            names.append(primary.name)
        }
        let spoken = analysis?.transcript?.words.prefix(3000).map(\.normalized) ?? []
        return GameProfile.detect(in: names, spoken: Array(spoken))
    }

    /// The scorer's input for a recording, with its game profile attached.
    func clipInput(for analysis: MediaAnalysis) -> ClipGenerationInput {
        ClipGenerationInput(analysis: analysis, game: gameProfile(for: analysis))
    }
}
