import Foundation

/// The timeline as Final Cut Pro XML (#480) for Final Cut Pro and DaVinci Resolve: every video and audio clip
/// with its source range, gaps where the timeline is empty, text as basic titles, markers. Speed changes,
/// transforms, grades and captions aren't carried over (the XML says so in a note) — the cut is.
public enum FCPXMLExporter {
    public static func xml(timeline: Timeline, assets: [MediaAsset], projectName: String, compounds: [UUID: Timeline] = [:]) -> String {
        let fps = timeline.canvas.frameRate
        let (num, den) = frameDuration(fps: fps)
        func t(_ seconds: Seconds) -> String {
            let frames = Int((seconds * Double(den) / Double(num)).rounded())
            return "\(frames * num)/\(den)s"
        }
        var resources: [String] = []
        resources.append("<format id=\"r1\" name=\"FFVideoFormat\(timeline.canvas.height)p\(fpsLabel(fps))\" frameDuration=\"\(num)/\(den)s\" width=\"\(timeline.canvas.width)\" height=\"\(timeline.canvas.height)\"/>")
        var assetIDs: [UUID: String] = [:]
        var next = 2
        for id in timeline.assetIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let asset = assets.first(where: { $0.id == id }) else { continue }
            let rid = "r\(next)"
            next += 1
            assetIDs[id] = rid
            let src = asset.url.absoluteString
            resources.append("<asset id=\"\(rid)\" name=\"\(escape(asset.name))\" start=\"0s\" duration=\"\(t(asset.metadata.duration))\" hasVideo=\"\(asset.metadata.hasVideo ? 1 : 0)\" hasAudio=\"\(asset.metadata.hasAudio ? 1 : 0)\" src=\"\(escape(src))\"/>")
        }
        let titleEffect = "r\(next)"
        resources.append("<effect id=\"\(titleEffect)\" name=\"Basic Title\" uid=\".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti\"/>")

        let videoTracks = timeline.tracks.filter { $0.kind == .video }
        let primary = videoTracks.first?.clips.sorted { $0.start < $1.start } ?? []
        // Secondary pieces: other video tracks, text, and audio clips that aren't the primary clips' own sound.
        let primaryGroups = Set(primary.compactMap(\.linkGroup))
        var connected: [(clip: TimelineClip, lane: Int)] = []
        for (i, track) in videoTracks.dropFirst().enumerated() { for c in track.clips { connected.append((c, i + 1)) } }
        for track in timeline.tracks where track.kind == .text { for c in track.clips { connected.append((c, videoTracks.count)) } }
        var audioLane = -1
        for track in timeline.tracks where track.kind == .audio {
            for c in track.clips where !(c.linkGroup.map(primaryGroups.contains) ?? false) { connected.append((c, audioLane)) }
            audioLane -= 1
        }

        var textStyles: [String] = []
        var styleCount = 0
        func element(for clip: TimelineClip, offset: Seconds, lane: Int?, children: [String] = []) -> String? {
            let laneAttr = lane.map { " lane=\"\($0)\"" } ?? ""
            let inner = children.isEmpty ? "" : "\n" + children.joined(separator: "\n") + "\n"
            switch clip.content {
            case .media(let assetID):
                guard let rid = assetIDs[assetID] else { return nil }
                let audioOnly = assets.first { $0.id == assetID }?.metadata.hasVideo == false
                let tag = audioOnly ? "asset-clip" : "asset-clip"
                var attrs = "ref=\"\(rid)\" offset=\"\(t(offset))\" name=\"\(escape(clip.name))\" start=\"\(t(clip.sourceIn))\" duration=\"\(t(clip.duration))\"\(laneAttr)"
                if !clip.isEnabled { attrs += " enabled=\"0\"" }
                if clip.audio.isMuted { attrs += " audioRole=\"dialogue\"" }
                return inner.isEmpty ? "<\(tag) \(attrs)/>" : "<\(tag) \(attrs)>\(inner)</\(tag)>"
            case .text(let element):
                styleCount += 1
                let ts = "ts\(styleCount)"
                textStyles.append(ts)
                let size = Int(element.style.fontSize.rounded())
                let body = "<text><text-style ref=\"\(ts)\">\(escape(element.text))</text-style></text>\n<text-style-def id=\"\(ts)\"><text-style font=\"\(escape(element.style.fontName))\" fontSize=\"\(size)\" bold=\"\(element.style.weight == .bold || element.style.weight == .black ? 1 : 0)\" alignment=\"center\"/></text-style-def>"
                return "<title ref=\"\(titleEffect)\" offset=\"\(t(offset))\" name=\"\(escape(clip.name))\" start=\"0s\" duration=\"\(t(clip.duration))\"\(laneAttr)>\n\(body)\(inner)</title>"
            case .compound(let id):
                let inside = compounds[id]
                return "<gap name=\"\(escape(clip.name)) (compound\(inside.map { ", \($0.allClips.count) clips" } ?? ""))\" offset=\"\(t(offset))\" start=\"0s\" duration=\"\(t(clip.duration))\"\(laneAttr)/>"
            default:
                return "<gap name=\"\(escape(clip.name))\" offset=\"\(t(offset))\" start=\"0s\" duration=\"\(t(clip.duration))\"\(laneAttr)/>"
            }
        }

