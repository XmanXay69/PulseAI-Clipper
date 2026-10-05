import Foundation

/// The finishing passes a human editor does after the rough cut — each one small, each one the
/// difference between "AI cut" and "edited": clean audio at every cut, no slivers, hidden jump cuts,
/// boring stretches gone, music that gets out of the way of the punchline, a gentle grade, an end screen.
/// All of it stays ordinary, editable timeline content.
public enum EditPolish {
    /// Minimum length of a kept piece; anything shorter is a breath, a half-word or a flash frame.
    public static let minimumPiece: Seconds = 0.35
    /// Audio fade at every cut point (kills clicks/pops without being heard as a fade).
    public static let cutFade: Seconds = 0.03

    // MARK: Slivers

    /// Ripple-deletes video+audio pieces shorter than `minimumPiece` that don't hold a whole word.
    /// Returns how many were removed.
    @discardableResult
    public static func removeMicroFragments(_ timeline: inout Timeline, words: [TranscriptWord] = [], after start: Seconds = 0) -> Int {
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return 0 }
        var removed = 0
        // Work from the end so earlier positions stay valid while rippling.
        let candidates = timeline.tracks[v].clips
            .filter { $0.start >= start - 0.01 && $0.duration < minimumPiece && $0.content.assetID != nil }
            .sorted { $0.start > $1.start }
        for clip in candidates {
            let holdsWord = words.contains { $0.start >= clip.sourceIn - 0.01 && $0.end <= clip.sourceOut + 0.01 }
            if holdsWord { continue }
            timeline.rippleDelete(range: clip.timelineRange)
            removed += 1
        }
        return removed
    }

    // MARK: Clean cuts

    /// Gives every dialogue piece a tiny fade in/out so jump cuts never click. Returns pieces touched.
    @discardableResult
    public static func addCutFades(_ timeline: inout Timeline) -> Int {
        var touched = 0
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
            for ci in timeline.tracks[ti].clips.indices {
                let clip = timeline.tracks[ti].clips[ci]
                guard clip.role != .music, clip.role != .soundEffect, clip.content.assetID != nil, clip.duration > cutFade * 3 else { continue }
                var changed = false
                if clip.audio.fadeIn < cutFade { timeline.tracks[ti].clips[ci].audio.fadeIn = cutFade; changed = true }
                if clip.audio.fadeOut < cutFade { timeline.tracks[ti].clips[ci].audio.fadeOut = cutFade; changed = true }
                if changed { touched += 1 }
            }
        }
        return touched
    }

    // MARK: Hidden jump cuts

    /// The classic YouTube trick: on every other jump cut, the frame steps in slightly, so a cut inside the
    /// same shot reads as a deliberate camera change instead of a glitch. Resets at each new segment.
    /// Returns how many pieces were pushed in.
    @discardableResult
    public static func jumpCutZooms(_ timeline: inout Timeline, from start: Seconds, segmentStarts: [Seconds], scale: Double) -> Int {
        guard scale > 1.001, let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return 0 }
        let order = timeline.tracks[v].clips.indices.filter { timeline.tracks[v].clips[$0].start >= start - 0.01 }
            .sorted { timeline.tracks[v].clips[$0].start < timeline.tracks[v].clips[$1].start }
        var zoomed = 0
        var stepped = false
        var previous: TimelineClip?
        for ci in order {
            let clip = timeline.tracks[v].clips[ci]
            let newSegment = segmentStarts.contains { abs($0 - clip.start) < 0.05 }
            if newSegment || previous == nil {
                stepped = false
            } else if let prev = previous, prev.content.assetID == clip.content.assetID, abs(prev.end - clip.start) < 0.02,
                      clip.sourceIn - prev.sourceOut > 0.5 {
                // A real jump in the source: alternate framing.
                stepped.toggle()
            }
            if stepped && clip.duration >= 1 {
                timeline.tracks[v].clips[ci].transform.zoom.value *= scale
                zoomed += 1
            }
            previous = clip
        }
        return zoomed
    }

    // MARK: Boring stretches

    /// Stretches inside `range` with nobody talking for at least `minimum` seconds and below-typical
    /// energy: the "nothing's happening" parts a viewer would skip. Returns source ranges to cut,
    /// each leaving `keep` seconds on both sides so the edit still breathes.
    public static func deadSpans(in range: TimeRange, words: [TranscriptWord], excitement: [Float], step: Seconds,
                                 minimum: Seconds = 3.5, keep: Seconds = 0.6) -> [TimeRange] {
        guard !excitement.isEmpty, step > 0, range.duration > minimum else { return [] }
        let inside = words.filter { $0.end > range.start && $0.start < range.end }.sorted { $0.start < $1.start }
        var gaps: [TimeRange] = []
        var cursor = range.start
        for w in inside {
            if w.start - cursor >= minimum { gaps.append(TimeRange(start: cursor, end: w.start)) }
            cursor = max(cursor, w.end)
        }
        if range.end - cursor >= minimum { gaps.append(TimeRange(start: cursor, end: range.end)) }
        guard !gaps.isEmpty else { return [] }
        func level(_ r: TimeRange) -> Float {
            let a = Int(r.start / step).clamped(0, excitement.count - 1)
            let b = max(a, Int(r.end / step).clamped(0, excitement.count - 1))
            return excitement[a...b].max() ?? 0
        }
        let segment = level(range)
        var typical = excitement[Int(range.start / step).clamped(0, excitement.count - 1)...Int(range.end / step).clamped(0, excitement.count - 1)].sorted()
        if typical.isEmpty { typical = [segment] }
        let median = typical[typical.count / 2]
        return gaps.compactMap { gap in
            // Something happening on screen or in the room (a fight, a scream, laughter) keeps it.
            guard level(gap) <= median * 1.05 else { return nil }
            let cut = TimeRange(start: gap.start + keep, end: gap.end - keep)
            return cut.duration >= 1 ? cut : nil
        }
    }

    // MARK: Music

    /// Pulls the music out for a beat on the biggest punchlines ("record-scratch silence"), then brings it
    /// back. `times` are timeline times. Returns how many drops were placed.
    @discardableResult
    public static func musicDrops(_ timeline: inout Timeline, at times: [Seconds], length: Seconds = 1.6) -> Int {
        var placed = 0
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
            for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].role == .music {
                let clip = timeline.tracks[ti].clips[ci]
                for t in times where t > clip.start + 1 && t + length < clip.end - 1 {
                    let local = t - clip.start
                    var volume = clip.audio.volume
                    let base = volume.value
                    volume.setKeyframe(at: local - 0.15, value: base, interpolation: .linear, aiGenerated: true)
                    volume.setKeyframe(at: local, value: 0, interpolation: .hold, aiGenerated: true)
                    volume.setKeyframe(at: local + length, value: 0, interpolation: .easeIn, aiGenerated: true)
                    volume.setKeyframe(at: local + length + 0.8, value: base, interpolation: .linear, aiGenerated: true)
                    timeline.tracks[ti].clips[ci].audio.volume = volume
                    placed += 1
                }
            }
        }
        return placed
    }

    // MARK: Look

    /// A gentle "make it pop" grade on the main footage: a touch more contrast and colour, never a filter look.
    @discardableResult
    public static func grade(_ timeline: inout Timeline) -> Int {
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return 0 }
        var graded = 0
        for ci in timeline.tracks[v].clips.indices where timeline.tracks[v].clips[ci].content.assetID != nil {
            var color = timeline.tracks[v].clips[ci].color
            guard color.isIdentity else { continue }
            color.contrast = 0.06
            color.saturation = 0.08
            timeline.tracks[v].clips[ci].color = color
            graded += 1
        }
        return graded
    }

    // MARK: Ending

    /// A 10-second end screen after the last moment: dark slate, "thanks for watching", the right half left
    /// clear for YouTube's end-screen cards (videos / subscribe). Music plays out under it.
    public static func addEndScreen(_ timeline: inout Timeline, length: Seconds = 10) {
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }), let last = timeline.tracks[v].clips.max(by: { $0.end < $1.end }) else { return }
        let at = last.end
        if let li = timeline.tracks[v].clips.firstIndex(where: { $0.id == last.id }) {
            timeline.tracks[v].clips[li].transitionOut = ClipTransition(kind: .fadeToBlack, duration: 0.5, aiGenerated: true)
        }
        var slate = TimelineClip(name: "End Screen", content: .solid(RGBAColor(hex: "#0E0E12")!), start: at, sourceDuration: length, aiGenerated: true)
        slate.transitionIn = ClipTransition(kind: .fadeToBlack, duration: 0.5, aiGenerated: true)
        timeline.tracks[v].clips.append(slate)
        timeline.tracks[v].sortClips()
        guard let t = timeline.tracks.firstIndex(where: { $0.kind == .text }) else { return }
        let title = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 84, weight: .black, textCase: .uppercase, color: .white,
                              strokeColor: .black, strokeWidth: 0, shadowOpacity: 0.4, shadowRadius: 10, shadowOffsetY: 4)
        var thanks = TimelineClip(name: "End Screen Title", content: .text(TextElement(text: "Thanks for watching", style: title, animationIn: .fadeIn,
                                                                                      animationOut: .fadeIn, animationDuration: 0.4, maxWidth: 0.42)),
                                  start: at + 0.6, sourceDuration: length - 0.8, aiGenerated: true)
        thanks.transform.positionX = AnimatedDouble(0.27)
        thanks.transform.positionY = AnimatedDouble(0.42)
        let sub = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 40, weight: .semibold, textCase: .asTyped,
                            color: RGBAColor(hex: "#B8B8C4")!, strokeWidth: 0, shadowOpacity: 0)
        var more = TimelineClip(name: "End Screen Subtitle", content: .text(TextElement(text: "More videos →", style: sub, animationIn: .fadeIn,
                                                                                       animationOut: .fadeIn, animationDuration: 0.4, maxWidth: 0.42)),
                                start: at + 1.2, sourceDuration: length - 1.4, aiGenerated: true)
        more.transform.positionX = AnimatedDouble(0.27)
        more.transform.positionY = AnimatedDouble(0.56)
        timeline.tracks[t].clips.append(contentsOf: [thanks, more])
        timeline.tracks[t].sortClips()
    }
}

