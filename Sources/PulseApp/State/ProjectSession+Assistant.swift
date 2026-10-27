import Foundation
import PulseCore
import PulseEngine

/// The editor assistant (#498): plain English in, an ordinary undoable edit out. Rules only — nothing
/// leaves the Mac and nothing needs a model.
extension ProjectSession {
    /// Runs one request and says what happened.
    @discardableResult
    func runAssistant(_ text: String) -> String {
        guard let timeline = activeTimeline else { return "Open a timeline first." }
        let intent = EditorAssistant.parse(text)
        switch intent {
        case .undo:
            undo(); return "Undone."
        case .redo:
            redo(); return "Redone."
        case .tightenPauses(let minimum):
            guard pauseWords(for: timeline) != nil else { return "Transcribe the recording first — pauses come from the words." }
            let before = timeline.duration
            tightenPauses(minimum: minimum)
            return report("Pauses tightened", before: before)
        case .trimStart(let seconds):
            let cut = min(seconds, max(0, timeline.duration - 1))
            guard cut > 0 else { return "Nothing to cut." }
            editTimeline("Cut the Start") { $0.rippleDelete(range: TimeRange(start: 0, end: cut)) }
            playback.seek(to: 0)
            return "Cut the first \(EditorAssistant.seconds(cut)) — everything slid left."
        case .trimEnd(let seconds):
            let cut = min(seconds, max(0, timeline.duration - 1))
            guard cut > 0 else { return "Nothing to cut." }
            editTimeline("Cut the End") { $0.rippleDelete(range: TimeRange(start: $0.duration - cut, end: $0.duration)) }
            return "Cut the last \(EditorAssistant.seconds(cut))."
        case .shorter(let fraction):
            let before = timeline.duration
            let target = before * (1 - fraction)
            if pauseWords(for: timeline) != nil { tightenPauses(minimum: 0.2) }
            if let now = activeTimeline?.duration, now > target + 1 {
                // Still long: the tail gives up the rest, up to 15 % of the edit.
                let cut = min(now - target, now * 0.15)
                editTimeline("Trim the Tail") { $0.rippleDelete(range: TimeRange(start: $0.duration - cut, end: $0.duration)) }
            }
            return report("Shortened", before: before)
        case .punchierHook:
            guard let assetID = timeline.origin?.assetID ?? timeline.videoTracks.first?.clips.first?.assetID else { return "No recording on this timeline." }
            guard let signals = energySignal(for: assetID), signals.step > 0, !signals.excitement.isEmpty else {
                return "Analyze the recording first — the hook comes from its most exciting moment."
            }
            // The most exciting source moment that the edit actually uses.
            let used = timeline.videoTracks.flatMap(\.clips).filter { $0.assetID == assetID && $0.role != .graphic }.map(\.sourceRange)
            var best: (time: Seconds, score: Float)?
            for (i, e) in signals.excitement.enumerated() {
                let t = Double(i) * signals.step
                guard used.contains(where: { $0.contains(t) }) else { continue }
                if best == nil || e > best!.score { best = (t, e) }
            }
            guard let payoff = best?.time else { return "Couldn't find a moment to open on." }
            var applied = false
            editTimeline("Punchier Hook") { applied = EditPolish.coldOpen(&$0, assetID: assetID, payoffAtSource: payoff) }
            playback.seek(to: 0)
            return applied ? "Opens on the moment at \(Timecode.short(payoff)) now, then the story." : "That moment is too close to the start to open on."
        case .captions(let on):
            if on {
                if timeline.captions == nil { CaptionsWorkspace.generateCaptions(session: self); return activeTimeline?.captions == nil ? "No transcript yet — transcribe first." : "Captions added." }
                editTimeline("Show Captions") { $0.captions?.isEnabled = true }
                return "Captions on."
            }
            guard timeline.captions != nil else { return "There are no captions to hide." }
            editTimeline("Hide Captions") { $0.captions?.isEnabled = false }
            return "Captions hidden."
        case .captionStyle(let name):
            guard let preset = CaptionStyle.presets.first(where: { $0.presetName.lowercased().contains(name) }) else { return "No caption style called \(name)." }
            guard timeline.captions != nil else { return "Add captions first." }
            editTimeline("Caption Style: \(preset.presetName)") { t in
                let y = t.captions?.style.positionY ?? preset.positionY
                t.captions?.style = preset
                if t.layout == .splitScreen || t.layout == .dynamic { t.captions?.style.positionY = y }
            }
            return "Captions in the \(preset.presetName) style."
        case .music(let on):
            let musicClips = timeline.audioTracks.flatMap(\.clips).filter { audioRole(of: $0) == .music }
            if on {
                guard musicClips.isEmpty else {
                    editTimeline("Unmute Music") { t in for ti in t.tracks.indices { for ci in t.tracks[ti].clips.indices where self.audioRole(of: t.tracks[ti].clips[ci]) == .music { t.tracks[ti].clips[ci].audio.isMuted = false } } }
                    return "The music is back on."
                }
                addLibraryAudio(toShort: timeline.id, music: true, effects: false)
                return "Adding a music bed — it lands in a moment."
            }
            guard !musicClips.isEmpty else { return "There's no music on this timeline." }
            editTimeline("Mute Music") { t in for ti in t.tracks.indices { for ci in t.tracks[ti].clips.indices where self.audioRole(of: t.tracks[ti].clips[ci]) == .music { t.tracks[ti].clips[ci].audio.isMuted = true } } }
            return "Music muted."
        case .musicLevel(let delta):
            var touched = 0
            editTimeline("Music Level") { t in
                for ti in t.tracks.indices {
                    for ci in t.tracks[ti].clips.indices where self.audioRole(of: t.tracks[ti].clips[ci]) == .music {
                        t.tracks[ti].clips[ci].audio.gainDB = (t.tracks[ti].clips[ci].audio.gainDB + delta).clamped(-24, 24)
                        touched += 1
                    }
                }
            }
            return touched == 0 ? "There's no music on this timeline." : String(format: "Music %@ %.0f dB.", delta < 0 ? "down" : "up", abs(delta))
        case .zooms(let more):
            if more {
                var options = EntertainmentOptions()
                options.jumpCuts = false; options.removeFillers = false; options.captionEmphasis = false
                options.punchIns = true; options.reactionZooms = true
                makeMoreEntertaining(options: options)
                return "Adding punch-ins on the strongest sentences."
            }
            var dropped = 0
            editTimeline("Fewer Zooms") { t in
                var n = 0
                for ti in t.tracks.indices where t.tracks[ti].kind == .video {
                    for ci in t.tracks[ti].clips.indices where t.tracks[ti].clips[ci].transform.zoom.hasAIKeyframes {
                        n += 1
                        if n % 2 == 0 { t.tracks[ti].clips[ci].transform.removeAIKeyframes(); dropped += 1 }
                    }
                }
            }
            return dropped == 0 ? "There are no AI zooms to thin out." : "Dropped every other zoom (\(dropped))."
        case .removeZooms:
            var dropped = 0
            editTimeline("Remove Zooms") { t in
                for ti in t.tracks.indices where t.tracks[ti].kind == .video {
                    for ci in t.tracks[ti].clips.indices where t.tracks[ti].clips[ci].transform.zoom.hasAIKeyframes {
                        t.tracks[ti].clips[ci].transform.removeAIKeyframes(); dropped += 1
                    }
                }
            }
            return dropped == 0 ? "There are no AI zooms on this timeline." : "Removed the zooms on \(dropped) clip\(dropped == 1 ? "" : "s")."
        case .moreEntertaining:
            makeMoreEntertaining()
            return "Running Make More Entertaining."
        case .progressBar(let on):
            let present = ProgressBar.isPresent(timeline)
            if on == present { return on ? "There's already a progress bar." : "There's no progress bar to remove." }
            toggleProgressBar()
            return on ? "Progress bar added." : "Progress bar removed."
        case .addMarker(let name):
            addMarker(name: name)
            return "Marker “\(name)” added at \(Timecode.short(playback.currentTime))."
        case .speed(let x):
            guard !selectedClipIDs.isEmpty else { return "Select the clips to change first, then ask again." }
            setSpeed(x)
            return String(format: "Selected clips set to %.2f×.", x)
        case .closeGaps:
            closeAllGaps()
            return "Gaps closed."
        case .roomTone:
            fillRoomTone()
            return "Room tone applied where it could be."
        case .removeAI:
            stripAI()
            return "AI edits removed."
        case .unknown:
            return "I didn't get that. Try: " + EditorAssistant.examples.prefix(4).map { "“\($0)”" }.joined(separator: ", ") + "."
        }
    }

    private func report(_ what: String, before: Seconds) -> String {
        let after = activeTimeline?.duration ?? before
        let saved = before - after
        return saved > 0.05 ? "\(what) — \(Timecode.short(before)) → \(Timecode.short(after))." : "\(what) — nothing to take out."
    }
}
