import Foundation

/// Options for "Edit My VOD": turn a long stream into a 10–20 minute YouTube video.
public struct LongFormOptions: Codable, Hashable, Sendable {
    /// Target length range; the edit lands inside it when the recording has enough good material.
    public var minimumLength: Seconds
    public var maximumLength: Seconds
    public var coldOpen: Bool
    public var cutDeadAir: Bool
    public var zooms: Bool
    public var captions: Bool
    public var memes: Bool
    public var soundEffects: Bool
    public var music: Bool
    /// "Don't over-edit": caps on zooms, memes and effects per minute.
    public var restraint: Restraint
    /// Settings measured from a reference video ("edit it like this one"); nil = PULSE's own style.
    public var style: StyleTuning?
    /// Editor finishing passes: boring-stretch trims, sliver removal, clean audio cuts, hidden jump cuts,
    /// chapter transitions, a gentle grade and music drops on punchlines.
    public var polish = true
    /// A 10-second end screen with room for YouTube's end-screen cards.
    public var endScreen = true
    /// Opt-in extras (asked before every edit; nothing here is on unless you said yes).
    public var extras = EditExtras()

    /// Seconds between reaction zooms / meme pop-ups / transition whooshes.
    public var zoomSpacing: Seconds { style?.zoomSpacing ?? restraint.zoomSpacing }
    public var memeSpacing: Seconds { style?.memeSpacing ?? restraint.memeSpacing }
    public var whooshSpacing: Seconds { style?.whooshSpacing ?? restraint.whooshSpacing }
    public var silencePreset: SilencePreset { style?.silence ?? .balanced }

    public enum Restraint: String, Codable, CaseIterable, Sendable {
        case subtle, balanced, energetic

        public var displayName: String { rawValue.capitalized }
        /// Seconds between zooms.
        var zoomSpacing: Seconds { self == .subtle ? 40 : (self == .balanced ? 22 : 12) }
        /// Seconds between meme pop-ups.
        var memeSpacing: Seconds { self == .subtle ? 180 : (self == .balanced ? 90 : 45) }
        /// Seconds between transition whooshes.
        var whooshSpacing: Seconds { self == .subtle ? 120 : (self == .balanced ? 60 : 30) }
    }

    public init(minimumLength: Seconds = 600, maximumLength: Seconds = 1200, coldOpen: Bool = true, cutDeadAir: Bool = true,
                zooms: Bool = true, captions: Bool = true, memes: Bool = true, soundEffects: Bool = true, music: Bool = true,
                restraint: Restraint = .balanced, style: StyleTuning? = nil) {
        self.minimumLength = minimumLength
        self.maximumLength = max(maximumLength, minimumLength)
        self.coldOpen = coldOpen
        self.cutDeadAir = cutDeadAir
        self.zooms = zooms
        self.captions = captions
        self.memes = memes
        self.soundEffects = soundEffects
        self.music = music
        self.restraint = restraint
        self.style = style
    }

    /// What the edit aims for, given how long the recording is.
    public func targetLength(forSource duration: Seconds) -> Seconds {
        if duration <= minimumLength * 1.25 { return duration * 0.6 }
        return (duration * 0.15).clamped(minimumLength, maximumLength)
    }
}

/// A kept stretch of the recording in the edit, in source time.
public struct LongFormSegment: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var range: TimeRange
    public var payoff: Seconds
    public var potential: Int
    public var title: String
    public var tags: [ClipTag]
    public var scores: ClipScores

    public init(id: UUID = UUID(), range: TimeRange, payoff: Seconds, potential: Int, title: String, tags: [ClipTag], scores: ClipScores = ClipScores()) {
        self.id = id
        self.range = range
        self.payoff = payoff
        self.potential = potential
        self.title = title
        self.tags = tags
        self.scores = scores
    }
}

/// Every moment Edit My VOD considered, with the ones it would keep switched on — for the storyboard.
public struct LongFormPlan: Sendable {
    public var moments: [LongFormSegment]
    public var selected: Set<UUID>
    public var target: Seconds
    /// The suggested hook (the strongest selected moment).
    public var hook: UUID?

    /// Kept length if built now (overlaps counted once, before dead air is cut).
    public func keptLength(_ selection: Set<UUID>? = nil) -> Seconds {
        let ids = selection ?? selected
        return LongFormEditor.mergedLength(moments.filter { ids.contains($0.id) })
    }
}