        // Spine: the primary clips with gaps, each carrying the connected clips that start inside it.
        var spine: [String] = []
        var cursor: Seconds = 0
        var placedConnected = Set<UUID>()
        let duration = max(timeline.duration, primary.last?.end ?? 0)
        func attach(to clip: TimelineClip, parentOffset: Seconds) -> [String] {
            var out: [String] = []
            for (c, lane) in connected where !placedConnected.contains(c.id) && c.start >= clip.start - 1e-6 && c.start < clip.end - 1e-6 {
                // A connected clip's offset is in the parent's own timebase (its `start`).
                if let e = element(for: c, offset: clip.sourceIn + (c.start - parentOffset), lane: lane) {
                    out.append(e)
                    placedConnected.insert(c.id)
                }
            }
            return out
        }
        for clip in primary {
            if clip.start > cursor + 1e-6 {
                let gap = TimelineClip(name: "Gap", content: .solid(.black), start: cursor, sourceDuration: clip.start - cursor)
                spine.append("<gap name=\"Gap\" offset=\"\(t(cursor))\" start=\"0s\" duration=\"\(t(gap.duration))\">\n\(attach(to: gap, parentOffset: cursor).joined(separator: "\n"))\n</gap>")
            }
            if let e = element(for: clip, offset: clip.start, lane: nil, children: attach(to: clip, parentOffset: clip.start)) { spine.append(e) }
            cursor = max(cursor, clip.end)
        }
        if duration > cursor + 1e-6 || connected.contains(where: { !placedConnected.contains($0.clip.id) }) {
            let tail = max(duration, connected.map { $0.clip.end }.max() ?? 0) - cursor
            let gap = TimelineClip(name: "Gap", content: .solid(.black), start: cursor, sourceDuration: max(tail, 1 / fps))
            let rest = connected.filter { !placedConnected.contains($0.clip.id) }.compactMap { c, lane in element(for: c, offset: c.start - cursor, lane: lane) }
            spine.append("<gap name=\"Gap\" offset=\"\(t(cursor))\" start=\"0s\" duration=\"\(t(gap.duration))\">\n\(rest.joined(separator: "\n"))\n</gap>")
        }
        let markers = timeline.markers.sorted { $0.time < $1.time }.map {
            "<marker start=\"\(t($0.time))\" duration=\"\(num)/\(den)s\" value=\"\(escape($0.name))\"\($0.note.isEmpty ? "" : " note=\"\(escape($0.note))\"")/>"
        }
        let skipped = ["speed changes", "zoom and pan", "color grades", "captions", "effects"].joined(separator: ", ")
        let note = "<note>Exported by PULSE. The cut, titles and markers are here; \(skipped) stay in PULSE.</note>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
        <resources>
        \(resources.joined(separator: "\n"))
        </resources>
        <library>
        <event name="PULSE">
        <project name="\(escape(projectName))">
        <sequence format="r1" duration="\(t(max(duration, 1 / fps)))" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
        \(note)
        <spine>
        \(spine.joined(separator: "\n"))
        </spine>
        \(markers.joined(separator: "\n"))
        </sequence>
        </project>
        </event>
        </library>
        </fcpxml>
        """
    }

    /// Frame duration as a rational: 29.97 → 1001/30000, 25 → 1/25, 59.94 → 1001/60000.
    static func frameDuration(fps: Double) -> (Int, Int) {
        for (rate, pair) in [(23.976, (1001, 24000)), (29.97, (1001, 30000)), (59.94, (1001, 60000)), (119.88, (1001, 120000))] where abs(fps - rate) < 0.01 {
            return pair
        }
        if abs(fps - fps.rounded()) < 1e-6 { return (1, max(1, Int(fps.rounded()))) }
        return (100, max(1, Int((fps * 100).rounded())))
    }

    static func fpsLabel(_ fps: Double) -> String {
        abs(fps - fps.rounded()) < 1e-6 ? "\(Int(fps.rounded()))" : String(format: "%.2f", fps).replacingOccurrences(of: ".", with: "")
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
