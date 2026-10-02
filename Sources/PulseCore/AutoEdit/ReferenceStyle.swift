import Foundation

// MARK: - What was measured

/// Text Vision read on one sampled frame of a reference video.
public struct TextSample: Codable, Hashable, Sendable {
    public var time: Seconds
    public var boxes: [TextBox]

    public init(time: Seconds, boxes: [TextBox]) {
        self.time = time
        self.boxes = boxes
    }
}

/// One line of on-screen text (normalized, top-left origin).
public struct TextBox: Codable, Hashable, Sendable {
    public var rect: NormRect
    public var text: String

    public init(rect: NormRect, text: String) {
        self.rect = rect
        self.text = text
    }
}

/// How a reference video is edited, measured from the video itself: pacing, zooms, captions,
/// music, sound effects, pop-ups, transitions and length. Saved so it can be reused on any VOD.
public struct ReferenceStyle: Codable, Hashable, Identifiable, Sendable {
    public struct CaptionLook: Codable, Hashable, Sendable {
        /// Share of the video with captions on screen (0…1).
        public var coverage: Double
        /// Vertical centre of the caption lines (0 = top, 1 = bottom).
        public var positionY: Double
        /// Height of one caption line as a fraction of the frame height.
        public var lineHeight: Double
        /// Typical number of words on screen at once.
        public var wordsOnScreen: Double
        public var uppercase: Bool

        public init(coverage: Double, positionY: Double, lineHeight: Double, wordsOnScreen: Double, uppercase: Bool) {
            self.coverage = coverage
            self.positionY = positionY
            self.lineHeight = lineHeight
            self.wordsOnScreen = wordsOnScreen
            self.uppercase = uppercase
        }
    }

    public enum Pace: String, Codable, Sendable {
        case calm, steady, fast, frantic

        public var displayName: String { rawValue.capitalized }
    }

    public var id: UUID
    /// Shown in the app ("MrBeast-style edit.mp4" → "MrBeast-style edit").
    public var name: String
    public var measuredAt: Date
    public var duration: Seconds
    /// Width ÷ height of the reference.
    public var aspect: Double
    /// Hard cuts (scene changes) per minute.
    public var cutsPerMinute: Double
    public var averageShotLength: Seconds
    /// Punch-in zooms per minute (the face suddenly gets bigger without a cut).
    public var zoomsPerMinute: Double
    /// Typical punch-in strength (1.2 = 20 % closer).
    public var zoomScale: Double
    public var captions: CaptionLook?
    /// Big short-lived text (memes, call-outs, titles) per minute, away from the captions.
    public var popupsPerMinute: Double
    public var wordsPerMinute: Double?
    /// Share of the talking time left as pauses (low = tight jump cuts).
    public var pauseRatio: Double?
    /// How much of the non-speech time has music under it (0…1).
    public var musicBed: Double
    /// Sudden sound hits (effects, whooshes) per minute.
    public var effectsPerMinute: Double
    /// Dips to black between sections per minute.
    public var fadesPerMinute: Double
    /// Cuts come faster in the first 20 seconds than in the rest — a hook.
    public var opensFast: Bool

    public init(id: UUID = UUID(), name: String, measuredAt: Date = Date(), duration: Seconds, aspect: Double, cutsPerMinute: Double,
                averageShotLength: Seconds, zoomsPerMinute: Double, zoomScale: Double, captions: CaptionLook?, popupsPerMinute: Double,
                wordsPerMinute: Double?, pauseRatio: Double?, musicBed: Double, effectsPerMinute: Double, fadesPerMinute: Double,
                opensFast: Bool) {
        self.id = id
        self.name = name
        self.measuredAt = measuredAt
        self.duration = duration
        self.aspect = aspect
        self.cutsPerMinute = cutsPerMinute
        self.averageShotLength = averageShotLength
        self.zoomsPerMinute = zoomsPerMinute
        self.zoomScale = zoomScale
        self.captions = captions
        self.popupsPerMinute = popupsPerMinute
        self.wordsPerMinute = wordsPerMinute
        self.pauseRatio = pauseRatio
        self.musicBed = musicBed
        self.effectsPerMinute = effectsPerMinute
        self.fadesPerMinute = fadesPerMinute
        self.opensFast = opensFast
    }

