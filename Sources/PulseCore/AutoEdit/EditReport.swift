import Foundation

/// What the edit did, as a page you can read (#107): what was cut and why, what was added, where the chapters
/// are — every line with a time to jump to.
public struct EditReport: Hashable, Sendable {
    public struct Line: Hashable, Identifiable, Sendable {
        public var id: Int
        /// Timeline time to jump to, when the line points somewhere.
        public var time: Seconds?
        public var text: String
    }

    public struct Section: Hashable, Identifiable, Sendable {
        public var id: String { title }
        public var title: String
        public var lines: [Line]
    }

    public var sections: [Section]

    public static func build(timeline: Timeline, assets: [MediaAsset] = []) -> EditReport {
        var sections: [Section] = []
        var next = 0
        func line(_ text: String, at time: Seconds? = nil) -> Line {
            next += 1
            return Line(id: next, time: time, text: text)
        }
        let clips = timeline.allClips
        let ai = clips.filter(\.aiGenerated)
        var overview = [line("\(Timecode.duration(timeline.duration)) long · \(clips.count) clips on \(timeline.tracks.count) tracks")]
        if !ai.isEmpty { overview.append(line("\(ai.count) clips placed by PULSE, every one editable")) }
        if let captions = timeline.captions { overview.append(line("\(captions.words.count) caption words\(captions.isEnabled ? "" : " (hidden)")")) }
        if let target = timeline.targetDuration { overview.append(line("Built for \(Timecode.duration(target))")) }
        sections.append(Section(title: "Overview", lines: overview))

        let chapters = timeline.markers.filter { $0.color == .blue && !$0.aiGenerated || $0.color == .blue }.sorted { $0.time < $1.time }
        if !chapters.isEmpty {
            sections.append(Section(title: "Chapters", lines: chapters.map { line("\(Timecode.short($0.time))  \($0.name)", at: $0.time) }))
        }

        if !timeline.removedSections.isEmpty {
            var lines: [Line] = []
            var byReason: [RemovedSection.Reason: (count: Int, seconds: Seconds)] = [:]
            for r in timeline.removedSections {
                byReason[r.reason, default: (0, 0)].count += 1
                byReason[r.reason, default: (0, 0)].seconds += r.sourceRange.duration
            }
            for (reason, total) in byReason.sorted(by: { $0.value.seconds > $1.value.seconds }) {
                lines.append(line("\(reason.displayName): \(total.count) cut\(total.count == 1 ? "" : "s"), \(Timecode.duration(total.seconds))"))
            }
            let shown = timeline.removedSections.sorted { $0.sourceRange.duration > $1.sourceRange.duration }.prefix(40)
            for r in shown {
                // The place in the edit where the cut happened: the clip that starts right after it.
                let at = timeline.timelineRanges(forSource: TimeRange(start: r.sourceRange.end, duration: 0.05), assetID: r.assetID).first?.start
                let what = r.text.map { " — “\(String($0.prefix(60)))\($0.count > 60 ? "…" : "")”" } ?? ""
                lines.append(line("\(Timecode.duration(r.sourceRange.duration)) of \(reason(r.reason)) at source \(Timecode.short(r.sourceRange.start))\(what)", at: at))
            }
            sections.append(Section(title: "What was cut", lines: lines))
        }

        var extras: [Line] = []
        func count(_ name: String, label: String) {
            let found = clips.filter { $0.name == name }
            if !found.isEmpty { extras.append(line("\(found.count) \(label)\(found.count == 1 ? "" : "s")", at: found.map(\.start).min())) }
        }
        let zooms = clips.reduce(0) { $0 + $1.transform.zoom.keyframes.filter(\.aiGenerated).count / 3 }
        if zooms > 0 { extras.append(line("\(zooms) zoom\(zooms == 1 ? "" : "s")")) }
        count("Meme", label: "meme pop-up")
        count("Replay", label: "instant replay")
        count("Title Card", label: "title card")
        count("Chapter Title", label: "chapter lower-third")
        count("Hook Title", label: "hook title")
        count("Cold Open", label: "cold open")
        count("Ramp", label: "speed ramp")
        count("End Card", label: "end card")
        count("End Screen", label: "end screen")
        let sfx = clips.filter { $0.role == .soundEffect }
        if !sfx.isEmpty { extras.append(line("\(sfx.count) sound effect\(sfx.count == 1 ? "" : "s")", at: sfx.map(\.start).min())) }
        let music = clips.filter { $0.role == .music }
        if !music.isEmpty { extras.append(line("\(music.count) music piece\(music.count == 1 ? "" : "s") (\(Timecode.duration(music.reduce(0) { $0 + $1.duration })))", at: music.map(\.start).min())) }
        let brollIDs = Set(assets.filter { $0.tags.contains("b-roll") }.map(\.id))
        let broll = clips.filter { clip in clip.role == .graphic && (clip.content.assetID.map(brollIDs.contains) ?? false) }
        if !broll.isEmpty { extras.append(line("\(broll.count) B-roll cutaway\(broll.count == 1 ? "" : "s")", at: broll.map(\.start).min())) }
        let transitions = clips.filter { $0.transitionIn != nil || $0.transitionOut != nil }.count
        if transitions > 0 { extras.append(line("\(transitions) clip\(transitions == 1 ? "" : "s") with transitions")) }
        if !extras.isEmpty { sections.append(Section(title: "Added", lines: extras)) }

        let todos = timeline.markers.filter { $0.name.lowercased().contains("todo") || $0.note.lowercased().contains("todo") }
        if !todos.isEmpty { sections.append(Section(title: "To do", lines: todos.map { line("\(Timecode.short($0.time))  \($0.name)", at: $0.time) })) }
        return EditReport(sections: sections)
    }

    static func reason(_ r: RemovedSection.Reason) -> String {
        switch r {
        case .silence: return "silence"
        case .fillerWord: return "filler"
        case .transcriptEdit: return "struck text"
        case .manual: return "manual cut"
        case .crosstalk: return "crosstalk"
        case .idleScreen: return "idle screen"
        case .noTalking: return "game with nobody talking"
        }
    }

    public var text: String {
        sections.map { s in "## \(s.title)\n" + s.lines.map { "- " + $0.text }.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}
