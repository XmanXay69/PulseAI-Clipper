import Foundation

/// Optional extras for Edit My VOD. PULSE asks before using any of them (the Extras step), and
/// remembers your last answers as the starting point for next time.
public struct EditExtras: Codable, Hashable, Sendable {
    /// Big reactions on gameplay-with-facecam zoom into the facecam instead of the middle of the screen.
    public var facecamPunchIns = false
    /// Short Creative Commons meme/reaction clips cut in on the funniest beats (downloaded from YouTube).
    public var brollClips = false
    /// Music starts on a beat and zooms land on beats.
    public var beatSync = false
    /// Sections start and end on whole sentences; talking-over-each-other stretches are trimmed.
    public var speakerAware = false
    /// Review every section (preview, keep, trim) before the final build.
    public var approveCut = false
    /// Short "THEN THIS HAPPENED…" cards when the video jumps ahead.
    public var titleCards = false
    /// Measure the final mix at export (YouTube plays at −14 LUFS) and offer to fix it.
    public var loudnessCheck = false

    public init(facecamPunchIns: Bool = false, brollClips: Bool = false, beatSync: Bool = false, speakerAware: Bool = false,
                approveCut: Bool = false, titleCards: Bool = false, loudnessCheck: Bool = false) {
        self.facecamPunchIns = facecamPunchIns
        self.brollClips = brollClips
        self.beatSync = beatSync
        self.speakerAware = speakerAware
        self.approveCut = approveCut
        self.titleCards = titleCards
        self.loudnessCheck = loudnessCheck
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        facecamPunchIns = c.decode(Bool.self, forKey: .facecamPunchIns, default: false)
        brollClips = c.decode(Bool.self, forKey: .brollClips, default: false)
        beatSync = c.decode(Bool.self, forKey: .beatSync, default: false)
        speakerAware = c.decode(Bool.self, forKey: .speakerAware, default: false)
        approveCut = c.decode(Bool.self, forKey: .approveCut, default: false)
        titleCards = c.decode(Bool.self, forKey: .titleCards, default: false)
        loudnessCheck = c.decode(Bool.self, forKey: .loudnessCheck, default: false)
    }

    public var anyEditTime: Bool { facecamPunchIns || brollClips || beatSync || speakerAware || titleCards }
}

// MARK: - Speaker-aware

public enum SpeakerAware {
    /// Moves each section's edges to whole sentences: back to where the sentence started (≤ `maxBack`),
    /// forward to where it finished (≤ `maxForward`). Never cut someone off mid-thought.
    public static func snapToSentences(_ segments: [LongFormSegment], words: [TranscriptWord], duration: Seconds,
                                       maxBack: Seconds = 4, maxForward: Seconds = 3) -> [LongFormSegment] {
        let sorted = words.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return segments }
        func endsSentence(_ w: TranscriptWord) -> Bool { w.text.hasSuffix(".") || w.text.hasSuffix("?") || w.text.hasSuffix("!") }
        return segments.map { segment in
            var s = segment
            var start = segment.range.start, end = segment.range.end
            // Start: the first word after a sentence end / long pause, at or before the current start.
            if let i = sorted.firstIndex(where: { $0.end > start }), sorted[i].start < start + 0.3 {
                var j = i
                while j > 0, sorted[j].start > start - maxBack,
                      !(endsSentence(sorted[j - 1]) || sorted[j].start - sorted[j - 1].end > 0.6) { j -= 1 }
                if sorted[j].start >= start - maxBack { start = max(0, sorted[j].start - 0.1) }
            }
            // End: the end of the sentence that's running at the current end.
            if let i = sorted.lastIndex(where: { $0.start < end }), sorted[i].end > end - 0.3 {
                var j = i
                while j < sorted.count - 1, sorted[j].end < end + maxForward,
                      !(endsSentence(sorted[j]) || sorted[j + 1].start - sorted[j].end > 0.6) { j += 1 }
                if sorted[j].end <= end + maxForward { end = min(duration, sorted[j].end + 0.25) }
            }
            s.range = TimeRange(start: start, end: max(end, start + 0.5))
            return s
        }
    }

    /// Stretches inside `range` where two or more people talk over each other for ≥ `minimum` seconds,
    /// away from the section's payoff. Needs speaker labels (Detect Speakers); otherwise empty.
    public static func crosstalk(in range: TimeRange, words: [TranscriptWord], protect: Seconds, minimum: Seconds = 1.5) -> [TimeRange] {
        let inside = words.filter { $0.speaker != nil && $0.end > range.start && $0.start < range.end }.sorted { $0.start < $1.start }
        guard Set(inside.compactMap(\.speaker)).count >= 2 else { return [] }
        var overlaps: [TimeRange] = []
        for (i, a) in inside.enumerated() {
            for b in inside[(i + 1)...] {
                if b.start >= a.end { break }
                if b.speaker != a.speaker { overlaps.append(TimeRange(start: max(a.start, b.start), end: min(a.end, b.end))) }
            }
        }
        return overlaps.merged(gap: 0.5).filter { $0.duration >= minimum && !$0.expanded(by: 3).contains(protect) }
    }
}

