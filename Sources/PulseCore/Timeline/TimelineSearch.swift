import Foundation

/// One place a search landed on a timeline (#174).
public struct TimelineHit: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case clip, marker, words

        public var symbolName: String {
            switch self {
            case .clip: return "film"
            case .marker: return "bookmark"
            case .words: return "text.quote"
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var time: Seconds
    public var title: String
    public var detail: String

    public init(id: String, kind: Kind, time: Seconds, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.time = time
        self.title = title
        self.detail = detail
    }
}

extension Timeline {
    /// Clips by name, markers by name or note, and words spoken in the captions (#174), in time order.
    public func find(_ rawQuery: String, limit: Int = 60) -> [TimelineHit] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        var hits: [TimelineHit] = []
        for track in tracks {
            for clip in track.clips where clip.name.lowercased().contains(q) {
                hits.append(TimelineHit(id: "c-\(clip.id.uuidString)", kind: .clip, time: clip.start, title: clip.name,
                                        detail: "\(track.name) · \(Timecode.duration(clip.duration))"))
            }
        }
        for m in markers where m.name.lowercased().contains(q) || m.note.lowercased().contains(q) {
            hits.append(TimelineHit(id: "m-\(m.id.uuidString)", kind: .marker, time: m.time, title: m.name, detail: m.note))
        }
        if let captions, captions.isEnabled {
            let words = CaptionLayoutEngine.timelineWords(captions, in: self)
            let terms = q.split(separator: " ").map { TranscriptWord.normalize(String($0)) }.filter { !$0.isEmpty }
            var i = 0
            while !terms.isEmpty, i + terms.count <= words.count {
                let slice = words[i..<(i + terms.count)]
                guard zip(terms, slice).allSatisfy({ TranscriptWord.normalize($1.text).contains($0) }) else { i += 1; continue }
                let lo = max(0, i - 3), hi = min(words.count, i + terms.count + 3)
                let context = words[lo..<hi].map(\.text).joined(separator: " ")
                hits.append(TimelineHit(id: "w-\(words[i].id.uuidString)", kind: .words, time: words[i].start,
                                        title: slice.map(\.text).joined(separator: " "), detail: "…\(context)…"))
                i += terms.count
            }
        }
        return Array(hits.sorted { $0.time < $1.time }.prefix(limit))
    }
}