    public var isVertical: Bool { aspect < 0.9 }
    public var isShortForm: Bool { duration <= 180 }
    public var hasCaptions: Bool { (captions?.coverage ?? 0) >= 0.15 }
    public var hasZooms: Bool { zoomsPerMinute >= 0.3 }
    public var hasMusic: Bool { musicBed >= 0.35 }
    public var hasSoundEffects: Bool { effectsPerMinute >= 0.6 }
    public var hasPopups: Bool { popupsPerMinute >= 0.25 }
    public var hasTransitions: Bool { fadesPerMinute >= 0.2 }

    public var pace: Pace {
        let activity = cutsPerMinute + zoomsPerMinute * 0.8 + effectsPerMinute * 0.3
        if activity < 4 { return .calm }
        if activity < 10 { return .steady }
        if activity < 20 { return .fast }
        return .frantic
    }

    /// One line per ingredient, for the "style fingerprint" card.
    public struct Trait: Hashable, Sendable {
        public var symbol: String
        public var title: String
        public var detail: String
    }

    public var traits: [Trait] {
        var out: [Trait] = []
        let shot = averageShotLength < 60 ? "a new shot every \(Self.seconds(averageShotLength))" : "long unbroken shots"
        out.append(Trait(symbol: "metronome", title: "\(pace.displayName) pace", detail: String(format: "%.0f cuts a minute — %@", cutsPerMinute, shot)))
        if let pauses = pauseRatio {
            out.append(Trait(symbol: "scissors", title: pauses < 0.06 ? "Tight jump cuts" : (pauses < 0.13 ? "Trimmed pauses" : "Natural pauses kept"),
                             detail: wordsPerMinute.map { String(format: "%.0f words a minute", $0) } ?? "Pauses between sentences"))
        }
        out.append(hasZooms
            ? Trait(symbol: "plus.magnifyingglass", title: "Punch-in zooms",
                    detail: String(format: "About every %@, ~%.0f%% closer", Self.seconds(60 / max(zoomsPerMinute, 0.01)), (zoomScale - 1) * 100))
            : Trait(symbol: "minus.magnifyingglass", title: "Few or no zooms", detail: "The framing mostly stays put"))
        if let c = captions, hasCaptions {
            let position = c.positionY < 0.4 ? "high" : (c.positionY < 0.7 ? "mid-screen" : "low")
            let words = c.wordsOnScreen < 1.6 ? "one word at a time" : String(format: "~%.0f words at a time", c.wordsOnScreen)
            out.append(Trait(symbol: "captions.bubble", title: "\(c.lineHeight >= 0.055 ? "Big" : "Small")\(c.uppercase ? " ALL-CAPS" : "") captions",
                             detail: "\(position.capitalizedFirst), \(words)"))
        } else {
            out.append(Trait(symbol: "captions.bubble", title: "No burned-in captions", detail: "Viewers rely on the audio"))
        }
        out.append(Trait(symbol: "music.note", title: hasMusic ? "Music under it" : (musicBed >= 0.15 ? "Music in places" : "No music bed"),
                         detail: String(format: "Music in about %.0f%% of the gaps", musicBed * 100)))
        out.append(Trait(symbol: "speaker.wave.3", title: hasSoundEffects ? "Sound effects" : "Few sound effects",
                         detail: effectsPerMinute >= 0.2 ? "About every \(Self.seconds(60 / effectsPerMinute))" : "Rarely, if ever"))
        out.append(Trait(symbol: "text.bubble", title: hasPopups ? "Text & meme pop-ups" : "Few pop-ups",
                         detail: popupsPerMinute >= 0.1 ? "About every \(Self.seconds(60 / popupsPerMinute))" : "Hardly any on-screen extras"))
        if hasTransitions { out.append(Trait(symbol: "circle.lefthalf.filled", title: "Fades between sections", detail: "Dips to black to change topic")) }
        out.append(Trait(symbol: "bolt", title: opensFast ? "Fast hook" : "Eases in", detail: opensFast ? "The first 20 s cut faster than the rest" : "No rushed opening"))
        out.append(Trait(symbol: isVertical ? "rectangle.portrait" : "rectangle", title: "\(Timecode.short(duration)) long",
                         detail: isVertical ? "Vertical (shorts format)" : "Landscape"))
        return out
    }

