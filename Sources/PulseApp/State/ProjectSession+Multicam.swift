import Foundation
import PulseCore
import PulseEngine

/// Multicam editing, synchronized companions and imported recordings.
extension ProjectSession {
    // MARK: Companions (screen recording + separate webcam/mic of the same session)

    /// Other recordings of the same session as `asset`.
    func syncedPartners(of asset: MediaAsset) -> [MediaAsset] {
        guard let group = asset.syncGroupID else { return [] }
        return document.media.filter { $0.syncGroupID == group && $0.id != asset.id && $0.availability != .missing }
    }

    /// The separate facecam for a screen/gameplay recording.
    func webcamCompanion(for asset: MediaAsset) -> MediaAsset? {
        guard asset.role == .gameplay else { return nil }
        return syncedPartners(of: asset).first { $0.role == .webcam && $0.metadata.hasVideo }
    }

    /// The separate voice recording for a screen/gameplay recording (a mic file, else the webcam's mic).
    func voiceCompanion(for asset: MediaAsset) -> MediaAsset? {
        guard asset.role == .gameplay else { return nil }
        let partners = syncedPartners(of: asset).filter { $0.metadata.hasAudio }
        return partners.first { $0.role == .microphone } ?? partners.first { $0.role == .webcam || $0.role == .camera }
    }

    // MARK: Multicam

    var multicamGroups: [MulticamGroup] { MulticamGroup.groups(in: document.media) }

    /// The multicam group used by a timeline's video clips.
    func multicamGroup(for timeline: Timeline?) -> MulticamGroup? {
        guard let timeline else { return nil }
        let groups = multicamGroups
        for clip in timeline.allClips where clip.isVisual {
            if let id = clip.assetID, let group = groups.first(where: { $0.angle(id) != nil }) { return group }
        }
        return nil
    }

    var activeMulticamGroup: MulticamGroup? { multicamGroup(for: activeTimeline) }

    /// Builds a switched edit of a multicam session. `auto` follows whoever is talking.
    func createMulticamEdit(groupID: UUID, auto: Bool) {
        guard let group = multicamGroups.first(where: { $0.id == groupID }) else {
            app.presentMessage(title: "Not a multicam session", message: MulticamError.noVideoAngles.localizedDescription)
            return
        }
        let span = group.commonVideoRange ?? group.sessionRange
        let firstAngle = group.videoAngles.first!
        let canvas: CanvasSettings = firstAngle.size.height > firstAngle.size.width ? .vertical1080 : .landscape1080
        let name = auto ? "AI Multicam Edit" : "Multicam Edit"
        if !auto {
            let timeline = MulticamEditor.timeline(cuts: [MulticamCut(range: span, assetID: firstAngle.assetID)], group: group,
                                                   audioAssetID: nil, canvas: canvas, name: name)
            edit("Create Multicam Edit") { $0.timelines.append(timeline) }
            open(timelineID: timeline.id)
            leftTab = .angles
            app.toast("Press 1–\(min(9, group.videoAngles.count)) while playing to cut between angles")
            return
        }
        app.jobs.start("AI multicam · \(group.videoAngles.count) angles", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            let (levels, hop) = try await self.loudness(for: group.videoAngles.filter(\.hasAudio), job: job)
            job.detail = "Choosing shots"
            let cuts = MulticamEditor.autoSwitch(group: group, levels: levels, hop: hop, range: span, gridOnCrosstalk: true)
            let timeline = MulticamEditor.timeline(cuts: cuts, group: group, audioAssetID: nil, canvas: canvas, name: name)
            self.edit("AI Multicam Edit") { $0.timelines.append(timeline) }
            self.open(timelineID: timeline.id)
            self.leftTab = .angles
            self.app.logActivity(.autoEdit, title: "AI multicam edit", detail: "\(cuts.count) shots from \(group.videoAngles.count) angles")
            self.app.toast("\(cuts.count) shots — cut anywhere with 1–\(min(9, group.videoAngles.count))")
        }
    }