/// Sounds the editor may place (already imported into the project). Keys: "whoosh", "boom", "impact",
/// "rimshot", "sad trombone", "record scratch", "ding", "applause"… matched by name.
public struct LongFormSounds: Sendable {
    public var effects: [MediaAsset]

    public init(effects: [MediaAsset] = []) {
        self.effects = effects
    }

    func effect(_ keywords: [String]) -> MediaAsset? {
        for k in keywords {
            if let match = effects.first(where: { $0.name.lowercased().contains(k) || $0.tags.contains(k) }) { return match }
        }
        return nil
    }
}

public struct LongFormResult: Sendable {
    public var timeline: Timeline
    public var segments: [LongFormSegment]
    public var report: String
    /// Where music beds go (one per "chapter"); the app composes a bed of each length.
    public var musicChapters: [TimeRange]
    /// Timeline times of the biggest punchlines — the music drops out there (see `addMusic`).
    public var musicDrops: [Seconds] = []
    /// The automatic edit check (fixed + open issues).
    public var checks = EditCheckReport()
    /// Where B-roll cutaways would go (only when the B-roll extra is on; the app downloads and places them).
    public var brollMoments: [BrollPlacer.Moment] = []
}

/// Builds a YouTube-style edit from a long recording: cuts the dead time, keeps the funniest and most
/// high-energy moments with enough context to follow, opens with a hook, and adds restrained zooms,
/// captions, meme pop-ups, sound effects and music. Everything is a normal, editable clip.
public enum LongFormEditor {
    /// Picks the moments to keep (source time, chronological).
    public static func selectSegments(analysis: MediaAnalysis, options: LongFormOptions, taste: TasteProfile = TasteProfile()) -> [LongFormSegment] {
        let plan = planMoments(analysis: analysis, options: options, taste: taste)
        return merge(plan.moments.filter { plan.selected.contains($0.id) }, gap: 8)
    }

    /// Every candidate moment (about 1.6× more than needed, so there are alternatives to swap in) and the
    /// ones Edit My VOD would keep.
    public static func planMoments(analysis: MediaAnalysis, options: LongFormOptions, taste: TasteProfile = TasteProfile()) -> LongFormPlan {
        let input = ClipGenerationInput(analysis: analysis)
        let target = options.targetLength(forSource: analysis.duration)
        let needed = max(8, Int(target / 25))
        let settings = ClipGenerationSettings(targetDuration: 45, aggressiveness: 1, minimumPotential: 0,
                                              maxCandidates: Int(Double(needed) * 1.6))
        let generator = ClipGenerator(input: input, settings: settings)
        var candidates = generator.generate().applyingTaste(taste)
        // "Focus on the funny bits": favour the moments the answers asked for.
        if let focus = options.style?.focusTags, !focus.isEmpty {
            for i in candidates.indices {
                let hit = candidates[i].tags.contains { focus.contains($0) }
                candidates[i].potential = (candidates[i].potential + (hit ? 12 : -6)).clamped(0, 100)
            }
        }
        candidates.sort { $0.potential > $1.potential }
        guard !candidates.isEmpty else {
            // Nothing stood out (or no audio): keep the whole thing.
            let whole = LongFormSegment(range: TimeRange(start: 0, end: analysis.duration), payoff: analysis.duration / 2, potential: 30, title: "", tags: [])
            return LongFormPlan(moments: [whole], selected: [whole.id], target: target, hook: nil)
        }
        let moments = candidates.map {
            LongFormSegment(range: $0.range, payoff: $0.payoffTime, potential: $0.potential, title: $0.title, tags: $0.tags, scores: $0.scores)
        }
        // Dead air comes out later, so pick a bit more than the target.
        let budget = target * (options.cutDeadAir ? 1.12 : 1)
        var chosen: [LongFormSegment] = []
        var total: Seconds = 0
        for m in moments {
            if total >= budget { break }
            // Weak moments only make it in while we're well short of the target.
            if m.potential < 35 && total > target * 0.6 { continue }
            chosen.append(m)
            total = mergedLength(chosen)
        }
        return LongFormPlan(moments: moments.sorted { $0.range.start < $1.range.start }, selected: Set(chosen.map(\.id)),
                            target: target, hook: chosen.max { $0.potential < $1.potential }?.id)
    }