    public var summary: String {
        var parts = ["\(pace.displayName.lowercased()) pace"]
        if hasZooms { parts.append("zooms") }
        if hasCaptions { parts.append("captions") }
        if hasMusic { parts.append("music") }
        if hasSoundEffects { parts.append("sound effects") }
        if hasPopups { parts.append("pop-ups") }
        return parts.joined(separator: ", ").capitalizedFirst
    }

    static func seconds(_ s: Seconds) -> String {
        s < 90 ? "\(Int(s.rounded())) s" : "\(Int((s / 60).rounded())) min"
    }
}

// MARK: - Measuring

public enum ReferenceStyleAnalyzer {
    /// Turns the reference's analysis (audio, transcript, frames, faces) and the text read off its
    /// frames into a style.
    public static func measure(name: String, analysis: MediaAnalysis, text: [TextSample], frameSize: Size2) -> ReferenceStyle {
        let duration = max(analysis.duration, 1)
        let minutes = duration / 60
        let cuts = analysis.visual?.sceneCuts ?? []
        let zooms = analysis.visual.map(zoomEvents) ?? []
        let speech = analysis.transcript.flatMap { speechStats($0.words, duration: duration) }
        let effects = analysis.audio.map { effectHits($0, words: analysis.transcript?.words ?? [], cuts: cuts) } ?? []
        let captionStats = captions(in: text)
        let firstCuts = cuts.filter { $0 < 20 }.count
        let opensFast = duration > 40 && Double(firstCuts) / min(20, duration) * 60 > (Double(cuts.count) / minutes) * 1.25 && firstCuts >= 2
        let scales = zooms.map(\.scale).sorted()
        return ReferenceStyle(name: name, duration: duration,
                              aspect: frameSize.height > 0 ? frameSize.width / frameSize.height : 16.0 / 9.0,
                              cutsPerMinute: Double(cuts.count) / minutes,
                              averageShotLength: duration / Double(cuts.count + 1),
                              zoomsPerMinute: Double(zooms.count) / minutes,
                              zoomScale: scales.isEmpty ? 1.16 : scales[scales.count / 2],
                              captions: captionStats.look,
                              popupsPerMinute: Double(captionStats.popups) / minutes,
                              wordsPerMinute: speech?.wordsPerMinute, pauseRatio: speech?.pauseRatio,
                              musicBed: analysis.audio.map { musicBed($0, words: analysis.transcript?.words ?? []) } ?? 0,
                              effectsPerMinute: Double(effects.count) / minutes,
                              fadesPerMinute: Double(analysis.visual.map(fades) ?? 0) / minutes,
                              opensFast: opensFast)
    }

    /// Punch-ins: the main face gets suddenly bigger between neighbouring samples with no cut between them.
    static func zoomEvents(_ visual: VisualFeatureSeries) -> [(time: Seconds, scale: Double)] {
        let samples = visual.faces.filter { !$0.boxes.isEmpty }.sorted { $0.time < $1.time }
        var events: [(time: Seconds, scale: Double)] = []
        for (a, b) in zip(samples, samples.dropFirst()) {
            guard b.time - a.time <= max(1.6, visual.hop * 2.5),
                  !visual.sceneCuts.contains(where: { $0 > a.time + 0.01 && $0 <= b.time + 0.01 }),
                  let fa = a.boxes.max(by: { $0.area < $1.area }), let fb = b.boxes.max(by: { $0.area < $1.area }),
                  fa.area > 0 else { continue }
            let scale = sqrt(fb.area / fa.area)
            let moved = hypot(fb.center.x - fa.center.x, fb.center.y - fa.center.y)
            guard scale >= 1.12, moved < 0.25 else { continue }
            if let last = events.last, b.time - last.time < 1.5 { continue }
            events.append((b.time, scale))
        }
        return events
    }