// MARK: - Retention cards

public enum RetentionCards {
    /// "THEN THIS HAPPENED…", "20 MINUTES LATER…", "IT GETS WORSE" — chosen from what comes next and how far
    /// the video jumped.
    public static func text(for segment: LongFormSegment, after previous: LongFormSegment, index: Int) -> String {
        let jump = segment.range.start - previous.range.end
        let tags = Set(segment.tags)
        if jump >= 600 { return "\(Int((jump / 60).rounded())) MINUTES LATER…" }
        if !tags.isDisjoint(with: [.fail, .rage]) { return "IT GETS WORSE" }
        if !tags.isDisjoint(with: [.story, .conversation]) { return index % 2 == 0 ? "STORY TIME" : "WAIT FOR IT…" }
        if !tags.isDisjoint(with: [.hype, .highEnergy, .gaming]) { return index % 2 == 0 ? "THEN THIS HAPPENED…" : "AND THEN…" }
        return ["MEANWHILE…", "THEN THIS HAPPENED…", "WAIT FOR IT…"][index % 3]
    }

    /// One short card at the start of sections that follow a real jump in the stream (≥ 2 minutes),
    /// at most one every 90 seconds, never on top of other text. Returns how many were added.
    @discardableResult
    public static func add(_ timeline: inout Timeline, segments: [LongFormSegment], starts: [Seconds?], hookEnd: Seconds) -> Int {
        guard let t1 = timeline.tracks.firstIndex(where: { $0.kind == .text }) else { return 0 }
        var added = 0
        var last = -Double.infinity
        for i in segments.indices.dropFirst() {
            guard let t = starts[i], t > hookEnd + 1, t - last >= 90,
                  segments[i].range.start - segments[i - 1].range.end >= 120,
                  !timeline.tracks[t1].clips.contains(where: { $0.timelineRange.overlaps(TimeRange(start: t - 0.5, end: t + 2.5)) }) else { continue }
            let style = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 64, weight: .black, textCase: .uppercase, color: .white,
                                  strokeColor: .black, strokeWidth: 8, shadowOpacity: 0.55, shadowRadius: 8, shadowOffsetY: 4)
            var card = TimelineClip(name: "Title Card", content: .text(TextElement(text: text(for: segments[i], after: segments[i - 1], index: added),
                                                                                   style: style, animationIn: .pop, animationOut: .fadeIn,
                                                                                   animationDuration: 0.2, maxWidth: 0.7)),
                                    start: t + 0.1, sourceDuration: 1.7, aiGenerated: true)
            card.transform.positionY = AnimatedDouble(0.16)
            timeline.tracks[t1].clips.append(card)
            last = t
            added += 1
        }
        timeline.tracks[t1].sortClips()
        return added
    }
}

// MARK: - Facecam punch-ins

