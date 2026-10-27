import Foundation
import PulseCore

/// Speed Edit (#500): a whole VOD in minutes without touching the mouse. N / P jump between the recording's
/// moments (in → out set to each), J/K/L and I/O work as always, X makes a short of in → out, D dismisses the
/// moment, return exports in → out, escape leaves the mode.
extension ProjectSession {
    /// The recording's moments in time order, dismissed ones left out.
    var speedEditMoments: [ClipCandidate] {
        guard let asset = document.primaryAsset else { return [] }
        return document.candidates.filter { $0.assetID == asset.id && $0.status != .dismissed }.sorted { $0.range.start < $1.range.start }
    }

    var speedEditCurrent: ClipCandidate? {
        guard let index = speedEditIndex else { return nil }
        let moments = speedEditMoments
        return moments.indices.contains(index) ? moments[index] : nil
    }

    func toggleSpeedEdit() {
        speedEdit.toggle()
        if speedEdit {
            if speedEditMoments.isEmpty {
                app.toast("Speed Edit: analyze the recording first so there are moments to step through")
            } else {
                speedEditGo(to: speedEditIndex ?? nearestMomentIndex())
                app.toast("Speed Edit — N / P next and previous moment, X makes a short, D dismisses, ↩ exports in → out, ⎋ leaves")
            }
        } else {
            speedEditIndex = nil
        }
    }

    /// The moment at or after the playhead, so the pass starts where you are.
    private func nearestMomentIndex() -> Int {
        let moments = speedEditMoments
        let sourceTime = sourceTimeAtPlayhead() ?? 0
        return moments.firstIndex { $0.range.end >= sourceTime } ?? 0
    }

    func speedEditNext() { speedEditStep(1) }
    func speedEditPrevious() { speedEditStep(-1) }

    private func speedEditStep(_ delta: Int) {
        let moments = speedEditMoments
        guard !moments.isEmpty else { app.toast("No moments left — analyze the recording or undo a dismissal"); return }
        let current = speedEditIndex ?? nearestMomentIndex()
        speedEditGo(to: min(max(current + delta, 0), moments.count - 1))
    }

    /// Jumps the playhead to a moment, marks in → out around it, and plays it from the top.
    func speedEditGo(to index: Int) {
        let moments = speedEditMoments
        guard moments.indices.contains(index), let timeline = activeTimeline, let asset = document.primaryAsset else { return }
        let moment = moments[index]
        speedEditIndex = index
        // Where the moment sits on the timeline: the main recording's clip that covers it.
        guard let clip = timeline.tracks.filter({ $0.kind == .video }).flatMap(\.clips)
                .first(where: { $0.content.assetID == asset.id && $0.sourceRange.contains(max(moment.range.start, moment.payoffTime - 1)) }) else {
            app.toast("“\(moment.title)” isn't on this timeline — open the recording's own timeline for Speed Edit")
            return
        }
        let start = clip.start + max(0, moment.range.start - clip.sourceIn) / clip.speed
        let end = min(clip.end, clip.start + (moment.range.end - clip.sourceIn) / clip.speed)
        inPoint = start
        outPoint = end
        playback.seek(to: start)
        playback.play()
    }

    /// X: a short from in → out (the current moment, or whatever you marked).
    func speedEditMakeShort() {
        guard inPoint != nil, outPoint != nil else { app.toast("Mark in and out first (I / O), or press N for the next moment"); return }
        selectedClipIDs = []
        makeShortFromSelection()
        speedEditNext()
    }

    /// D: this moment is not worth a short; on to the next.
    func speedEditDismiss() {
        guard let current = speedEditCurrent else { return }
        let id = current.id
        edit("Dismiss Moment") { doc in
            if let i = doc.candidates.firstIndex(where: { $0.id == id }) { doc.candidates[i].status = .dismissed }
        }
        let moments = speedEditMoments
        if moments.isEmpty { speedEditIndex = nil; app.toast("That was the last moment") } else { speedEditGo(to: min(speedEditIndex ?? 0, moments.count - 1)) }
    }

    /// Source time of the recording under the playhead, if the playhead is over it.
    func sourceTimeAtPlayhead() -> Seconds? {
        guard let timeline = activeTimeline, let asset = document.primaryAsset else { return nil }
        let t = playhead
        guard let clip = timeline.tracks.filter({ $0.kind == .video }).flatMap(\.clips)
                .first(where: { $0.content.assetID == asset.id && $0.timelineRange.contains(t) }) else { return nil }
        return clip.sourceIn + (t - clip.start) * clip.speed
    }
}