    static func mergedLength(_ segments: [LongFormSegment]) -> Seconds {
        segments.map(\.range).merged().reduce(0) { $0 + $1.duration }
    }

    /// Chronological, with overlapping or nearly touching stretches joined (a short gap is kept as context).
    static func merge(_ segments: [LongFormSegment], gap: Seconds) -> [LongFormSegment] {
        var result: [LongFormSegment] = []
        for s in segments.sorted(by: { $0.range.start < $1.range.start }) {
            if var last = result.last, s.range.start - last.range.end <= gap {
                last.range = TimeRange(start: last.range.start, end: max(last.range.end, s.range.end))
                if s.potential > last.potential {
                    last.payoff = s.payoff
                    last.title = s.title
                    last.potential = s.potential
                    last.tags = s.tags
                }
                result[result.count - 1] = last
            } else {
                result.append(s)
            }
        }
        return result
    }

    public static func build(asset: MediaAsset, analysis: MediaAnalysis, options: LongFormOptions = LongFormOptions(),
                             sounds: LongFormSounds = LongFormSounds(), taste: TasteProfile = TasteProfile(),
                             segments chosen: [LongFormSegment]? = nil, hookPayoff: Seconds? = nil) -> LongFormResult {
        var segments = chosen.map { LongFormEditor.merge($0, gap: 8) } ?? selectSegments(analysis: analysis, options: options, taste: taste)
        let words = analysis.transcript?.words ?? []
        // Extra: whole sentences only — sections start where a thought starts and end where it ends.
        if options.extras.speakerAware, !words.isEmpty {
            segments = LongFormEditor.merge(SpeakerAware.snapToSentences(segments, words: words, duration: analysis.duration), gap: 0.5)
        }
        let size = asset.metadata.size.isEmpty ? Size2(1920, 1080) : asset.metadata.size
        let landscape = size.aspect >= 1
        let fps = min(asset.metadata.frameRate > 1 ? asset.metadata.frameRate.rounded() : 30, 60)
        var canvas = landscape ? CanvasSettings.landscape1080 : CanvasSettings(width: 1080, height: 1920, frameRate: 30)
        canvas.frameRate = fps
        let editName = options.style.map { "\(asset.name) — like \($0.name)" } ?? "\(asset.name) — YouTube Edit"
        var timeline = Timeline(name: editName, canvas: canvas, tracks: [
            Track(kind: .video, name: "V1 Stream"),
            Track(kind: .text, name: "T1 Titles & Memes"),
            Track(kind: .audio, name: "A1 Dialogue"),
            Track(kind: .audio, name: "A2 Music"),
            Track(kind: .audio, name: "A3 SFX"),
        ])
        timeline.origin = TimelineOrigin(candidateID: nil, assetID: asset.id, sourceRange: TimeRange(start: 0, end: analysis.duration))
        let profile = analysis.profile
        let mainRole: MediaRole = profile == .gameplay || profile == .gameplayWithFacecam ? .gameplay : .main
        let hasAudio = asset.metadata.hasAudio || asset.metadata.audioTrackCount > 0

        func place(_ range: TimeRange, at start: Seconds, name: String) {
            let group = UUID()
            if asset.metadata.hasVideo || asset.kind == .video {
                timeline.tracks[0].clips.append(TimelineClip(name: name, content: .media(assetID: asset.id), start: start, sourceIn: range.start,
                                                             sourceDuration: range.duration, linkGroup: group, role: mainRole, aiGenerated: true))
            }
            if hasAudio {
                var audio = TimelineClip(name: name, content: .media(assetID: asset.id), start: start, sourceIn: range.start,
                                         sourceDuration: range.duration, linkGroup: group, role: .microphone, aiGenerated: true)
                audio.audio.normalize = true
                timeline.tracks[2].clips.append(audio)
            }
        }

        // Cold open: the single best moment, tight around the payoff.
        var cursor: Seconds = 0
        var hookRange: TimeRange?
        var hookMoment: Seconds?
        if options.coldOpen, var best = segments.max(by: { $0.potential < $1.potential }), analysis.duration > 120 {
            // The storyboard can pick a different moment for the hook.
            if let hookPayoff, let picked = segments.first(where: { $0.range.contains(hookPayoff) }) {
                best = picked
                best.payoff = hookPayoff
            }
            let range = hookWindow(around: best.payoff, analysis: analysis)
            hookMoment = best.payoff
            place(range, at: 0, name: "Hook")
            hookRange = range
            cursor = range.duration
            timeline.markers.append(Marker(time: 0, name: "Hook", note: best.title, color: .orange, aiGenerated: true))
            if !best.title.isEmpty {
                var style = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 92, weight: .black, textCase: .uppercase, color: .white,
                                      strokeColor: .black, strokeWidth: 10, shadowOpacity: 0.5, shadowRadius: 8, shadowOffsetY: 6)
                style.letterSpacing = 0.5
                var title = TimelineClip(name: "Hook Title", content: .text(TextElement(text: best.title, style: style, animationIn: .pop,
                                                                                         animationOut: .fadeIn, animationDuration: 0.25, maxWidth: 0.8)),
                                         start: 0.15, sourceDuration: min(2.6, range.duration - 0.2), aiGenerated: true)
                title.transform.positionY = AnimatedDouble(0.2)
                timeline.tracks[1].clips.append(title)
            }
        }
        let hookEnd = cursor

