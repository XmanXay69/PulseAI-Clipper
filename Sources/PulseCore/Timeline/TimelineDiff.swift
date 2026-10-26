import Foundation

/// What changed between two versions of a timeline (a snapshot and the live edit), in plain lines (#472).
public enum TimelineDiff {
    public static func summarize(before: Timeline, after: Timeline) -> [String] {
        var lines: [String] = []
        if abs(before.duration - after.duration) > 0.05 {
            let delta = after.duration - before.duration
            lines.append("Length \(Timecode.short(before.duration)) → \(Timecode.short(after.duration)) (\(delta > 0 ? "+" : "−")\(String(format: "%.1f", abs(delta))) s)")
        }
        let beforeClips = Dictionary(before.allClips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let afterClips = Dictionary(after.allClips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let added = afterClips.values.filter { beforeClips[$0.id] == nil }
        let removed = beforeClips.values.filter { afterClips[$0.id] == nil }
        if !added.isEmpty { lines.append("\(added.count) clip\(added.count == 1 ? "" : "s") added: " + names(added)) }
        if !removed.isEmpty { lines.append("\(removed.count) clip\(removed.count == 1 ? "" : "s") removed: " + names(removed)) }
        var moved = 0, trimmed = 0, restyled = 0, retimed = 0
        for (id, a) in afterClips {
            guard let b = beforeClips[id] else { continue }
            if abs(a.start - b.start) > 0.001 { moved += 1 }
            if abs(a.sourceIn - b.sourceIn) > 0.001 || abs(a.sourceDuration - b.sourceDuration) > 0.001 { trimmed += 1 }
            if abs(a.speed - b.speed) > 0.001 { retimed += 1 }
            if a.transform != b.transform || a.style != b.style || a.color != b.color || a.audio != b.audio || a.effects != b.effects { restyled += 1 }
        }
        if moved > 0 { lines.append("\(moved) clip\(moved == 1 ? "" : "s") moved") }
        if trimmed > 0 { lines.append("\(trimmed) clip\(trimmed == 1 ? "" : "s") trimmed") }
        if retimed > 0 { lines.append("\(retimed) clip\(retimed == 1 ? "" : "s") at a different speed") }
        if restyled > 0 { lines.append("\(restyled) clip\(restyled == 1 ? "" : "s") with a different look or sound") }
        switch (before.captions, after.captions) {
        case (nil, .some): lines.append("Captions added")
        case (.some, nil): lines.append("Captions removed")
        case let (.some(x), .some(y)):
            if x.style != y.style { lines.append("Caption style changed (\(x.style.presetName) → \(y.style.presetName))") }
            if x.words.count != y.words.count { lines.append("Caption words \(x.words.count) → \(y.words.count)") }
            else if x.words != y.words { lines.append("Caption words edited") }
        default: break
        }
        if before.markers.count != after.markers.count { lines.append("Markers \(before.markers.count) → \(after.markers.count)") }
        if before.removedSections.count != after.removedSections.count {
            lines.append("Removed sections \(before.removedSections.count) → \(after.removedSections.count)")
        }
        if before.layout != after.layout { lines.append("Layout \(before.layout?.displayName ?? "none") → \(after.layout?.displayName ?? "none")") }
        if before.tracks.count != after.tracks.count { lines.append("Tracks \(before.tracks.count) → \(after.tracks.count)") }
        return lines.isEmpty ? ["No differences"] : lines
    }

    static func names(_ clips: [TimelineClip]) -> String {
        let shown = clips.sorted { $0.start < $1.start }.prefix(4).map(\.name)
        return shown.joined(separator: ", ") + (clips.count > 4 ? ", …" : "")
    }
}