    static func speechStats(_ words: [TranscriptWord], duration: Seconds) -> (wordsPerMinute: Double, pauseRatio: Double)? {
        let sorted = words.sorted { $0.start < $1.start }
        guard sorted.count >= 20, let first = sorted.first, let last = sorted.last, last.end > first.start else { return nil }
        var paused: Seconds = 0
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let gap = b.start - a.end
            if gap > 0.35 && gap < 5 { paused += gap }
        }
        let span = last.end - first.start
        return (Double(sorted.count) / (duration / 60), paused / span)
    }

    /// Music shows up as level in the gaps between words (a dry voice track drops to the noise floor).
    static func musicBed(_ audio: AudioFeatureSeries, words: [TranscriptWord]) -> Double {
        guard audio.count > 0, audio.hop > 0 else { return 0 }
        let sorted = words.sorted { $0.start < $1.start }
        var gapLevels: [Float] = []
        if sorted.count >= 10 {
            var gaps: [TimeRange] = [TimeRange(start: 0, end: sorted[0].start)]
            for (a, b) in zip(sorted, sorted.dropFirst()) where b.start - a.end > 0.5 {
                gaps.append(TimeRange(start: a.end + 0.1, end: b.start - 0.1))
            }
            gaps.append(TimeRange(start: sorted[sorted.count - 1].end + 0.1, end: audio.duration))
            for gap in gaps where gap.duration > 0.2 {
                var t = gap.start
                while t < gap.end {
                    let i = Int(t / audio.hop)
                    if i >= 0 && i < audio.count { gapLevels.append(audio.rmsDB[i]) }
                    t += audio.hop
                }
            }
        }
        if gapLevels.count >= 20 {
            return Double(gapLevels.filter { $0 > -40 }.count) / Double(gapLevels.count)
        }
        // Hardly any gaps (tightly cut, or no speech): judge by the quietest moments overall.
        var levels: [Float] = []
        for i in 0..<audio.count { levels.append(audio.rmsDB[i]) }
        levels.sort()
        let floor = levels[levels.count / 10]
        return floor > -32 ? 0.8 : (floor > -40 ? 0.4 : 0.05)
    }

    /// Loud onsets that stand far above the rest: effects and whooshes. Spikes inside words only count
    /// when they're huge (a "boom" under a sentence); spikes on cuts count (whoosh transitions).
    static func effectHits(_ audio: AudioFeatureSeries, words: [TranscriptWord], cuts: [Seconds]) -> [Seconds] {
        let n = audio.count
        guard n > 10 else { return [] }
        var flux: [Double] = []
        flux.reserveCapacity(n)
        for i in 0..<n { flux.append(Double(audio.spectralFlux[i])) }
        let mean = flux.reduce(0, +) / Double(n)
        let sd = sqrt(flux.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n))
        guard sd > 1e-9 else { return [] }
        var hits: [Seconds] = []
        for i in 0..<n {
            let z = (flux[i] - mean) / sd
            guard z > 3.5, audio.peakDB[i] > -14 else { continue }
            let t = Double(i) * audio.hop
            let inWord = words.contains { $0.start - 0.05 <= t && t <= $0.end + 0.05 }
            let onCut = cuts.contains { abs($0 - t) < 0.6 }
            guard !inWord || z > 5.5 || onCut else { continue }
            if let last = hits.last, t - last < 0.6 { continue }
            hits.append(t)
        }
        return hits
    }

    /// Short dips to black away from the very start and end.
    static func fades(_ visual: VisualFeatureSeries) -> Int {
        let n = visual.count
        guard n > 6, visual.hop > 0 else { return 0 }
        let edge = Int((2 / visual.hop).rounded(.up))
        let reach = max(1, Int((2 / visual.hop).rounded()))
        let level = visual.brightness.values
        var count = 0
        var i = edge
        while i < n - edge {
            if level[i] < 0.05 {
                let before = level[max(0, i - reach)..<i].contains { $0 > 0.12 }
                var j = i
                while j < n && level[j] < 0.05 { j += 1 }
                let after = j < n && level[j..<min(n, j + reach)].contains { $0 > 0.12 }
                if before && after && Double(j - i) * visual.hop <= 2 { count += 1 }
                i = j
            }
            i += 1
        }
        return count
    }

    /// Captions: text that changes, low-to-mid frame, not a persistent overlay (channel names,
    /// watermarks, a game HUD). Pop-ups: big or high short-lived text that isn't the captions.
    static func captions(in samples: [TextSample]) -> (look: ReferenceStyle.CaptionLook?, popups: Int) {
        guard !samples.isEmpty else { return (nil, 0) }
        let sorted = samples.sorted { $0.time < $1.time }
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        var seen: [String: Int] = [:]
        for sample in sorted {
            for k in Set(sample.boxes.map { key($0.text) }) where k.count >= 2 { seen[k, default: 0] += 1 }
        }
        let persistentLimit = max(3, Int(Double(sorted.count) * 0.3))
        let persistent = Set(seen.filter { $0.value >= persistentLimit }.keys)
        let live = sorted.map { sample in
            TextSample(time: sample.time, boxes: sample.boxes.filter { box in
                let k = key(box.text)
                return k.count >= 2 && !persistent.contains(k)
            })
        }

        func isCaptionBand(_ b: TextBox) -> Bool { b.rect.center.y >= 0.35 && b.rect.center.y <= 0.95 && b.rect.height <= 0.2 }
        var captionTexts: [String] = []
        var positions: [Double] = []
        var heights: [Double] = []
        var wordCounts: [Double] = []
        var letters = 0, upper = 0
        for sample in live {
            let lines = sample.boxes.filter(isCaptionBand)
            guard !lines.isEmpty else { continue }
            let joined = lines.map(\.text).joined(separator: " ")
            captionTexts.append(key(joined))
            positions.append(lines.map(\.rect.center.y).reduce(0, +) / Double(lines.count))
            heights.append(contentsOf: lines.map(\.rect.height))
            wordCounts.append(Double(joined.split(whereSeparator: { $0.isWhitespace }).count))
            for ch in joined where ch.isLetter {
                letters += 1
                if ch.isUppercase { upper += 1 }
            }
        }
        func median(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.sorted()[v.count / 2] }
        var look: ReferenceStyle.CaptionLook?
        // Real captions keep changing; one static line in the same place is a title, not captions.
        if captionTexts.count >= 3, Double(Set(captionTexts).count) >= Double(captionTexts.count) * 0.35 {
            look = ReferenceStyle.CaptionLook(coverage: Double(captionTexts.count) / Double(sorted.count), positionY: median(positions),
                                              lineHeight: median(heights), wordsOnScreen: max(1, median(wordCounts)),
                                              uppercase: letters > 0 && Double(upper) / Double(letters) >= 0.85)
        }

        // Pop-ups: runs of consecutive samples with high or oversized text, up to ~4 s long.
        let captionHeight = look?.lineHeight ?? 0.06
        var popups = 0
        var runStart: Seconds?
        var runEnd: Seconds = 0
        for sample in live {
            let pops = sample.boxes.contains { $0.rect.center.y < 0.35 || $0.rect.height > max(0.1, captionHeight * 1.8) }
            if pops {
                if runStart == nil { runStart = sample.time }
                runEnd = sample.time
            } else if let start = runStart {
                if runEnd - start <= 4 { popups += 1 }
                runStart = nil
            }
        }
        if let start = runStart, runEnd - start <= 4 { popups += 1 }
        return (look, popups)
    }
}