// MARK: - Checks

/// What an editor checks before exporting — run on every AI edit (fixable problems are fixed) and on
/// demand (Edit → Check Edit).
public struct EditCheckReport: Sendable {
    public struct Issue: Hashable, Sendable {
        public enum Severity: String, Sendable { case fixed, warning, note }
        public var severity: Severity
        public var title: String
        public var detail: String
    }

    public var issues: [Issue] = []
    public var fixed: [Issue] { issues.filter { $0.severity == .fixed } }
    public var open: [Issue] { issues.filter { $0.severity != .fixed } }

    public var summary: String {
        if issues.isEmpty { return "All checks passed" }
        var parts: [String] = []
        if !fixed.isEmpty { parts.append("fixed \(fixed.count)") }
        if !open.isEmpty { parts.append("\(open.count) to look at") }
        return "Checks: " + parts.joined(separator: ", ")
    }

    /// Plain-text report for a dialog.
    public var text: String {
        if issues.isEmpty { return "No slivers, clicks, gaps, overlaps or loud music — the edit is clean." }
        return issues.map { i in
            let mark = i.severity == .fixed ? "✓ Fixed" : (i.severity == .warning ? "⚠︎" : "•")
            return "\(mark) \(i.title) — \(i.detail)"
        }.joined(separator: "\n")
    }
}