        // The story, in order.
        for (i, segment) in segments.enumerated() {
            place(segment.range, at: cursor, name: segment.title.isEmpty ? "Part \(i + 1)" : segment.title)
            cursor += segment.range.duration
        }

        // Dead air out (the hook is already tight; pauses inside the story get jump-cut).
        var removed: Seconds = 0
        if options.cutDeadAir {
            var cuts: [TimeRange] = []
            // Long stretches where nobody talks and nothing happens (game audio keeps the silence
            // detector from seeing them) — the parts a viewer would skip.
            let signals = options.polish ? EngagementModel.compute(analysis: analysis) : nil
            for s in segments {
                cuts += SilenceDetector.detect(audio: analysis.audio, transcript: analysis.transcript, in: s.range, preset: options.silencePreset)
                if let signals {
                    cuts += EditPolish.deadSpans(in: s.range, words: analysis.transcript?.words ?? [], excitement: signals.excitement, step: signals.step)
                }
            }
            cuts = cuts.merged()
            if let hookRange { cuts.removeAll { $0.overlaps(hookRange) } }
            if !cuts.isEmpty {
                removed = timeline.removeSourceRanges(cuts, assetID: asset.id, reason: .silence, aiGenerated: true)
            }
        }
        // Extra: people talking over each other (needs speaker labels), away from each section's payoff.
        var crosstalk: Seconds = 0
        if options.extras.speakerAware {
            var cuts = segments.flatMap { SpeakerAware.crosstalk(in: $0.range, words: words, protect: $0.payoff) }.merged()
            if let hookRange { cuts.removeAll { $0.overlaps(hookRange) } }
            if !cuts.isEmpty {
                crosstalk = timeline.removeSourceRanges(cuts, assetID: asset.id, reason: .silence, aiGenerated: true)
            }
        }
        // Flash frames and half-breaths left between cuts.
        var slivers = 0
        if options.polish {
            slivers = EditPolish.removeMicroFragments(&timeline, words: analysis.transcript?.words ?? [], after: hookEnd)
        }

        // Where each segment begins now (after the cuts) — chapters, transitions, music.
        let storyClips = timeline.tracks[0].clips.isEmpty ? timeline.tracks[2].clips : timeline.tracks[0].clips
        func timelineStart(of range: TimeRange) -> Seconds? {
            storyClips.filter { $0.start >= hookEnd - 0.01 && $0.sourceRange.overlaps(range) }.map(\.start).min()
        }
        func timelineTime(ofSource t: Seconds) -> Seconds? {
            storyClips.first { $0.start >= hookEnd - 0.01 && $0.sourceRange.contains(t) }.map { $0.timelineTime(atSource: t) }
        }
        let starts = segments.map { timelineStart(of: $0.range) }
        for (i, segment) in segments.enumerated() {
            guard let t = starts[i] else { continue }
            let name = segment.title.isEmpty ? "Part \(i + 1)" : segment.title
            timeline.markers.append(Marker(time: t, name: name, note: "From \(Timecode.short(segment.range.start)) of the stream", color: .blue, aiGenerated: true))
        }

