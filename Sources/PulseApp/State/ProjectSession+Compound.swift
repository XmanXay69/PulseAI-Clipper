import Foundation
import PulseCore
import PulseEngine

/// Compound clips: collapse, open (edit inside), go back, break apart.
extension ProjectSession {
    var isInsideCompound: Bool { !compoundPath.isEmpty }

    /// Collapses the selected clips into one compound clip (⌥G).
    func createCompoundClip() {
        guard let parent = activeTimeline, !selectedClipIDs.isEmpty else {
            app.presentMessage(title: "Nothing selected", message: CompoundError.nothingSelected.localizedDescription)
            return
        }
        let ids = Array(selectedClipIDs)
        let parentID = parent.id
        let name = "Compound \(document.compounds.count + 1)"
        var newClipID: UUID?
        edit("New Compound Clip") { doc in
            var nested: Timeline?
            try doc.editTimeline(id: parentID) { t in
                let result = try CompoundEditor.makeCompound(in: &t, clipIDs: ids, name: name)
                nested = result.nested
                newClipID = result.clipID
            }
            if let nested { doc.compounds.append(nested) }
        }
        if let newClipID { selectedClipIDs = [newClipID] }
        app.toast("Compound clip created — double-click it to edit inside")
    }

    /// Opens a compound clip's nested timeline in the editor (double-click).
    func openCompound(clipID: UUID) {
        guard let parent = activeTimeline, let clip = parent.clip(id: clipID), let nestedID = clip.content.compoundID,
              document.timeline(id: nestedID) != nil else { return }
        compoundPath.append(parent.id)
        selectedTimelineID = nestedID
        selectedClipIDs = []
        reloadPlayback(debounce: 0)
        playback.seek(to: max(0, playback.currentTime - clip.start + clip.sourceIn))
    }

    /// Back to the timeline that contains the open compound clip.
    func exitCompound(toLevel level: Int? = nil) {
        guard !compoundPath.isEmpty else { return }
        let index = level ?? compoundPath.count - 1
        let target = compoundPath[index]
        compoundPath.removeSubrange(index...)
        selectedTimelineID = target
        selectedClipIDs = []
        reloadPlayback(debounce: 0)
    }

    /// Replaces a compound clip with its contents (⇧⌘G).
    func breakApartCompound(clipID: UUID? = nil) {
        guard let timeline = activeTimeline,
              let id = clipID ?? selectedClips.first(where: { $0.content.compoundID != nil })?.id,
              let nestedID = timeline.clip(id: id)?.content.compoundID,
              let nested = document.timeline(id: nestedID) else { return }
        let timelineID = timeline.id
        edit("Break Apart Compound Clip") { doc in
            try doc.editTimeline(id: timelineID) { t in
                try CompoundEditor.breakApart(&t, clipID: id, nested: nested)
            }
            // Drop nested timelines nothing refers to any more.
            let all = doc.compoundsByID
            var used = Set<UUID>(compoundPath)
            for t in doc.timelines { used.formUnion(CompoundEditor.referencedCompounds(of: t, in: all)) }
            doc.compounds.removeAll { !used.contains($0.id) }
        }
        selectedClipIDs = []
    }

    /// Names shown in the viewer's breadcrumb (outermost first, then the open timeline).
    var compoundBreadcrumb: [(id: UUID, name: String)] {
        (compoundPath + [selectedTimelineID].compactMap { $0 }).compactMap { id in document.timeline(id: id).map { (id, $0.name) } }
    }
}