    /// Re-runs AI angle switching over the active multicam timeline's V1 clips.
    func autoSwitchActiveTimeline() {
        guard let timeline = activeTimeline, let group = multicamGroup(for: timeline),
              let ti = timeline.tracks.firstIndex(where: { t in t.kind == .video && t.clips.contains { c in c.assetID.map { group.angle($0) != nil } ?? false } }) else { return }
        let clips = timeline.tracks[ti].clips.sorted { $0.start < $1.start }
        guard let first = clips.first, let last = clips.last,
              let start = MulticamEditor.sessionTime(of: first, atTimeline: first.start, group: group),
              let end = MulticamEditor.sessionTime(of: last, atTimeline: last.end, group: group), end > start else { return }
        let timelineID = timeline.id
        app.jobs.start("AI angle switching", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            let (levels, hop) = try await self.loudness(for: group.videoAngles.filter(\.hasAudio), job: job)
            let cuts = MulticamEditor.autoSwitch(group: group, levels: levels, hop: hop, range: TimeRange(start: start, end: end), gridOnCrosstalk: true)
            let rebuilt = MulticamEditor.timeline(cuts: cuts, group: group, audioAssetID: nil, canvas: timeline.canvas, name: timeline.name)
            self.edit("AI Switch Angles") { doc in
                doc.updateTimeline(id: timelineID) { t in
                    guard ti < t.tracks.count else { return }
                    let offset = first.start
                    let span = TimeRange(start: first.start, end: last.end)
                    func shifted(_ clips: [TimelineClip]) -> [TimelineClip] {
                        clips.map { var c = $0; c.start += offset; c.aiGenerated = true; return c }
                    }
                    t.tracks[ti].clips = shifted(rebuilt.tracks[0].clips)
                    // Old grid cells in this span go; the new grid shots come from the rebuilt edit.
                    for gi in t.tracks.indices where t.tracks[gi].name.hasPrefix("Grid ") {
                        t.tracks[gi].clips.removeAll { $0.timelineRange.overlaps(span) }
                    }
                    for gridTrack in rebuilt.tracks where gridTrack.name.hasPrefix("Grid ") && !gridTrack.clips.isEmpty {
                        if let gi = t.tracks.firstIndex(where: { $0.kind == .video && $0.name == gridTrack.name }) {
                            t.tracks[gi].clips = (t.tracks[gi].clips + shifted(gridTrack.clips)).sorted { $0.start < $1.start }
                        } else {
                            var track = Track(kind: .video, name: gridTrack.name)
                            track.clips = shifted(gridTrack.clips)
                            t.tracks.insert(track, at: min(t.tracks.count, ti + 1))
                        }
                    }
                }
            }
            self.app.toast("\(cuts.count) shots chosen by who's talking")
        }
    }

    /// Cuts the active multicam timeline to angle `index` (0-based) at the playhead.
    func cutToAngle(_ index: Int) {
        guard let group = activeMulticamGroup, index < group.videoAngles.count else { return }
        let angle = group.videoAngles[index]
        let time = playhead
        editTimeline("Cut to \(angle.name)", coalesce: nil) { t in
            let id = try MulticamEditor.cut(&t, at: time, to: angle.assetID, group: group)
            selectedClipIDs = [id]
        }
    }

    /// The multicam shot under the playhead on the active timeline.
    var multicamShotAtPlayhead: TimelineClip? {
        guard let group = activeMulticamGroup, let timeline = activeTimeline else { return nil }
        let time = playhead
        for track in timeline.tracks where track.kind == .video {
            if let clip = track.clips.first(where: { c in c.timelineRange.contains(time) && (c.assetID.map { group.angle($0) != nil } ?? false) }) {
                return clip
            }
        }
        return nil
    }