public enum FacecamPunchIn {
    /// On big reactions, push in on the facecam (zoom + pan so the webcam fills most of the frame), hold,
    /// and come back. `region` is the facecam overlay in the source (normalized). Returns how many.
    @discardableResult
    public static func apply(_ timeline: inout Timeline, at times: [Seconds], region: NormRect, hold: Seconds = 1.8) -> Int {
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }), region.width > 0.05, region.height > 0.05 else { return 0 }
        let zoom = (0.85 / max(region.width, region.height)).clamped(1.3, 2.6)
        let px = region.center.x - 0.5, py = region.center.y - 0.5
        var applied = 0
        for t in times.sorted() {
            guard let ci = timeline.tracks[v].clips.firstIndex(where: { $0.timelineRange.contains(t) && $0.content.assetID != nil }) else { continue }
            let clip = timeline.tracks[v].clips[ci]
            let local = t - clip.start
            guard local > 0.25, local + hold + 0.5 < clip.duration else { continue }
            var transform = clip.transform
            // Replace any centre punch-in at this moment.
            for k in transform.zoom.keyframes where k.aiGenerated && k.time > local - 1.5 && k.time < local + hold + 1.5 {
                transform.zoom.removeKeyframe(id: k.id)
            }
            let base = transform.zoom.value
            transform.zoom.setKeyframe(at: local - 0.22, value: base, interpolation: .easeOut, aiGenerated: true)
            transform.zoom.setKeyframe(at: local, value: base * zoom, interpolation: .hold, aiGenerated: true)
            transform.zoom.setKeyframe(at: local + hold, value: base * zoom, interpolation: .easeInOut, aiGenerated: true)
            transform.zoom.setKeyframe(at: local + hold + 0.35, value: base, interpolation: .linear, aiGenerated: true)
            for (axis, offset) in [(\VisualTransform.panX, px), (\VisualTransform.panY, py)] {
                var pan = transform[keyPath: axis]
                let rest = pan.value(at: local - 0.22)
                pan.setKeyframe(at: local - 0.22, value: rest, interpolation: .easeOut, aiGenerated: true)
                pan.setKeyframe(at: local, value: offset, interpolation: .hold, aiGenerated: true)
                pan.setKeyframe(at: local + hold, value: offset, interpolation: .easeInOut, aiGenerated: true)
                pan.setKeyframe(at: local + hold + 0.35, value: rest, interpolation: .linear, aiGenerated: true)
                transform[keyPath: axis] = pan
            }
            timeline.tracks[v].clips[ci].transform = transform
            applied += 1
        }
        return applied
    }
}

// MARK: - Beat sync