// MARK: - Questions and the edit

/// The answers to "what do you want?" before PULSE edits like the reference.
public struct ReferenceAnswers: Codable, Hashable, Sendable {
    public enum Length: String, Codable, CaseIterable, Sendable {
        case likeReference, youtube, medium, short, shorts
    }

    public enum Focus: String, Codable, CaseIterable, Sendable {
        case everything, funny, hype, story

        public var displayName: String {
            switch self {
            case .everything: return "A bit of everything"
            case .funny: return "Funniest moments"
            case .hype: return "Hype & big plays"
            case .story: return "Stories & conversation"
            }
        }

        public var tags: [ClipTag] {
            switch self {
            case .everything: return []
            case .funny: return [.funny, .reaction, .fail]
            case .hype: return [.hype, .highEnergy, .rage, .gaming]
            case .story: return [.story, .conversation, .question, .emotional]
            }
        }
    }

    public enum Closeness: String, Codable, CaseIterable, Sendable {
        case closely, loosely

        public var displayName: String { self == .closely ? "Copy it closely" : "Loosely — keep it a bit calmer" }
    }

    public var length: Length
    public var focus: Focus
    public var closeness: Closeness
    public var coldOpen: Bool
    public var copyPacing: Bool
    public var copyZooms: Bool
    public var copyCaptions: Bool
    public var copyMusic: Bool
    public var copySoundEffects: Bool
    public var copyPopups: Bool
    public var copyTransitions: Bool
    /// For `.shorts`: how many.
    public var shortsCount: Int