        // Hide the jump cuts: every other cut inside a stretch steps the framing in a little.
        var jumpZooms = 0
        if options.polish, options.zooms, timeline.tracks[0].clips.count > 0 {
            let scale: Double = options.style?.rhythmZooms == true ? 1.08 : (options.restraint == .subtle ? 1 : (options.restraint == .energetic ? 1.08 : 1.06))
            jumpZooms = EditPolish.jumpCutZooms(&timeline, from: hookEnd, segmentStarts: starts.compactMap { $0 }, scale: scale)
        }

        // Captions: easy-to-read subtitles low in frame.
        if options.captions, let transcript = analysis.transcript, !transcript.isEmpty {
            let lo = segments.map(\.range.start).min() ?? 0, hi = segments.map(\.range.end).max() ?? analysis.duration
            let all = TimeRange(start: min(lo, hookRange?.start ?? lo), end: max(hi, hookRange?.end ?? hi))
            let captionStyle = options.style?.captionLook?.captionStyle(canvasHeight: Double(canvas.height), landscape: landscape)
                ?? (landscape ? .youtube : .tiktok)
            var track = CaptionTrack.make(from: transcript, range: all, assetID: asset.id, style: captionStyle, emphasize: false)
            track.colorBySpeaker()
            timeline.captions = track
        }

        // Zooms on the big reactions only (spaced out — no zoom on every line).
        var zooms = 0
        if options.zooms, timeline.tracks[0].clips.count > 0 {
            var moments: [PunchInGenerator.Moment] = []
            for s in segments.sorted(by: { $0.potential > $1.potential }) where s.potential >= 45 {
                if let t = timelineTime(ofSource: s.payoff) { moments.append(.reaction(t)) }
            }
            if let hookRange, let hookMoment, hookRange.contains(hookMoment) {
                moments.append(.reaction(hookMoment - hookRange.start))
            }
            var settings = PunchInSettings()
            settings.reactionZoom = options.style?.zoomScale ?? 1.16
            settings.punchlineZoom = 1 + (settings.reactionZoom - 1) * 0.6
            settings.minimumSpacing = options.zoomSpacing
            settings.holdDuration = 1.8
            settings.rampDuration = 0.25
            // A fast reference punches in and out on the sentences too, not just the big reactions.
            if let style = options.style, style.rhythmZooms, let words = analysis.transcript?.words {
                settings.statementZoom = 1 + (settings.reactionZoom - 1) * 0.5
                settings.minimumSpacing = min(options.zoomSpacing, style.rhythmSpacing)
                settings.holdDuration = min(style.rhythmSpacing * 0.7, 6)
                var last = -Double.infinity
                for (i, word) in words.enumerated() {
                    let startsSentence = i == 0 || word.start - words[i - 1].end > 0.45 || words[i - 1].text.hasSuffix(".")
                        || words[i - 1].text.hasSuffix("?") || words[i - 1].text.hasSuffix("!")
                    guard startsSentence, let t = timelineTime(ofSource: word.start), t - last >= style.rhythmSpacing else { continue }
                    moments.append(.statement(t))
                    last = t
                }
            }
            PunchInGenerator.apply(moments: moments, to: &timeline, trackID: timeline.tracks[0].id, settings: settings)
            zooms = timeline.tracks[0].clips.reduce(0) { $0 + $1.transform.zoom.keyframes.filter(\.aiGenerated).count / 3 }
        }

        // Extra: on gameplay with a facecam, the biggest reactions push in on the face, not the game.
        var facecamZooms = 0
        if options.extras.facecamPunchIns, profile == .gameplayWithFacecam, let webcam = analysis.webcam, timeline.tracks[0].clips.count > 0 {
            var times: [Seconds] = []
            for s in segments.sorted(by: { $0.potential > $1.potential }) where s.potential >= 55 && times.count < 6 {
                guard !Set(s.tags).isDisjoint(with: [.reaction, .funny, .fail, .rage, .hype, .highEnergy]),
                      let t = timelineTime(ofSource: s.payoff), !times.contains(where: { abs($0 - t) < 45 }) else { continue }
                times.append(t)
            }
            facecamZooms = FacecamPunchIn.apply(&timeline, at: times, region: webcam.region)
        }