public enum BeatSync {
    /// Starts each music piece on its first beat (skipping a silent or sloppy intro), so chapter changes —
    /// where the music pieces start — land on a beat. A piece that already uses the whole track gets that
    /// much shorter (it ends ≤ 4 s early, where it fades anyway). `beats` are source times per music asset;
    /// `durations` the assets' lengths. Returns pieces moved.
    @discardableResult
    public static func alignMusic(_ timeline: inout Timeline, beats: [UUID: [Seconds]], durations: [UUID: Seconds]) -> Int {
        var moved = 0
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
            for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].role == .music {
                let clip = timeline.tracks[ti].clips[ci]
                guard let id = clip.content.assetID, let grid = beats[id], let length = durations[id],
                      let first = grid.first(where: { $0 >= clip.sourceIn + 0.02 && $0 <= clip.sourceIn + 4 }) else { continue }
                let room = length - (first + clip.sourceDuration)
                let shortened = room < 0 ? clip.sourceDuration + room : clip.sourceDuration
                guard shortened >= 2 else { continue }
                timeline.tracks[ti].clips[ci].sourceIn = first
                timeline.tracks[ti].clips[ci].sourceDuration = shortened
                moved += 1
            }
        }
        return moved
    }

    /// Beat times on the timeline, from the music pieces placed on it.
    public static func timelineBeats(_ timeline: Timeline, beats: [UUID: [Seconds]]) -> [Seconds] {
        timeline.tracks.filter { $0.kind == .audio }.flatMap(\.clips).filter { $0.role == .music }.flatMap { clip -> [Seconds] in
            guard let id = clip.content.assetID, let grid = beats[id] else { return [] }
            return grid.filter { $0 >= clip.sourceIn && $0 < clip.sourceOut }.map { clip.start + ($0 - clip.sourceIn) / max(clip.speed, 0.01) }
        }.sorted()
    }

    /// Nudges each AI zoom (ramp, hit, hold, release — and any pan that goes with it) so its hit lands on the
    /// nearest beat, if one is within `tolerance`. Returns zooms moved.
    @discardableResult
    public static func snapZooms(_ timeline: inout Timeline, beats: [Seconds], tolerance: Seconds = 0.2) -> Int {
        guard !beats.isEmpty, let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return 0 }
        var moved = 0
        for ci in timeline.tracks[v].clips.indices {
            let clip = timeline.tracks[v].clips[ci]
            let keys = clip.transform.zoom.keyframes.filter(\.aiGenerated).sorted { $0.time < $1.time }
            guard !keys.isEmpty else { continue }
            // Group keyframes into individual zooms (a zoom's keyframes are never more than ~2 s apart).
            var groups: [[ValueKeyframe]] = [[keys[0]]]
            for k in keys.dropFirst() {
                if k.time - groups[groups.count - 1].last!.time > 2.5 { groups.append([k]) } else { groups[groups.count - 1].append(k) }
            }
            var transform = clip.transform
            for group in groups where group.count >= 2 {
                let hit = group[1].time + clip.start
                guard let beat = beats.min(by: { abs($0 - hit) < abs($1 - hit) }), abs(beat - hit) <= tolerance, abs(beat - hit) > 0.01 else { continue }
                let delta = beat - hit
                let span = (group.first!.time - 0.01)...(group.last!.time + 0.01)
                guard span.lowerBound + delta > 0, span.upperBound + delta < clip.duration else { continue }
                // Move in the direction of travel so keyframes never cross.
                func shift(_ value: inout AnimatedDouble, _ ids: [ValueKeyframe]) {
                    for k in (delta > 0 ? ids.reversed() : ids) { value.moveKeyframe(id: k.id, to: k.time + delta) }
                }
                let panX = transform.panX.keyframes.filter { $0.aiGenerated && span.contains($0.time) }
                let panY = transform.panY.keyframes.filter { $0.aiGenerated && span.contains($0.time) }
                shift(&transform.zoom, group)
                shift(&transform.panX, panX)
                shift(&transform.panY, panY)
                moved += 1
            }
            timeline.tracks[v].clips[ci].transform = transform
        }
        return moved
    }

    /// Beat grid from an onset-strength envelope (hop seconds): tempo by autocorrelation in 70–180 BPM (leaning
    /// towards ~120), phase by the strongest comb alignment over the first bars, then each beat snapped to the
    /// local onset peak so a slightly-off tempo never drifts across a whole track.
    public static func beats(onsets: [Float], hop: Seconds, duration: Seconds) -> [Seconds] {
        let n = onsets.count
        guard n > 32, hop > 0 else { return [] }
        let mean = onsets.reduce(0, +) / Float(n)
        let x = onsets.map { max(0, $0 - mean) }
        let minLag = max(1, Int((60.0 / 180) / hop)), maxLag = min(n / 2, Int((60.0 / 70) / hop) + 1)
        guard maxLag > minLag + 1 else { return [] }
        var ac = [Float](repeating: 0, count: maxLag + 2)
        for lag in (minLag - 1)...(maxLag + 1) where lag > 0 && lag < n {
            var s: Float = 0
            for i in lag..<n { s += x[i] * x[i - lag] }
            ac[lag] = s / Float(n - lag)
        }
        var bestLag = minLag, bestScore: Float = 0
        for lag in minLag...maxLag {
            let bpm = 60 / (Double(lag) * hop)
            let prior = Float(exp(-0.5 * pow(log2(bpm / 120), 2)))
            if ac[lag] * prior > bestScore { bestScore = ac[lag] * prior; bestLag = lag }
        }
        guard bestScore > 0 else { return [] }
        // Sub-hop period from the peak's neighbours.
        var period = Double(bestLag)
        let a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1]
        let curvature = a - 2 * b + c
        if curvature < 0 { period += Double(0.5 * (a - c) / curvature).clamped(-0.5, 0.5) }
        // Phase from the first few bars only: any small tempo error adds up over a whole track.
        let span = min(n, Int(period * 8) + 1)
        var bestPhase = 0, phaseScore: Float = -1
        for phase in 0..<bestLag {
            var s: Float = 0
            var t = Double(phase)
            while Int(t.rounded()) < span { s += x[Int(t.rounded())]; t += period }
            if s > phaseScore { phaseScore = s; bestPhase = phase }
        }
        let window = max(1, Int(period * 0.12))
        var out: [Seconds] = []
        var t = Double(bestPhase)
        while Int(t.rounded()) < n {
            let centre = Int(t.rounded())
            var best = centre
            for i in max(0, centre - window)...min(n - 1, centre + window) where x[i] > x[best] { best = i }
            let beat = x[best] > 0 ? Double(best) : t
            if beat * hop < duration { out.append(beat * hop) }
            t = beat + period
        }
        return out
    }
}

