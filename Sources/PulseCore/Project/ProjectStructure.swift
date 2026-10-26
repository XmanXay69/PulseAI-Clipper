import Foundation

extension ProjectDocument {
    /// The shape of the project with nothing personal in it (#455): counts, kinds, durations and settings —
    /// no names, paths, words or titles. Goes into a problem report when you tick the box.
    public func anonymizedStructure() -> String {
        var lines: [String] = []
        lines.append("project: format \(schemaVersion), \(media.count) media, \(timelines.count) timelines, \(compounds.count) compounds, \(candidates.count) clip cards (\(visibleCandidates.count) visible), \(snapshots.count) snapshots, \(exportCount) exports, status \(status.rawValue)")
        for (i, m) in media.enumerated() {
            let md = m.metadata
            lines.append("media \(i): \(m.kind.rawValue)/\(m.role.rawValue) \(md.width)x\(md.height) @\(String(format: "%.2f", md.frameRate)) fps, \(Timecode.duration(md.duration)), \(md.videoCodec ?? "-")/\(md.audioCodec ?? "-"), \(md.audioChannels) ch, \(m.availability == .online ? "online" : "offline"), analysis \(m.preparation.analysisState.rawValue)\(m.preparation.proxyPath == nil ? "" : ", proxy")\(m.syncGroupID == nil ? "" : ", synced")")
        }
        for (i, t) in timelines.enumerated() {
            var kinds: [String] = []
            for track in t.tracks {
                let ai = track.clips.filter(\.aiGenerated).count
                kinds.append("\(track.kind.rawValue) \(track.clips.count)\(ai > 0 ? " (\(ai) ai)" : "")")
            }
            let captions = t.captions.map { "\($0.words.count) caption words" } ?? "no captions"
            lines.append("timeline \(i): \(t.canvas.width)x\(t.canvas.height) @\(String(format: "%.2f", t.canvas.frameRate)), \(Timecode.duration(t.duration)), tracks [\(kinds.joined(separator: ", "))], \(captions), \(t.markers.count) markers, \(t.removedSections.count) removed sections, layout \(t.layout?.rawValue ?? "none")\(t.origin == nil ? "" : ", from AI")")
        }
        if !candidates.isEmpty {
            var bands: [String: Int] = [:]
            for c in candidates { bands[c.potentialBand.rawValue, default: 0] += 1 }
            let rated = candidates.filter { $0.feedback != nil }.count
            lines.append("clip cards: " + bands.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + ", \(rated) rated, lengths \(Int(candidates.map(\.duration).min() ?? 0))–\(Int(candidates.map(\.duration).max() ?? 0)) s")
        }
        lines.append("export: \(exportSettings.presetID), \(exportSettings.codec.rawValue), \(exportSettings.quality.rawValue)\(exportSettings.burnInCaptions ? ", burn-in captions" : "")\(exportSettings.audioOnly ? ", audio only" : "")")
        return lines.joined(separator: "\n")
    }
}
