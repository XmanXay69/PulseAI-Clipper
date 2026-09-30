import Foundation

/// What "Make More Entertaining" is allowed to do. Each toggle maps to a separately undoable,
/// AI-labelled change on the existing timeline.
public struct EntertainmentOptions: Codable, Hashable, Sendable {
    public var jumpCuts: Bool = true
    public var silencePreset: SilencePreset = .aggressive
    public var removeFillers: Bool = true
    public var punchIns: Bool = true
    public var captionEmphasis: Bool = true
    public var reactionZooms: Bool = true
    public var soundEffects: Bool = false
    public var music: Bool = false
    public var transitions: Bool = false

    public init() {}
}

/// Summary of what an AI pass changed (shown in the AI activity feed and undo label).
public struct AIEditReport: Hashable, Sendable {
    public var removedSeconds: Seconds = 0
    public var silenceCuts: Int = 0
    public var fillerCuts: Int = 0
    public var punchIns: Int = 0
    public var emphasizedWords: Int = 0
    public var soundEffects: Int = 0
    public var transitions: Int = 0
    public var musicAdded: Bool = false

    public var summary: String {
        var parts: [String] = []
        if silenceCuts > 0 { parts.append("\(silenceCuts) jump cuts") }
        if fillerCuts > 0 { parts.append("\(fillerCuts) filler words removed") }
        if punchIns > 0 { parts.append("\(punchIns) punch-ins") }
        if emphasizedWords > 0 { parts.append("\(emphasizedWords) emphasised words") }
        if soundEffects > 0 { parts.append("\(soundEffects) sound effects") }
        if transitions > 0 { parts.append("\(transitions) transitions") }
        if musicAdded { parts.append("music bed") }
        if removedSeconds > 0.05 { parts.append(String(format: "%.1fs tighter", removedSeconds)) }
        return parts.isEmpty ? "No changes needed — the clip is already tight." : parts.joined(separator: " · ")
    }
}