// MARK: - B-roll

public enum BrollPlacer {
    public struct Moment: Hashable, Sendable {
        public var time: Seconds
        public var query: String
    }

    /// Search phrase for a moment's mood.
    public static func query(for tags: [ClipTag]) -> String {
        let set = Set(tags)
        if set.contains(.fail) { return "bruh moment meme" }
        if set.contains(.funny) { return "funny laughing reaction meme" }
        if set.contains(.rage) { return "angry reaction meme" }
        if !set.isDisjoint(with: [.hype, .highEnergy]) { return "lets go hype reaction meme" }
        if set.contains(.reaction) { return "shocked surprised reaction meme" }
        return "wow reaction meme"
    }

    /// The funniest beats worth a cutaway: strongest first, ≥ 60 s apart, not in the hook, at most one per
    /// ~2 minutes of video.
    public static func moments(segments: [LongFormSegment], timelineTime: (Seconds) -> Seconds?, hookEnd: Seconds, duration: Seconds) -> [Moment] {
        let budget = max(1, min(6, Int(duration / 120)))
        var out: [Moment] = []
        for s in segments.sorted(by: { $0.potential > $1.potential }) where s.potential >= 55 && out.count < budget {
            guard !Set(s.tags).isDisjoint(with: [.funny, .fail, .reaction, .hype, .rage, .highEnergy]),
                  let t = timelineTime(s.payoff), t > hookEnd + 2, !out.contains(where: { abs($0.time - t) < 60 }) else { continue }
            out.append(Moment(time: t + 0.4, query: query(for: s.tags)))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Ranks downloaded search results: short, clearly a meme/reaction, no green screen (would need keying).
    public static func score(_ r: VideoSearchResult) -> Double? {
        let t = (r.title + " " + r.channel).lowercased()
        guard let d = r.duration, d >= 2, d <= 40 else { return nil }
        if ["green screen", "greenscreen", "chroma", "compilation", "1 hour", "tutorial", "template"].contains(where: { t.contains($0) }) { return nil }
        var s = 0.0
        for w in ["meme", "reaction", "no copyright", "free to use", "creative commons", "sound effect"] where t.contains(w) { s += 1 }
        return s - d / 40
    }

    /// Credits for the description: one line per distinct clip.
    public static func creditBlock(_ clips: [OnlineTrack]) -> String {
        var seen = Set<String>()
        let lines = clips.filter { seen.insert($0.videoID).inserted }.map { "▶ " + $0.credit }
        return lines.isEmpty ? "" : (["Clips"] + lines).joined(separator: "\n")
    }

    /// Cuts each clip in on a "V2 B-roll" track above the main video (full frame, quick dissolves), with its
    /// sound on the effects track at a moderate level. Returns clips placed.
    @discardableResult
    public static func place(_ timeline: inout Timeline, clips: [(asset: MediaAsset, at: Seconds)], maxLength: Seconds = 2.4) -> Int {
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return 0 }
        var track: Int
        if let existing = timeline.tracks.firstIndex(where: { $0.name == "V2 B-roll" }) {
            track = existing
        } else {
            timeline.tracks.insert(Track(kind: .video, name: "V2 B-roll"), at: v + 1)
            track = v + 1
        }
        let sfx = timeline.tracks.firstIndex { $0.kind == .audio && $0.name.hasPrefix("A3") }
            ?? timeline.tracks.lastIndex { $0.kind == .audio }
        var placed = 0
        for item in clips {
            let length = min(maxLength, item.asset.metadata.duration > 0 ? item.asset.metadata.duration : maxLength)
            guard length > 0.5, item.at + length < timeline.duration,
                  !timeline.tracks[track].clips.contains(where: { $0.timelineRange.overlaps(TimeRange(start: item.at, end: item.at + length)) }) else { continue }
            let group = UUID()
            var clip = TimelineClip(name: "B-roll: \(item.asset.name)", content: .media(assetID: item.asset.id), start: item.at, sourceDuration: length,
                                    linkGroup: group, role: .graphic, aiGenerated: true)
            clip.transform.fit = .fill
            clip.transitionIn = ClipTransition(kind: .crossDissolve, duration: 0.12, aiGenerated: true)
            clip.transitionOut = ClipTransition(kind: .crossDissolve, duration: 0.15, aiGenerated: true)
            timeline.tracks[track].clips.append(clip)
            if item.asset.metadata.hasAudio, let sfx {
                var sound = TimelineClip(name: "B-roll: \(item.asset.name)", content: .media(assetID: item.asset.id), start: item.at, sourceDuration: length,
                                         linkGroup: group, role: .soundEffect, aiGenerated: true)
                sound.audio.volume = AnimatedDouble(0.55)
                sound.audio.fadeIn = 0.05
                sound.audio.fadeOut = 0.2
                timeline.tracks[sfx].clips.append(sound)
                timeline.tracks[sfx].sortClips()
            }
            placed += 1
        }
        timeline.tracks[track].sortClips()
        return placed
    }
}

// MARK: - Loudness

/// BS.1770 integrated loudness measured in pieces (so a 20-minute mix never sits in memory), plus peak.
public struct StreamingLoudness: Sendable {
    public let sampleRate: Double
    private var shelves: [Biquad] = []
    private var highPasses: [Biquad] = []
    private var subBlock: Int
    private var subFill = 0
    private var subSum = 0.0
    /// Mean square (summed over channels) of each 100 ms sub-block.
    private var subPowers: [Double] = []
    public private(set) var peak: Float = 0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        subBlock = max(1, Int(0.1 * sampleRate))
    }