    public init(length: Length = .likeReference, focus: Focus = .everything, closeness: Closeness = .closely, coldOpen: Bool = true,
                copyPacing: Bool = true, copyZooms: Bool = true, copyCaptions: Bool = true, copyMusic: Bool = true,
                copySoundEffects: Bool = true, copyPopups: Bool = true, copyTransitions: Bool = true, shortsCount: Int = 3) {
        self.length = length
        self.focus = focus
        self.closeness = closeness
        self.coldOpen = coldOpen
        self.copyPacing = copyPacing
        self.copyZooms = copyZooms
        self.copyCaptions = copyCaptions
        self.copyMusic = copyMusic
        self.copySoundEffects = copySoundEffects
        self.copyPopups = copyPopups
        self.copyTransitions = copyTransitions
        self.shortsCount = shortsCount
    }

    /// What PULSE suggests before you change anything.
    public static func recommended(for style: ReferenceStyle) -> ReferenceAnswers {
        var answers = ReferenceAnswers()
        answers.length = style.isShortForm && style.isVertical ? .shorts : .likeReference
        answers.coldOpen = style.opensFast || style.duration > 180
        return answers
    }
}

/// The reference's style, turned into concrete editing settings.
public struct StyleTuning: Codable, Hashable, Sendable {
    public var name: String
    public var silence: SilencePreset
    /// Seconds between reaction zooms.
    public var zoomSpacing: Seconds
    public var zoomScale: Double
    /// Punch in/out on sentence starts too, like a fast jump-cut edit.
    public var rhythmZooms: Bool
    public var rhythmSpacing: Seconds
    /// nil = PULSE's normal caption look.
    public var captionLook: ReferenceStyle.CaptionLook?
    public var memeSpacing: Seconds
    public var whooshSpacing: Seconds
    public var fades: Bool
    /// Moments with these tags are favoured.
    public var focusTags: [ClipTag]

    public init(name: String, silence: SilencePreset = .balanced, zoomSpacing: Seconds = 22, zoomScale: Double = 1.16, rhythmZooms: Bool = false,
                rhythmSpacing: Seconds = 8, captionLook: ReferenceStyle.CaptionLook? = nil, memeSpacing: Seconds = 90,
                whooshSpacing: Seconds = 60, fades: Bool = false, focusTags: [ClipTag] = []) {
        self.name = name
        self.silence = silence
        self.zoomSpacing = zoomSpacing
        self.zoomScale = zoomScale
        self.rhythmZooms = rhythmZooms
        self.rhythmSpacing = rhythmSpacing
        self.captionLook = captionLook
        self.memeSpacing = memeSpacing
        self.whooshSpacing = whooshSpacing
        self.fades = fades
        self.focusTags = focusTags
    }
}

extension ReferenceStyle {
    /// Edit My VOD settings that reproduce this style, shaped by the answers.
    public func longFormOptions(_ answers: ReferenceAnswers) -> LongFormOptions {
        let closely = answers.closeness == .closely
        func blend(_ measured: Double, _ normal: Double) -> Double { closely ? measured : (measured + normal) / 2 }

        var options = LongFormOptions()
        switch answers.length {
        case .likeReference:
            let d = max(60, duration)
            options.minimumLength = d * 0.8
            options.maximumLength = d * 1.2
        case .youtube:
            options.minimumLength = 600
            options.maximumLength = 1200
        case .medium:
            options.minimumLength = 300
            options.maximumLength = 480
        case .short, .shorts:
            options.minimumLength = 90
            options.maximumLength = 180
        }
        options.coldOpen = answers.coldOpen
        options.cutDeadAir = true

        var tuning = StyleTuning(name: name)
        tuning.focusTags = answers.focus.tags

        if answers.copyPacing {
            tuning.silence = silencePreset(loosely: !closely)
        }
        if answers.copyZooms {
            options.zooms = closely ? hasZooms : zoomsPerMinute >= 0.15
            tuning.zoomSpacing = blend(60 / max(zoomsPerMinute, 0.01), 22).clamped(4, 90)
            tuning.zoomScale = blend(zoomScale, 1.16).clamped(1.06, 1.45)
            tuning.rhythmZooms = closely ? (cutsPerMinute >= 8 || zoomsPerMinute >= 4) : cutsPerMinute >= 14
            tuning.rhythmSpacing = blend(averageShotLength, 8).clamped(2.5, 15)
            if tuning.rhythmZooms { options.zooms = true }
        }
        if answers.copyCaptions {
            options.captions = closely ? hasCaptions : true
            tuning.captionLook = hasCaptions ? captions : nil
        }
        if answers.copyMusic {
            options.music = closely ? hasMusic : musicBed >= 0.2
        }
        if answers.copySoundEffects {
            options.soundEffects = closely ? hasSoundEffects : effectsPerMinute >= 0.3
            tuning.whooshSpacing = blend(120 / max(effectsPerMinute, 0.01), 60).clamped(15, 300)
        }
        if answers.copyPopups {
            options.memes = closely ? hasPopups : popupsPerMinute >= 0.12
            tuning.memeSpacing = blend(60 / max(popupsPerMinute, 0.01), 90).clamped(20, 300)
        }
        if answers.copyTransitions {
            tuning.fades = hasTransitions
        }
        switch pace {
        case .calm: options.restraint = .subtle
        case .steady: options.restraint = .balanced
        case .fast, .frantic: options.restraint = closely ? .energetic : .balanced
        }
        options.style = tuning
        return options
    }