public enum EntertainmentEditor {
    /// Applies an entertainment pass to an existing timeline in place.
    public static func apply(to timeline: inout Timeline, analysis: MediaAnalysis?, options: EntertainmentOptions,
                             soundEffects: [MediaAsset] = [], music: MediaAsset? = nil) -> AIEditReport {
        var report = AIEditReport()
        guard let assetID = timeline.origin?.assetID ?? timeline.allClips.compactMap(\.assetID).first else { return report }
        let visibleSource = timeline.allClips.filter { $0.assetID == assetID }.map(\.sourceRange).merged()

        if options.jumpCuts {
            var cuts: [TimeRange] = []
            for range in visibleSource {
                cuts += SilenceDetector.detect(audio: analysis?.audio, transcript: analysis?.transcript, in: range, preset: options.silencePreset)
            }
            if !cuts.isEmpty {
                report.removedSeconds += timeline.removeSourceRanges(cuts, assetID: assetID, reason: .silence, aiGenerated: true)
                report.silenceCuts = cuts.count
            }
        }
        if options.removeFillers, let transcript = analysis?.transcript {
            var detections: [FillerDetection] = []
            for range in timeline.allClips.filter({ $0.assetID == assetID }).map(\.sourceRange).merged() {
                detections += FillerWordDetector.detect(in: transcript, range: range, minimumConfidence: 0.75).filter { $0.kind != .filler }
            }
            if !detections.isEmpty {
                let ranges = FillerWordDetector.cutRanges(for: detections, in: transcript)
                report.removedSeconds += timeline.removeSourceRanges(ranges, assetID: assetID, reason: .fillerWord, texts: detections.map(\.text), aiGenerated: true)
                report.fillerCuts = detections.count
            }
        }
        if options.captionEmphasis, var captions = timeline.captions {
            captions.applyAIEmphasis()
            report.emphasizedWords = captions.words.filter { $0.isEmphasized && $0.emphasisIsAI }.count
            timeline.captions = captions
        }
        if options.punchIns || options.reactionZooms {
            var moments: [PunchInGenerator.Moment] = []
            if options.punchIns, let captions = timeline.captions {
                for w in CaptionLayoutEngine.timelineWords(captions, in: timeline) where w.isEmphasized {
                    moments.append(.punchline(w.start))
                }
            }
            if options.reactionZooms {
                for m in timeline.markers where m.name == "Payoff" { moments.append(.reaction(m.time)) }
                if let analysis, let audio = analysis.audio {
                    // Loud spikes inside the edit become reaction zooms.
                    for clip in timeline.allClips where clip.assetID == assetID && clip.role != .webcam && clip.role != .microphone {
                        var t = clip.sourceIn
                        while t < clip.sourceOut {
                            let window = TimeRange(start: t, end: min(t + 1, clip.sourceOut))
                            if audio.maxRMS(in: window) > -10 { moments.append(.reaction(clip.timelineTime(atSource: window.start))) }
                            t += 1
                        }
                    }
                }
            }
            let faceTrack = timeline.tracks.first { t in t.kind == .video && t.clips.contains { $0.role == .webcam && $0.isEnabled } }
            if let target = faceTrack?.id ?? timeline.videoTracks.first?.id, !moments.isEmpty {
                var settings = PunchInSettings()
                settings.minimumSpacing = 2.5
                PunchInGenerator.apply(moments: moments, to: &timeline, trackID: target, settings: settings)
                report.punchIns = timeline.tracks.first { $0.id == target }?.clips.map { $0.transform.zoom.keyframes.filter(\.aiGenerated).count / 3 }.reduce(0, +) ?? 0
            }
        }
        if options.soundEffects, let sfx = ShortBuilder.pickSoundEffect(soundEffects, preferring: ["whoosh", "swoosh", "pop"]) {
            let sfxTrackID = timeline.freeTrack(kind: .audio, for: TimeRange(start: 0, duration: 0.01))
            // A whoosh at up to 4 jump cuts, spaced out.
            let cutPoints = timeline.tracks.first { $0.kind == .video }?.clips.dropFirst().map(\.start) ?? []
            var last = -10.0
            for t in cutPoints where t - last > 4 && report.soundEffects < 4 {
                let clip = TimelineClip(name: sfx.name, content: .media(assetID: sfx.id), start: max(0, t - 0.15),
                                        sourceDuration: min(max(sfx.metadata.duration, 0.3), 1.2), role: .soundEffect, aiGenerated: true)
                if (try? timeline.insert(clip, onTrack: sfxTrackID, mode: .overwrite)) != nil {
                    report.soundEffects += 1
                    last = t
                }
            }
        }
        if options.music, let music, !timeline.allClips.contains(where: { $0.role == .music }) {
            let trackID = timeline.freeTrack(kind: .audio, for: TimeRange(start: 0, end: timeline.duration))
            var clip = TimelineClip(name: music.name, content: .media(assetID: music.id), start: 0,
                                    sourceDuration: music.metadata.duration > 0 ? min(music.metadata.duration, timeline.duration) : timeline.duration,
                                    role: .music, aiGenerated: true)
            clip.audio.volume = AnimatedDouble(0.3)
            clip.audio.duckUnderDialogue = true
            clip.audio.fadeIn = 0.5
            clip.audio.fadeOut = 1.2
            if (try? timeline.insert(clip, onTrack: trackID)) != nil { report.musicAdded = true }
        }
        if options.transitions {
            // Only soften the first and last cut; never spam transitions.
            if let ti = timeline.tracks.firstIndex(where: { $0.kind == .video }), !timeline.tracks[ti].clips.isEmpty {
                timeline.tracks[ti].clips[0].transitionIn = ClipTransition(kind: .fadeToBlack, duration: 0.25, aiGenerated: true)
                let lastIndex = timeline.tracks[ti].clips.count - 1
                timeline.tracks[ti].clips[lastIndex].transitionOut = ClipTransition(kind: .fadeToBlack, duration: 0.35, aiGenerated: true)
                report.transitions = 2
            }
        }
        timeline.modifiedAt = Date()
        return report
    }

    /// Removes every AI-generated change from a timeline (the "Disable AI" escape hatch).
    public static func stripAIEdits(from timeline: inout Timeline) {
        for ti in timeline.tracks.indices {
            timeline.tracks[ti].clips.removeAll { $0.aiGenerated && ($0.role == .soundEffect || $0.role == .music) }
            for ci in timeline.tracks[ti].clips.indices {
                timeline.tracks[ti].clips[ci].transform.removeAIKeyframes()
                if timeline.tracks[ti].clips[ci].transitionIn?.aiGenerated == true { timeline.tracks[ti].clips[ci].transitionIn = nil }
                if timeline.tracks[ti].clips[ci].transitionOut?.aiGenerated == true { timeline.tracks[ti].clips[ci].transitionOut = nil }
                timeline.tracks[ti].clips[ci].effects.removeAll { $0.aiGenerated }
            }
        }
        timeline.captions?.resetAIEmphasis()
        timeline.markers.removeAll { $0.aiGenerated }
        // Restore AI-removed sections, newest first.
        for section in timeline.removedSections.reversed() where section.aiGenerated {
            try? timeline.restore(removedSectionID: section.id)
        }
        timeline.modifiedAt = Date()
    }
}