    /// Applies a grid layout to the shot under the playhead, or to every shot between In and Out.
    /// `angles` are in slot order; empty = the shot's angle followed by the others.
    func applyMulticamGrid(_ layout: MulticamGridLayout, angles: [UUID]) {
        guard let group = activeMulticamGroup else { return }
        let range: TimeRange? = {
            guard let a = inPoint, let b = outPoint, b - a > 0.1 else { return nil }
            return TimeRange(start: a, end: b)
        }()
        let shotID = multicamShotAtPlayhead?.id
        var focus: [UUID: Vec2] = [:]
        for angle in group.videoAngles {
            if let face = analyses[angle.assetID]?.webcam?.face.center { focus[angle.assetID] = face }
        }
        editTimeline(layout == .single ? "Remove Grid" : "Grid: \(layout.displayName)") { t in
            let ids: [UUID]
            if let range {
                ids = MulticamEditor.shots(&t, in: range, group: group)
            } else if let shotID {
                ids = [shotID]
            } else {
                ids = []
            }
            guard !ids.isEmpty else { throw MulticamError.notMulticam }
            for id in ids {
                guard let current = t.clip(id: id)?.assetID else { continue }
                let order = angles.isEmpty ? [current] + group.videoAngles.map(\.assetID).filter { $0 != current } : angles
                try MulticamEditor.applyGrid(&t, clipID: id, angles: order, layout: layout, group: group, focus: focus)
            }
        }
    }

    /// Switches the angle of a whole clip (Inspector).
    func switchAngle(clipID: UUID, to assetID: UUID) {
        guard let group = activeMulticamGroup else { return }
        editTimeline("Switch Angle") { t in try MulticamEditor.switchAngle(&t, clipID: clipID, to: assetID, group: group) }
    }

    /// Per-angle loudness (dB per hop), from existing analyses or a quick audio pass.
    private func loudness(for angles: [MulticamAngle], job: BackgroundJob) async throws -> ([UUID: [Float]], Seconds) {
        var levels: [UUID: [Float]] = [:]
        var hop = AudioAnalyzer.hop
        for (i, angle) in angles.enumerated() {
            job.detail = "Listening to \(angle.name)"
            if let features = analyses[angle.assetID]?.audio {
                levels[angle.assetID] = features.rmsDB.values
                hop = features.hop
            } else if let asset = document.asset(id: angle.assetID) {
                let result = try await AudioAnalyzer().analyze(url: url(for: asset), isCancelled: job.isCancelledCheck)
                levels[angle.assetID] = result.features.rmsDB.values
                hop = result.features.hop
            }
            job.progress = Double(i + 1) / Double(max(angles.count, 1)) * 0.9
        }
        return (levels, hop)
    }

    // MARK: Recordings

    /// Imports the files of a PULSE recording as one synchronized session and analyzes it.
    func importRecording(_ result: RecordingResult, analyzeAfter: Bool) {
        let cacheRoot = app.cacheFolder
        app.jobs.start("Importing recording", kind: .importMedia) { [weak self] job in
            guard let self else { return }
            let group = UUID()
            var assets: [MediaAsset] = []
            for file in result.files {
                job.detail = file.url.lastPathComponent
                let kind: MediaKind = file.role == .microphone ? .audio : .video
                var asset = try await MediaImporter.makeAsset(for: ImportPlan.Item(url: file.url, kind: kind, role: file.role), cacheRoot: cacheRoot)
                asset.syncGroupID = group
                asset.syncOffset = file.syncOffset
                asset.tags.append("recording")
                assets.append(asset)
            }
            let screen = assets.first { $0.role == .gameplay }
            self.edit("Import Recording") { doc in
                doc.media.append(contentsOf: assets)
                if let screen { doc.primaryAssetID = screen.id } else if doc.primaryAssetID == nil { doc.primaryAssetID = assets.first?.id }
            }
            self.save()
            self.app.logActivity(.importMedia, title: "Recorded \(Timecode.duration(result.duration))", detail: assets.map(\.name).joined(separator: " · "))
            if !result.warnings.isEmpty {
                self.app.presentMessage(title: "Recording finished with notes", message: result.warnings.joined(separator: "\n\n"))
            }
            if analyzeAfter, let main = screen ?? assets.first {
                self.analyze(assetID: main.id, generateClips: true)
            } else {
                self.app.section = .importMedia
            }
        }
    }
}