        // Meme pop-ups + matching sound on the strongest reactions.
        var memes = 0
        if options.memes || options.soundEffects {
            var lastMeme = -Double.infinity
            for s in segments.sorted(by: { $0.potential > $1.potential }) where s.potential >= 55 {
                guard let t = timelineTime(ofSource: s.payoff), t - lastMeme >= options.memeSpacing || lastMeme == -.infinity else { continue }
                if timeline.tracks[1].clips.contains(where: { abs($0.start - t) < options.memeSpacing }) { continue }
                let meme = memeFor(tags: s.tags)
                if options.memes {
                    let style = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 120, weight: .black, textCase: .uppercase, color: meme.color,
                                          strokeColor: .black, strokeWidth: 12, shadowOpacity: 0.6, shadowRadius: 0, shadowOffsetY: 8)
                    var clip = TimelineClip(name: "Meme: \(meme.text)", content: .text(TextElement(text: meme.text, style: style, animationIn: .bounce,
                                                                                                  animationOut: .fadeIn, animationDuration: 0.2, maxWidth: 0.6)),
                                            start: t + 0.1, sourceDuration: 1.3, aiGenerated: true)
                    clip.transform.positionY = AnimatedDouble(0.24)
                    clip.transform.rotation = AnimatedDouble(meme.tilt)
                    if (try? timeline.insert(clip, onTrack: timeline.tracks[1].id, mode: .overwrite)) != nil { memes += 1 }
                }
                if options.soundEffects, let sfx = sounds.effect(meme.sounds) {
                    ShortBuilder.addPayoffHit(sfx, at: t + 0.05, to: &timeline)
                }
                lastMeme = t
                if memes >= 12 { break }
            }
        }

        // Extra: "THEN THIS HAPPENED…" cards where the video jumps ahead in the stream.
        var cards = 0
        if options.extras.titleCards {
            cards = RetentionCards.add(&timeline, segments: segments, starts: starts, hookEnd: hookEnd)
        }

        // A whoosh where the story jumps ahead in the stream (sparingly), and one out of the hook.
        var whooshes = 0
        if options.soundEffects, let whoosh = sounds.effect(["whoosh", "swoosh"]) {
            if hookRange != nil { ShortBuilder.addPayoffHit(whoosh, at: max(0, hookEnd - 0.25), to: &timeline); whooshes += 1 }
            var last = hookEnd
            for i in segments.indices.dropFirst() {
                guard let t = starts[i], t - last >= options.whooshSpacing,
                      segments[i].range.start - segments[i - 1].range.end > 60 else { continue }
                ShortBuilder.addPayoffHit(whoosh, at: max(0, t - 0.2), to: &timeline)
                last = t
                whooshes += 1
            }
        }

        // Dips to black between sections, when the reference uses them.
        var fades = 0
        if options.style?.fades == true {
            for i in segments.indices.dropFirst() {
                guard let t = starts[i], let ci = timeline.tracks[0].clips.firstIndex(where: { abs($0.timelineRange.end - t) < 0.05 }) else { continue }
                timeline.tracks[0].clips[ci].transitionOut = ClipTransition(kind: .fadeToBlack, duration: 0.3, aiGenerated: true)
                if let next = timeline.tracks[0].clips.firstIndex(where: { abs($0.start - t) < 0.05 }) {
                    timeline.tracks[0].clips[next].transitionIn = ClipTransition(kind: .fadeToBlack, duration: 0.3, aiGenerated: true)
                }
                fades += 1
            }
        }

        // Chapter changes (a big jump in the stream) get a quick zoom-through instead of a hard cut.
        var transitions = 0
        if options.polish, options.style?.fades != true, options.restraint != .subtle {
            for i in segments.indices.dropFirst() {
                guard let t = starts[i], segments[i].range.start - segments[i - 1].range.end > 60,
                      let ci = timeline.tracks[0].clips.firstIndex(where: { abs($0.start - t) < 0.05 }) else { continue }
                timeline.tracks[0].clips[ci].transitionIn = ClipTransition(kind: .zoomIn, duration: 0.3, aiGenerated: true)
                transitions += 1
            }
        }

        if options.polish { EditPolish.grade(&timeline) }

        // Ending: an end screen for YouTube's cards, or a soft fade.
        if options.endScreen && landscape && analysis.duration > 120 {
            EditPolish.addEndScreen(&timeline)
        } else if let last = timeline.tracks[0].clips.indices.last {
            timeline.tracks[0].clips[last].transitionOut = ClipTransition(kind: .fadeToBlack, duration: 0.6, aiGenerated: true)
        }

        // The music gets out of the way of the three biggest punchlines.
        var drops: [Seconds] = []
        if options.polish {
            for s in segments.sorted(by: { $0.potential > $1.potential }) where s.potential >= 70 && drops.count < 3 {
                if let t = timelineTime(ofSource: s.payoff), !drops.contains(where: { abs($0 - t) < 30 }) { drops.append(t) }
            }
        }

        // What an editor checks before exporting; mechanical problems are fixed here.
        let checks = EditQualityCheck.run(&timeline, words: analysis.transcript?.words ?? [],
                                          target: options.polish ? (options.minimumLength * 0.8)...(options.maximumLength * 1.15) : nil)

        // YouTube chapters for the description.
        timeline.notes = chapterList(timeline.markers.filter { $0.color == .blue }, hasHook: hookRange != nil)
        timeline.copy = ClipCopy(titles: segments.sorted { $0.potential > $1.potential }.prefix(3).map(\.title).filter { !$0.isEmpty },
                                 shortsTitle: "", tiktokCaption: "", instagramCaption: "", hashtags: [])
        timeline.modifiedAt = Date()

        let chapters = options.music ? musicChapters(for: timeline, hookEnd: hookEnd) : []
        let broll = options.extras.brollClips
            ? BrollPlacer.moments(segments: segments, timelineTime: timelineTime(ofSource:), hookEnd: hookEnd, duration: timeline.duration) : []
        var parts = ["\(segments.count) moments", "\(Timecode.short(timeline.duration)) long"]
        if removed > 1 { parts.append("\(Int(removed)) s of dead air cut") }
        if hookRange != nil { parts.append("hook") }
        if zooms > 0 { parts.append("\(zooms) zooms") }
        if memes > 0 { parts.append("\(memes) memes") }
        if whooshes > 0 { parts.append("\(whooshes) transitions") }
        if fades > 0 { parts.append("\(fades) fades") }
        if transitions > 0 { parts.append("\(transitions) chapter transitions") }
        if jumpZooms > 0 { parts.append("\(jumpZooms) jump-cut zooms") }
        if slivers > 0 { parts.append("\(slivers) slivers removed") }
        if crosstalk > 0.5 { parts.append("\(Int(crosstalk.rounded())) s of crosstalk trimmed") }
        if facecamZooms > 0 { parts.append("\(facecamZooms) facecam punch-ins") }
        if cards > 0 { parts.append("\(cards) title cards") }
        if let style = options.style { parts.append("styled like “\(style.name)”") }
        parts.append(checks.summary.lowercased())
        return LongFormResult(timeline: timeline, segments: segments, report: parts.joined(separator: " · "), musicChapters: chapters,
                              musicDrops: drops, checks: checks, brollMoments: broll)
    }

    /// 4–7 s around the payoff: a beat of setup, the moment, the first reaction.
    static func hookWindow(around payoff: Seconds, analysis: MediaAnalysis) -> TimeRange {
        var start = max(0, payoff - 3.5), end = min(analysis.duration, payoff + 2.5)
        if let words = analysis.transcript?.words {
            // Don't start or stop inside a word.
            if let w = words.first(where: { $0.start < start && $0.end > start }) { start = w.start }
            if let w = words.first(where: { $0.start < end && $0.end > end }) { end = min(analysis.duration, w.end + 0.1) }
        }
        return TimeRange(start: start, end: end)
    }

    struct Meme {
        var text: String
        var sounds: [String]
        var color: RGBAColor
        var tilt: Double
    }

    static func memeFor(tags: [ClipTag]) -> Meme {
        let yellow = RGBAColor(hex: "#FFD60A")!, pink = RGBAColor(hex: "#FF3D6E")!
        switch tags.first {
        case .funny: return Meme(text: "💀💀💀", sounds: ["rimshot", "boom"], color: .white, tilt: -4)
        case .fail: return Meme(text: "BRUH", sounds: ["sad trombone", "trombone", "boom"], color: yellow, tilt: 3)
        case .hype: return Meme(text: "LET'S GO", sounds: ["impact", "boom"], color: yellow, tilt: -3)
        case .rage: return Meme(text: "😤", sounds: ["record scratch", "scratch", "boom"], color: .white, tilt: 0)
        case .reaction: return Meme(text: "NO WAY", sounds: ["boom", "impact"], color: pink, tilt: -3)
        case .story, .conversation, .question: return Meme(text: "👀", sounds: ["ding", "pop"], color: .white, tilt: 0)
        default: return Meme(text: "W", sounds: ["boom", "impact"], color: yellow, tilt: -4)
        }
    }

    /// Music sections (~3–4 min each) following the edit's chapters, after the cold open.
    public static func musicChapters(for timeline: Timeline, hookEnd: Seconds) -> [TimeRange] {
        let total = timeline.duration
        guard total - hookEnd > 5 else { return [] }
        let chapterStarts = timeline.markers.filter { $0.color == .blue }.map(\.time).sorted()
        var cuts: [Seconds] = [hookEnd]
        for t in chapterStarts where t - cuts.last! >= 150 && total - t >= 60 { cuts.append(t) }
        cuts.append(total)
        var ranges: [TimeRange] = []
        for i in 0..<(cuts.count - 1) {
            var a = cuts[i]
            let b = cuts[i + 1]
            // Very long chapters get split so a bed never runs more than ~5 minutes.
            while b - a > 330 {
                ranges.append(TimeRange(start: a, end: a + 240))
                a += 240
            }
            ranges.append(TimeRange(start: a, end: b))
        }
        return ranges
    }

    /// Lays composed beds (one per chapter, same order) on A2, quiet and ducked under talking.
    /// Music sits about 22 dB under the (−14 LUFS) dialogue before ducking.
    public static let musicLevel = 0.08

    public static func addMusic(_ beds: [MediaAsset], chapters: [TimeRange], to timeline: inout Timeline, drops: [Seconds] = []) {
        guard let ti = timeline.tracks.firstIndex(where: { $0.name.hasPrefix("A2") }), !beds.isEmpty else { return }
        timeline.tracks[ti].clips.removeAll { $0.role == .music && $0.aiGenerated }
        for (index, range) in chapters.enumerated() {
            // Fewer tracks than chapters: cycle; a track shorter than its chapter repeats.
            let bed = beds[index % beds.count]
            let length = bed.metadata.duration > 3 ? bed.metadata.duration : range.duration
            var t = range.start
            while range.end - t > 1 {
                let piece = min(length, range.end - t)
                var clip = TimelineClip(name: bed.name, content: .media(assetID: bed.id), start: t, sourceDuration: piece, role: .music, aiGenerated: true)
                // A bed, not a feature: leveled first (so loud and quiet tracks sit the same), then well under
                // the voice and ducked further while anyone talks.
                clip.audio.normalize = true
                clip.audio.volume = AnimatedDouble(musicLevel)
                clip.audio.duckUnderDialogue = true
                clip.audio.duckAmountDB = -14
                clip.audio.fadeIn = t == range.start ? 2.5 : 1
                clip.audio.fadeOut = t + piece >= range.end - 1 ? 3 : 1
                timeline.tracks[ti].clips.append(clip)
                t += piece
            }
        }
        timeline.tracks[ti].sortClips()
        EditPolish.musicDrops(&timeline, at: drops)
    }

    static func chapterList(_ markers: [Marker], hasHook: Bool) -> String {
        var lines = ["Chapters"]
        if hasHook { lines.append("0:00 Intro") }
        for (i, m) in markers.sorted(by: { $0.time < $1.time }).enumerated() {
            let t = i == 0 && !hasHook ? 0 : m.time
            lines.append("\(youtubeTimestamp(t)) \(m.name)")
        }
        return lines.joined(separator: "\n")
    }

    static func youtubeTimestamp(_ t: Seconds) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension CaptionStyle {
    /// Subtitles for landscape YouTube edits: no box behind them — white with a dark outline and a soft
    /// shadow reads on bright and dark footage alike — modest size, low in frame, a few words at a time.
    public static let youtube = CaptionStyle(
        presetName: "YouTube",
        text: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 42, weight: .bold, textCase: .asTyped, color: .white,
                        strokeColor: .black, strokeWidth: 4, shadowOpacity: 0.7, shadowRadius: 6, shadowOffsetY: 2),
        highlightColor: RGBAColor(hex: "#FFD60A")!, highlightMode: .none, animation: .fade, displayMode: .phrase,
        maxWordsPerPage: 7, maxCharsPerLine: 34, maxLines: 2, positionY: 0.86, safeArea: nil)
}