public enum EditQualityCheck {
    /// Fixes what's mechanical (slivers, unfaded cuts, gaps, loud music), then reports what needs a human.
    @discardableResult
    public static func run(_ timeline: inout Timeline, words: [TranscriptWord] = [], target: ClosedRange<Seconds>? = nil, autofix: Bool = true) -> EditCheckReport {
        var report = EditCheckReport()
        func add(_ s: EditCheckReport.Issue.Severity, _ title: String, _ detail: String) {
            report.issues.append(.init(severity: s, title: title, detail: detail))
        }
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return report }

        // 1. Slivers.
        let short = timeline.tracks[v].clips.filter { $0.duration < EditPolish.minimumPiece && $0.content.assetID != nil }
        let wordy = short.filter { c in words.contains { $0.start >= c.sourceIn - 0.01 && $0.end <= c.sourceOut + 0.01 } }.count
        let slivers = short.count - wordy
        if slivers > 0 {
            if autofix {
                let removed = EditPolish.removeMicroFragments(&timeline, words: words)
                add(.fixed, "Slivers removed", "\(removed) piece\(removed == 1 ? "" : "s") under \(Int(EditPolish.minimumPiece * 1000)) ms (flash frames, half-breaths)")
            } else {
                add(.warning, "Slivers", "\(slivers) piece\(slivers == 1 ? "" : "s") under \(Int(EditPolish.minimumPiece * 1000)) ms")
            }
        }
        if wordy > 0 { add(.note, "Very short pieces", "\(wordy) hold a whole word — check they don't feel choppy") }

        // 2. Clicks at cuts.
        let unfaded = timeline.tracks.filter { $0.kind == .audio }.flatMap(\.clips)
            .filter { $0.role != .music && $0.role != .soundEffect && $0.content.assetID != nil && $0.duration > EditPolish.cutFade * 3
                && ($0.audio.fadeIn < EditPolish.cutFade || $0.audio.fadeOut < EditPolish.cutFade) }.count
        if unfaded > 0 {
            if autofix {
                EditPolish.addCutFades(&timeline)
                add(.fixed, "Clicks at cuts", "\(unfaded) dialogue cut\(unfaded == 1 ? "" : "s") got a \(Int(EditPolish.cutFade * 1000)) ms fade")
            } else {
                add(.warning, "Possible clicks", "\(unfaded) dialogue cuts have no fade")
            }
        }

