import Foundation

/// A named copy of a timeline you can go back to (#185): "before the AI pass", "v2 with the cold open"…
/// Edit My VOD and Make More Entertaining take one automatically before they change a timeline (#118).
public struct TimelineSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var timelineID: UUID
    public var name: String
    public var createdAt: Date
    public var timeline: Timeline
    /// True when PULSE took it before an automatic pass (older automatic ones are dropped first).
    public var automatic: Bool

    public init(id: UUID = UUID(), timeline: Timeline, name: String, createdAt: Date = Date(), automatic: Bool = false) {
        self.id = id
        self.timelineID = timeline.id
        self.name = name
        self.createdAt = createdAt
        self.timeline = timeline
        self.automatic = automatic
    }

    public var summary: String {
        "\(Timecode.short(timeline.duration)) · \(timeline.allClips.count) clips"
    }
}

extension ProjectDocument {
    /// How many snapshots a timeline keeps; beyond it the oldest automatic ones go first, then the oldest named.
    public static let snapshotsPerTimeline = 20

    public func snapshots(for timelineID: UUID) -> [TimelineSnapshot] {
        snapshots.filter { $0.timelineID == timelineID }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Saves a copy of the timeline as it is now. Returns the snapshot, or nil when there is no such timeline.
    @discardableResult
    public mutating func snapshot(timelineID: UUID, name: String, automatic: Bool = false, at date: Date = Date()) -> TimelineSnapshot? {
        guard let timeline = timeline(id: timelineID) else { return nil }
        let snapshot = TimelineSnapshot(timeline: timeline, name: name, createdAt: date, automatic: automatic)
        snapshots.append(snapshot)
        var mine = snapshots.filter { $0.timelineID == timelineID }
        while mine.count > ProjectDocument.snapshotsPerTimeline {
            let victim = mine.sorted { a, b in a.automatic != b.automatic ? a.automatic : a.createdAt < b.createdAt }.first!
            snapshots.removeAll { $0.id == victim.id }
            mine.removeAll { $0.id == victim.id }
        }
        return snapshot
    }

    /// Puts the snapshot's copy back in place of the live timeline (same id, so the editor stays on it). The
    /// live version is kept as an automatic snapshot first, so a restore is itself undoable from the list.
    @discardableResult
    public mutating func restore(snapshotID: UUID, at date: Date = Date()) -> Bool {
        guard let snapshot = snapshots.first(where: { $0.id == snapshotID }) else { return false }
        if timeline(id: snapshot.timelineID) != nil {
            self.snapshot(timelineID: snapshot.timelineID, name: "Before restoring “\(snapshot.name)”", automatic: true, at: date)
        }
        var restored = snapshot.timeline
        restored.id = snapshot.timelineID
        restored.modifiedAt = date
        if let i = timelines.firstIndex(where: { $0.id == snapshot.timelineID }) {
            timelines[i] = restored
        } else if let i = compounds.firstIndex(where: { $0.id == snapshot.timelineID }) {
            compounds[i] = restored
        } else {
            timelines.append(restored)
        }
        return true
    }

    public mutating func deleteSnapshot(id: UUID) {
        snapshots.removeAll { $0.id == id }
    }
}