    /// Feeds de-interleaved samples (any number of frames).
    public mutating func add(_ channels: [[Float]]) {
        guard let frames = channels.first?.count, frames > 0 else { return }
        while shelves.count < channels.count {
            shelves.append(Biquad.highShelf(frequency: 1681.974450955533, gainDB: 3.999843853973347, q: 0.7071752369554196, sampleRate: sampleRate))
            highPasses.append(Biquad.highPass(frequency: 38.13547087602444, q: 0.5003270373238773, sampleRate: sampleRate))
        }
        for i in 0..<frames {
            var power = 0.0
            for c in channels.indices {
                let x = channels[c][i]
                peak = max(peak, abs(x))
                let y = highPasses[c].process(shelves[c].process(Double(x)))
                power += y * y
            }
            subSum += power
            subFill += 1
            if subFill == subBlock {
                subPowers.append(subSum / Double(subBlock))
                subFill = 0
                subSum = 0
            }
        }
    }

    /// Integrated loudness (LUFS) of everything fed so far.
    public var integratedLUFS: Double {
        guard subPowers.count >= 4 else {
            let all = subPowers.isEmpty ? 0 : subPowers.reduce(0, +) / Double(subPowers.count)
            return all > 0 ? -0.691 + 10 * log10(all) : -.infinity
        }
        // 400 ms blocks with 75 % overlap = 4 consecutive sub-blocks.
        var blocks: [Double] = []
        for i in 0...(subPowers.count - 4) { blocks.append((subPowers[i] + subPowers[i + 1] + subPowers[i + 2] + subPowers[i + 3]) / 4) }
        func loudness(_ p: Double) -> Double { p > 0 ? -0.691 + 10 * log10(p) : -.infinity }
        let absolute = blocks.filter { loudness($0) > -70 }
        guard !absolute.isEmpty else { return -.infinity }
        let gate = loudness(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { loudness($0) > gate }
        return gated.isEmpty ? -.infinity : loudness(gated.reduce(0, +) / Double(gated.count))
    }

    public var peakDB: Double { peak > 0 ? 20 * log10(Double(peak)) : -.infinity }
}

/// What the export loudness check found and what it suggests.
public struct LoudnessVerdict: Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        case fine
        /// Lower everything by this many dB.
        case lower(Double)
        /// Too quiet: level (normalize) dialogue that isn't leveled yet.
        case levelDialogue
        /// Too quiet but already leveled — nothing safe to do.
        case quietButLeveled
    }

    public static let target = -14.0
    public var lufs: Double
    public var peakDB: Double
    public var action: Action

    public init(lufs: Double, peakDB: Double, unleveledDialogue: Bool) {
        self.lufs = lufs
        self.peakDB = peakDB
        if !lufs.isFinite {
            action = .fine
        } else if lufs > Self.target + 1 || peakDB > -0.5 {
            action = .lower(max(lufs - Self.target, peakDB + 1, 0.5))
        } else if lufs < Self.target - 2 {
            action = unleveledDialogue ? .levelDialogue : .quietButLeveled
        } else {
            action = .fine
        }
    }

    public var summary: String {
        let measured = lufs.isFinite ? String(format: "%.1f LUFS, peaks at %.1f dB", lufs, peakDB) : "silent"
        switch action {
        case .fine: return "Mix is \(measured) — right for YouTube (−14 LUFS)."
        case .lower(let db): return "Mix is \(measured) — louder than YouTube plays (−14 LUFS), so it would be turned down and may clip. Lower it by \(String(format: "%.1f", db)) dB?"
        case .levelDialogue: return "Mix is \(measured) — quieter than YouTube's −14 LUFS. Level the dialogue that isn't leveled yet?"
        case .quietButLeveled: return "Mix is \(measured) — a little quiet, but the dialogue is already leveled; YouTube will play it as is."
        }
    }
}

