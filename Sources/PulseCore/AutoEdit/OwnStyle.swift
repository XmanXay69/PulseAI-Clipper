import Foundation

extension ReferenceStyleAnalyzer {
    /// The fingerprint of a finished edit (#489): the same measurements as a studied reference, read
    /// off the timeline instead of the pixels. Nil for edits too short to say anything about.
    public static func measure(timeline: Timeline, assets: [MediaAsset], name: String? = nil) -> ReferenceStyle? {
        let duration = timeline.duration
        guard duration >= 5 else { return nil }
        let minutes = duration / 60
        let assetByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func role(_ clip: TimelineClip) -> MediaRole? { clip.role ?? clip.assetID.flatMap { assetByID[$0]?.role } }

        // Cuts: every distinct point where a picture clip starts (after the opening frame).
        func isPicture(_ clip: TimelineClip) -> Bool {
            switch clip.content {
            case .media, .compound: return true
            case .text, .solid: return false
            }
        }
        let visual = timeline.videoTracks.flatMap(\.clips).filter { $0.isEnabled && isPicture($0) }
        var cutTimes: [Seconds] = []
        for start in visual.map(\.start).sorted() where start > 0.05 {
            if let last = cutTimes.last, start - last < 0.05 { continue }
            cutTimes.append(start)
        }
        let firstCuts = cutTimes.filter { $0 < 20 }.count
        let opensFast = duration > 40 && Double(firstCuts) / min(20, duration) * 60 > (Double(cutTimes.count) / minutes) * 1.25 && firstCuts >= 2

        // Punch-ins: content zoom keyframes that step up by at least 8 %.
        var zoomScales: [Double] = []
        for clip in visual {
            let keys = clip.transform.zoom.keyframes
            guard keys.count >= 2 else { continue }
            for (a, b) in zip(keys, keys.dropFirst()) where b.value >= 1.08 && b.value - a.value >= 0.05 {
                zoomScales.append(b.value)
            }
        }
        zoomScales.sort()

        // Captions on screen.
        var look: ReferenceStyle.CaptionLook?
        var wordsPerMinute: Double?
        var pauseRatio: Double?
        if let captions = timeline.captions, captions.isEnabled {
            let words = CaptionLayoutEngine.timelineWords(captions, in: timeline)
            if !words.isEmpty {
                let pages = CaptionLayoutEngine.pages(words, style: captions.style)
                let covered = pages.map { min($0.range.end, duration) - $0.range.start }.filter { $0 > 0 }.reduce(0, +)
                let perPage = Double(pages.map(\.words.count).reduce(0, +)) / Double(max(pages.count, 1))
                look = ReferenceStyle.CaptionLook(coverage: (covered / duration).clamped(0, 1), positionY: captions.style.positionY,
                                                  lineHeight: captions.style.text.fontSize * 1.2 / Double(max(timeline.canvas.height, 1)),
                                                  wordsOnScreen: perPage, uppercase: captions.style.text.textCase == .uppercase)
                if words.count >= 20, let first = words.first, let last = words.last, last.end > first.start {
                    wordsPerMinute = Double(words.count) / minutes
                    var paused: Seconds = 0
                    for (a, b) in zip(words, words.dropFirst()) {
                        let gap = b.start - a.end
                        if gap > 0.35 && gap < 5 { paused += gap }
                    }
                    pauseRatio = paused / (last.end - first.start)
                }
            }
        }

        // Pop-ups: short text layers; music: how much of the edit has a music clip under it; effects: SFX clips.
        let popups = timeline.textTracks.flatMap(\.clips).filter { $0.isEnabled && $0.duration < 6 }.count
        let musicRanges = timeline.audioTracks.flatMap(\.clips).filter { $0.isEnabled && role($0) == .music }.map(\.timelineRange)
        let musicCovered = union(musicRanges).map { min($0.end, duration) - max($0.start, 0) }.filter { $0 > 0 }.reduce(0, +)
        let effects = timeline.audioTracks.flatMap(\.clips).filter { $0.isEnabled && role($0) == .soundEffect }.count
        var fadePoints: [Seconds] = []
        for clip in visual {
            if clip.transitionIn?.kind == .fadeToBlack { fadePoints.append(clip.start) }
            if clip.transitionOut?.kind == .fadeToBlack { fadePoints.append(clip.end) }
        }
        let fades = Set(fadePoints.map { Int(($0 * 10).rounded()) }).count

        return ReferenceStyle(name: name ?? timeline.name, duration: duration,
                              aspect: Double(timeline.canvas.width) / Double(max(timeline.canvas.height, 1)),
                              cutsPerMinute: Double(cutTimes.count) / minutes,
                              averageShotLength: duration / Double(cutTimes.count + 1),
                              zoomsPerMinute: Double(zoomScales.count) / minutes,
                              zoomScale: zoomScales.isEmpty ? 1.16 : zoomScales[zoomScales.count / 2],
                              captions: look, popupsPerMinute: Double(popups) / minutes,
                              wordsPerMinute: wordsPerMinute, pauseRatio: pauseRatio,
                              musicBed: (musicCovered / duration).clamped(0, 1),
                              effectsPerMinute: Double(effects) / minutes,
                              fadesPerMinute: Double(fades) / minutes,
                              opensFast: opensFast)
    }

    static func union(_ ranges: [TimeRange]) -> [TimeRange] {
        var out: [TimeRange] = []
        for r in ranges.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, r.start <= last.end {
                out[out.count - 1] = TimeRange(start: last.start, end: max(last.end, r.end))
            } else {
                out.append(r)
            }
        }
        return out
    }
}

extension ReferenceStyle {
    /// The id of the style learned from your own exports (#489); never one of the studied references.
    public static let ownStyleID = UUID(uuidString: "0B5E0000-5E1F-4000-8000-00000000A489")!

    /// One style averaging several measured edits (#489) — the newest counts the same as the oldest.
    public static func average(of styles: [ReferenceStyle], name: String) -> ReferenceStyle? {
        guard var result = styles.first else { return nil }
        for (i, next) in styles.dropFirst().enumerated() {
            // Fold each in with the weight that keeps every sample equal: the (i+2)th sample is 1/(i+2) of the mix.
            result = result.blended(with: next, weight: 1 / Double(i + 2), name: name)
        }
        result.name = name
        result.id = ownStyleID
        result.measuredAt = styles.map(\.measuredAt).max() ?? Date()
        return result
    }
}
