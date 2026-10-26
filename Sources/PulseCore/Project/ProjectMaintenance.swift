import Foundation

/// Bringing older projects forward (#385). Every model decodes missing fields to defaults; this pass fixes
/// what defaults can't: dangling references and unsorted clips. Returns what it touched.
public enum ProjectMigration {
    @discardableResult
    public static func migrate(_ doc: inout ProjectDocument) -> [String] {
        var notes: [String] = []
        if doc.schemaVersion < ProjectDocument.schemaVersion {
            notes.append("Project format \(doc.schemaVersion) → \(ProjectDocument.schemaVersion)")
            doc.schemaVersion = ProjectDocument.schemaVersion
        }
        if let active = doc.activeTimelineID, doc.timeline(id: active) == nil {
            doc.activeTimelineID = doc.timelines.first?.id
            notes.append("Active timeline reset")
        }
        if let primary = doc.primaryAssetID, doc.asset(id: primary) == nil {
            doc.primaryAssetID = doc.media.first?.id
            notes.append("Main recording reset")
        }
        for ti in doc.timelines.indices {
            for tr in doc.timelines[ti].tracks.indices {
                let before = doc.timelines[ti].tracks[tr].clips.map(\.id)
                doc.timelines[ti].tracks[tr].sortClips()
                if doc.timelines[ti].tracks[tr].clips.map(\.id) != before {
                    notes.append("Clips reordered on \(doc.timelines[ti].tracks[tr].name) in \(doc.timelines[ti].name)")
                }
            }
        }
        let known = Set(doc.timelines.map(\.id))
        var unlinked = 0
        for i in doc.candidates.indices where doc.candidates[i].timelineID.map({ !known.contains($0) }) ?? false {
            doc.candidates[i].timelineID = nil
            unlinked += 1
        }
        if unlinked > 0 { notes.append("\(unlinked) clip card\(unlinked == 1 ? "" : "s") unlinked from deleted timelines") }
        let timelineIDs = known.union(doc.compounds.map(\.id))
        let orphanSnapshots = doc.snapshots.filter { !timelineIDs.contains($0.timelineID) }.count
        if orphanSnapshots > 0 {
            doc.snapshots.removeAll { !timelineIDs.contains($0.timelineID) }
            notes.append("\(orphanSnapshots) snapshot\(orphanSnapshots == 1 ? "" : "s") of deleted timelines removed")
        }
        return notes
    }
}

extension ProjectDocument {
    /// Media any timeline, compound, clip card or sync group still needs (#469).
    public var usedAssetIDs: Set<UUID> {
        var used = Set<UUID>()
        for t in timelines + compounds { used.formUnion(t.assetIDs) }
        for c in candidates where c.status != .dismissed { used.insert(c.assetID) }
        if let p = primaryAssetID { used.insert(p) }
        let groups = Set(media.filter { used.contains($0.id) }.compactMap(\.syncGroupID))
        for m in media where m.syncGroupID.map(groups.contains) ?? false { used.insert(m.id) }
        return used
    }

    public var unusedMedia: [MediaAsset] {
        let used = usedAssetIDs
        return media.filter { !used.contains($0.id) }
    }

    /// Trims the project to the media it uses (#469). The files stay on disk. Returns what was removed.
    @discardableResult
    public mutating func removeUnusedMedia() -> [MediaAsset] {
        let gone = unusedMedia
        guard !gone.isEmpty else { return [] }
        let ids = Set(gone.map(\.id))
        media.removeAll { ids.contains($0.id) }
        touch()
        return gone
    }

    /// The asset already holding this content, if any (#5).
    public func asset(contentHash: String) -> MediaAsset? {
        media.first { $0.contentHash == contentHash }
    }
}

extension ProjectDocument {
    /// Media in the panel (not trashed).
    public var visibleMedia: [MediaAsset] { media.filter { !$0.isTrashed } }
    public var trashedMedia: [MediaAsset] { media.filter(\.isTrashed) }

    /// Out of the panel, clips untouched (#22).
    @discardableResult
    public mutating func trashMedia(id: UUID) -> Bool {
        guard let i = media.firstIndex(where: { $0.id == id }), !media[i].isTrashed else { return false }
        media[i].isTrashed = true
        if primaryAssetID == id { primaryAssetID = visibleMedia.first { $0.kind == .video }?.id ?? visibleMedia.first?.id }
        touch()
        return true
    }

    @discardableResult
    public mutating func restoreMedia(id: UUID) -> Bool {
        guard let i = media.firstIndex(where: { $0.id == id }), media[i].isTrashed else { return false }
        media[i].isTrashed = false
        if primaryAssetID == nil { primaryAssetID = id }
        touch()
        return true
    }

    /// Deletes trashed media nothing uses; what a timeline still needs stays in the trash. Returns what went.
    @discardableResult
    public mutating func emptyMediaTrash() -> [MediaAsset] {
        let used = usedAssetIDs
        let gone = media.filter { $0.isTrashed && !used.contains($0.id) }
        guard !gone.isEmpty else { return [] }
        let ids = Set(gone.map(\.id))
        media.removeAll { ids.contains($0.id) }
        touch()
        return gone
    }
}