extension LoudnessVerdict {
    /// Talking clips (anything on an audio track that isn't music or a sound effect) not leveled yet.
    public static func hasUnleveledDialogue(_ timeline: Timeline) -> Bool {
        timeline.tracks.filter { $0.kind == .audio && !$0.isMuted }.flatMap(\.clips).contains(where: isUnleveledDialogue)
    }

    static func isUnleveledDialogue(_ clip: TimelineClip) -> Bool {
        clip.isEnabled && clip.content.assetID != nil && clip.role != .music && clip.role != .soundEffect && !clip.audio.normalize && !clip.audio.isMuted
    }

    /// Makes the change the verdict suggests (only after you said yes). Returns clips changed.
    @discardableResult
    public func apply(to timeline: inout Timeline) -> Int {
        var changed = 0
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
            for ci in timeline.tracks[ti].clips.indices {
                let clip = timeline.tracks[ti].clips[ci]
                switch action {
                case .lower(let db):
                    guard clip.content.assetID != nil || clip.content.compoundID != nil else { continue }
                    timeline.tracks[ti].clips[ci].audio.gainDB -= db
                    changed += 1
                case .levelDialogue:
                    guard Self.isUnleveledDialogue(clip) else { continue }
                    timeline.tracks[ti].clips[ci].audio.normalize = true
                    changed += 1
                case .fine, .quietButLeveled:
                    return 0
                }
            }
        }
        if changed > 0 { timeline.modifiedAt = Date() }
        return changed
    }
}