        // 3. Black gaps on the main track.
        let gaps = blackGaps(in: timeline.tracks[v].clips)
        if !gaps.isEmpty {
            if autofix {
                for gap in gaps.sorted(by: { $0.start > $1.start }) { timeline.rippleDelete(range: gap) }
                add(.fixed, "Gaps closed", "\(gaps.count) black gap\(gaps.count == 1 ? "" : "s") on the main track")
            } else {
                add(.warning, "Black gaps", "\(gaps.count) on the main track")
            }
        }

        // 4. Music level.
        let loud = timeline.tracks.filter { $0.kind == .audio }.flatMap(\.clips).filter { $0.role == .music && $0.audio.volume.value > 0.25 && !$0.audio.duckUnderDialogue }
        if !loud.isEmpty {
            if autofix {
                for ti in timeline.tracks.indices {
                    for ci in timeline.tracks[ti].clips.indices where loud.contains(where: { $0.id == timeline.tracks[ti].clips[ci].id }) {
                        timeline.tracks[ti].clips[ci].audio.duckUnderDialogue = true
                    }
                }
                add(.fixed, "Music ducked", "\(loud.count) loud music clip\(loud.count == 1 ? "" : "s") now drop under talking")
            } else {
                add(.warning, "Loud music", "\(loud.count) music clips aren't ducked under talking")
            }
        }

        // 5. Overlapping text (titles fighting each other).
        let texts = timeline.tracks.filter { $0.kind == .text }.flatMap(\.clips).sorted { $0.start < $1.start }
        // Only text that overlaps in time *and* sits at about the same height fights for attention.
        let overlaps = zip(texts, texts.dropFirst()).filter { a, b in
            a.end > b.start + 0.1 && abs(a.transform.positionY.value - b.transform.positionY.value) < 0.12
        }.count
        if overlaps > 0 { add(.warning, "Overlapping text", "\(overlaps) pop-up\(overlaps == 1 ? "" : "s") overlap another — move or shorten one") }

        // 6. Zooms stacked on top of each other.
        let zoomTimes = timeline.tracks[v].clips.flatMap { c in c.transform.zoom.keyframes.filter(\.aiGenerated).map { c.start + $0.time } }.sorted()
        let starts = stride(from: 0, to: zoomTimes.count, by: 1).filter { i in i == 0 || zoomTimes[i] - zoomTimes[i - 1] > 0.6 }.map { zoomTimes[$0] }
        let crowded = zip(starts, starts.dropFirst()).filter { $1 - $0 < 2.5 }.count
        if crowded > 2 { add(.note, "Busy zooms", "\(crowded) zooms land within 2.5 s of the previous one") }

        // 7. Pacing: cuts per minute in the story.
        let duration = max(timeline.duration, 1)
        let cuts = Double(max(0, timeline.tracks[v].clips.count - 1))
        let perMinute = cuts / (duration / 60)
        if perMinute > 30 { add(.note, "Very fast cutting", String(format: "%.0f cuts a minute — fine for shorts, tiring over a long video", perMinute)) }

        // 8. Chapters too short to follow.
        let chapterTimes = timeline.markers.filter { $0.color == .blue }.map(\.time).sorted()
        let tiny = zip(chapterTimes, chapterTimes.dropFirst()).filter { $1 - $0 < 6 }.count
        if tiny > 0 { add(.note, "Very short chapters", "\(tiny) chapter\(tiny == 1 ? " is" : "s are") under 6 s — consider merging") }

        // 9. Length.
        if let target, !target.contains(duration) {
            add(.note, "Length", "\(Timecode.short(duration)) is outside the \(Timecode.short(target.lowerBound))–\(Timecode.short(target.upperBound)) target")
        }
        return report
    }

    /// Stretches of the main track with nothing on it, between the first and last clip.
    static func blackGaps(in clips: [TimelineClip]) -> [TimeRange] {
        let sorted = clips.filter(\.isEnabled).sorted { $0.start < $1.start }
        var gaps: [TimeRange] = []
        var reach = sorted.first?.start ?? 0
        for clip in sorted {
            if clip.start - reach > 0.05 { gaps.append(TimeRange(start: reach, end: clip.start)) }
            reach = max(reach, clip.end)
        }
        return gaps
    }
}
