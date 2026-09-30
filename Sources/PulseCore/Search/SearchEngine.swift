import Foundation

public enum SearchResultKind: String, Sendable, CaseIterable {
    case project, clip, media, transcript, caption, marker, timeline

    public var displayName: String {
        switch self {
        case .project: return "Projects"
        case .clip: return "AI Clips"
        case .media: return "Media"
        case .transcript: return "Transcript"
        case .caption: return "Captions"
        case .marker: return "Markers"
        case .timeline: return "Timelines"
        }
    }

    public var symbolName: String {
        switch self {
        case .project: return "folder"
        case .clip: return "sparkles"
        case .media: return "film"
        case .transcript: return "text.quote"
        case .caption: return "captions.bubble"
        case .marker: return "bookmark"
        case .timeline: return "timeline.selection"
        }
    }
}

public struct SearchResult: Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: SearchResultKind
    public var title: String
    public var subtitle: String
    /// Source time (transcript/clip) or timeline time (marker/caption).
    public var time: Seconds?
    public var projectID: UUID?
    public var assetID: UUID?
    public var timelineID: UUID?
    public var candidateID: UUID?
    public var score: Double

    public init(id: String, kind: SearchResultKind, title: String, subtitle: String, time: Seconds? = nil, projectID: UUID? = nil,
                assetID: UUID? = nil, timelineID: UUID? = nil, candidateID: UUID? = nil, score: Double) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.time = time
        self.projectID = projectID
        self.assetID = assetID
        self.timelineID = timelineID
        self.candidateID = candidateID
        self.score = score
    }
}

/// Global search across projects, clips, media, transcripts, captions, markers and timelines.
/// Understands a few "vibe" queries: "funny", "hype", "fail" expand into lexicon terms and tags.
public enum SearchEngine {
    static let expansions: [String: [String]] = [
        "funny": ["haha", "lol", "lmao", "laugh", "hilarious", "funny", "crying", "dead"],
        "hype": ["let's go", "lets go", "insane", "clutch", "yes", "no way", "sheesh"],
        "fail": ["oh no", "died", "dead", "noo", "rip", "worst"],
        "rage": ["what the", "wtf", "are you kidding", "rigged"],
        "story": ["one time", "story", "remember when", "so basically"],
    ]

    static let tagForQuery: [String: ClipTag] = [
        "funny": .funny, "hype": .hype, "fail": .fail, "rage": .rage, "story": .story, "reaction": .reaction,
        "gaming": .gaming, "energy": .highEnergy, "question": .question,
    ]

    public static func search(_ rawQuery: String, projects: [ProjectSummary], document: ProjectDocument?, analyses: [UUID: MediaAnalysis], limit: Int = 80) -> [SearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        var results: [SearchResult] = []

        // Timestamps like "42:17" jump straight to that time in the primary asset.
        if let t = Timecode.parse(query), query.contains(":"), let doc = document, let asset = doc.primaryAsset {
            results.append(SearchResult(id: "time-\(t)", kind: .transcript, title: "Jump to \(Timecode.short(t))", subtitle: asset.name,
                                        time: t, projectID: doc.id, assetID: asset.id, score: 10))
        }

        for p in projects where p.name.lowercased().contains(query) {
            results.append(SearchResult(id: "project-\(p.id)", kind: .project, title: p.name, subtitle: "\(p.clipCount) clips · \(Timecode.duration(p.duration))",
                                        projectID: p.id, score: 5 + (p.name.lowercased().hasPrefix(query) ? 1 : 0)))
        }

        guard let doc = document else { return Array(results.prefix(limit)) }

        let terms = [query] + (expansions[query] ?? [])
        let tag = tagForQuery[query]
        for c in doc.visibleCandidates {
            var score = 0.0
            if c.title.lowercased().contains(query) { score += 4 }
            if c.copy.titles.contains(where: { $0.lowercased().contains(query) }) { score += 2 }
            if terms.contains(where: { c.transcriptSnippet.lowercased().contains($0) }) { score += 2 }
            if let tag, c.tags.contains(tag) { score += 3 }
            if c.tags.contains(where: { $0.displayName.lowercased() == query }) { score += 3 }
            guard score > 0 else { continue }
            results.append(SearchResult(id: "clip-\(c.id)", kind: .clip, title: c.title,
                                        subtitle: "\(Timecode.short(c.range.start)) → \(Timecode.short(c.range.end)) · AI Potential \(c.potential)",
                                        time: c.range.start, projectID: doc.id, assetID: c.assetID, candidateID: c.id, score: score + Double(c.potential) / 100))
        }

        for m in doc.media {
            let hay = ([m.name, m.role.displayName, m.category.displayName] + m.tags).joined(separator: " ").lowercased()
            if hay.contains(query) {
                results.append(SearchResult(id: "media-\(m.id)", kind: .media, title: m.name,
                                            subtitle: "\(m.kind.displayName) · \(Timecode.duration(m.metadata.duration)) · \(m.metadata.resolutionLabel)",
                                            projectID: doc.id, assetID: m.id, score: 3))
            }
        }

        for t in doc.timelines {
            if t.name.lowercased().contains(query) {
                results.append(SearchResult(id: "timeline-\(t.id)", kind: .timeline, title: t.name, subtitle: "\(t.canvas.aspectLabel) · \(Timecode.duration(t.duration))",
                                            projectID: doc.id, timelineID: t.id, score: 3))
            }
            for marker in t.markers where marker.name.lowercased().contains(query) || marker.note.lowercased().contains(query) {
                results.append(SearchResult(id: "marker-\(marker.id)", kind: .marker, title: marker.name, subtitle: "\(t.name) · \(Timecode.short(marker.time))",
                                            time: marker.time, projectID: doc.id, timelineID: t.id, score: 2))
            }
            if let captions = t.captions {
                let text = captions.words.map(\.text).joined(separator: " ").lowercased()
                if terms.contains(where: { text.contains($0) }) {
                    results.append(SearchResult(id: "caption-\(t.id)", kind: .caption, title: "Captions in \(t.name)", subtitle: String(captions.text.prefix(80)),
                                                projectID: doc.id, timelineID: t.id, score: 1.5))
                }
            }
        }

        for (assetID, analysis) in analyses {
            guard let transcript = analysis.transcript else { continue }
            var hits: [TranscriptHit] = []
            for term in terms { hits += transcript.search(term) }
            // Merge hits closer than 5 s so "funny" doesn't list every "haha" separately.
            var merged: [TranscriptHit] = []
            for hit in hits.sorted(by: { $0.time < $1.time }) {
                if let last = merged.last, hit.time - last.time < 5 { continue }
                merged.append(hit)
            }
            for hit in merged.prefix(40) {
                results.append(SearchResult(id: "tx-\(assetID)-\(hit.wordIndex)", kind: .transcript, title: "“\(hit.context)”",
                                            subtitle: "\(doc.asset(id: assetID)?.name ?? "Transcript") · \(Timecode.short(hit.time))",
                                            time: hit.time, projectID: doc.id, assetID: assetID, score: 1))
            }
        }

        return Array(results.sorted { $0.score != $1.score ? $0.score > $1.score : ($0.time ?? 0) < ($1.time ?? 0) }.prefix(limit))
    }
}