    /// Short-form settings in this style (for "make shorts like this").
    public func shortOptions(_ answers: ReferenceAnswers, base: ShortBuildOptions, canvasHeight: Double = 1920) -> ShortBuildOptions {
        let closely = answers.closeness == .closely
        var options = base
        if answers.copyPacing { options.silence = silencePreset(loosely: !closely) }
        if answers.copyCaptions {
            options.captionsEnabled = closely ? hasCaptions : true
            if let look = captions, hasCaptions {
                options.captionStyle = look.captionStyle(canvasHeight: canvasHeight, landscape: false)
            }
        }
        if answers.copyZooms {
            options.punchIns = closely ? (hasZooms || cutsPerMinute >= 8) : zoomsPerMinute >= 0.15
            let spacing = 60 / max(zoomsPerMinute, 0.01)
            options.punchInSettings.minimumSpacing = (closely ? spacing : (spacing + options.punchInSettings.minimumSpacing) / 2).clamped(2, 30)
            let scale = closely ? zoomScale : (zoomScale + options.punchInSettings.reactionZoom) / 2
            options.punchInSettings.reactionZoom = scale.clamped(1.06, 1.45)
            options.punchInSettings.punchlineZoom = (1 + (scale - 1) * 0.7).clamped(1.04, 1.35)
        }
        if answers.copySoundEffects { options.soundEffects = closely ? hasSoundEffects : effectsPerMinute >= 0.3 }
        return options
    }

    /// Music for shorts in this style.
    public func shortWantsMusic(_ answers: ReferenceAnswers, default fallback: Bool) -> Bool {
        guard answers.copyMusic else { return fallback }
        return answers.closeness == .closely ? hasMusic : musicBed >= 0.2
    }

    func silencePreset(loosely: Bool) -> SilencePreset {
        let measured: SilencePreset
        if let pauses = pauseRatio {
            measured = pauses < 0.06 || cutsPerMinute > 14 ? .aggressive : (pauses < 0.13 ? .balanced : .conservative)
        } else {
            measured = cutsPerMinute > 12 ? .aggressive : (cutsPerMinute > 5 ? .balanced : .conservative)
        }
        return loosely && measured != .balanced ? .balanced : measured
    }
}

extension ReferenceStyle.CaptionLook {
    /// A caption style that looks like the reference's: nearest preset, then its size, position,
    /// case and words-per-screen.
    public func captionStyle(canvasHeight: Double, landscape: Bool) -> CaptionStyle {
        var style: CaptionStyle
        if wordsOnScreen < 1.6 {
            style = .highEnergy
        } else if uppercase {
            style = .bold
        } else if landscape && positionY > 0.75 && lineHeight < 0.06 {
            style = .youtube
        } else {
            style = .tiktok
        }
        style.presetName = "Matched"
        style.positionY = positionY.clamped(0.12, 0.9)
        // Vision's line box is roughly the font size; caption sizes are in canvas pixels.
        style.text.fontSize = (lineHeight * canvasHeight * 0.85).clamped(28, 150)
        style.text.textCase = uppercase ? .uppercase : .asTyped
        style.maxWordsPerPage = Int(wordsOnScreen.rounded()).clamped(1, 10)
        if style.maxWordsPerPage == 1 {
            style.displayMode = .wordByWord
            style.maxLines = 1
        } else if style.displayMode == .wordByWord {
            style.displayMode = .phrase
        }
        style.maxCharsPerLine = max(10, min(42, style.maxWordsPerPage * 6))
        return style
    }
}
