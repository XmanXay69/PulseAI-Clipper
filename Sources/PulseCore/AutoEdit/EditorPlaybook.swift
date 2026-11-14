import Foundation

/// The rules an editing style lives by, in numbers the coach can check an edit against. They come from what
/// working editors and retention strategists teach in public: a hook that lands early, something new on
/// screen before attention drifts, a reset every couple of minutes on long videos, effects kept for the
/// moments that deserve them, and captions short enough to read at a glance.
public struct PacingRules: Codable, Hashable, Sendable {
    /// The promise or the best moment is on screen by this many seconds in.
    public var hookDeadline: Seconds
    /// Longest the edit may go with no cut, zoom, pop-up or layout change.
    public var maxStaticStretch: Seconds
    /// The same, for a stretch that starts in the first half minute — where most viewers decide to stay.
    public var openingStaticStretch: Seconds
    /// A long video marks a new section about this often (0 = the format has no sections).
    public var rehookInterval: Seconds
    public var maxZoomsPerMinute: Double
    public var maxEffectsPerMinute: Double
    /// Most caption words on screen at once.
    public var maxCaptionWords: Int
    /// Longest caption line, in characters.
    public var maxCaptionLineLength: Int
    /// How long a punch-in takes to arrive. Short ones snap (a jolt on the joke); from 0.4 s up the move
    /// starts slow, travels and settles, and the coach treats a zoom that jumps in as out of style.
    public var zoomRamp: Seconds

    /// From this ramp up, a style is one where moves glide rather than snap.
    public static let glidingRamp: Seconds = 0.4

    public var zoomsGlide: Bool { zoomRamp >= PacingRules.glidingRamp }

    public init(hookDeadline: Seconds, maxStaticStretch: Seconds, openingStaticStretch: Seconds, rehookInterval: Seconds,
                maxZoomsPerMinute: Double, maxEffectsPerMinute: Double, maxCaptionWords: Int, maxCaptionLineLength: Int,
                zoomRamp: Seconds = 0.25) {
        self.hookDeadline = hookDeadline
        self.maxStaticStretch = maxStaticStretch
        self.openingStaticStretch = openingStaticStretch
        self.rehookInterval = rehookInterval
        self.maxZoomsPerMinute = maxZoomsPerMinute
        self.maxEffectsPerMinute = maxEffectsPerMinute
        self.maxCaptionWords = maxCaptionWords
        self.maxCaptionLineLength = maxCaptionLineLength
        self.zoomRamp = zoomRamp
    }

    /// What an edit is held to when no playbook was chosen: a phone short decides in two or three seconds and
    /// wants a change every few; a YouTube video gets about fifteen seconds to make its promise, a change of
    /// picture within half a minute, and a reset every two to three minutes.
    public static func standard(for format: EditFormat) -> PacingRules {
        switch format {
        case .short:
            return PacingRules(hookDeadline: 2, maxStaticStretch: 8, openingStaticStretch: 5, rehookInterval: 0,
                               maxZoomsPerMinute: 10, maxEffectsPerMinute: 12, maxCaptionWords: 4, maxCaptionLineLength: 26, zoomRamp: 0.18)
        case .longForm:
            return PacingRules(hookDeadline: 15, maxStaticStretch: 30, openingStaticStretch: 15, rehookInterval: 180,
                               maxZoomsPerMinute: 4, maxEffectsPerMinute: 6, maxCaptionWords: 8, maxCaptionLineLength: 42)
        }
    }
}

/// How one school of editing cuts, written down so the auto-editor can cut that way and the coach can hold an
/// edit to it. Each playbook is a style fingerprint in the same form a studied reference video gets
/// (`ReferenceStyle`), the rules that style lives by, and the reasons behind them in plain words.
///
/// Nothing here is a trained model. It is editing craft collected from public teaching — the "smoothness
/// first" approach of editing tutors such as Finzar, the hook → new information → payoff structure retention
/// strategists describe, Walter Murch's ordering of what a cut must serve (emotion, then story, then rhythm),
/// subtitle reading-speed standards, and published breakdowns of what high-performing shorts have in common —
/// turned into settings the existing editors already understand.
public struct EditorPlaybook: Hashable, Identifiable, Sendable {
    public struct Principle: Hashable, Sendable {
        public var title: String
        public var detail: String

        public init(_ title: String, _ detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public var id: String
    public var name: String
    /// One line: what an edit in this style feels like.
    public var tagline: String
    public var bestFor: String
    /// SF Symbol for the style's card.
    public var symbol: String
    public var style: ReferenceStyle
    public var rules: PacingRules
    public var principles: [Principle]

    public init(id: String, name: String, tagline: String, bestFor: String, symbol: String, style: ReferenceStyle, rules: PacingRules,
                principles: [Principle]) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.bestFor = bestFor
        self.symbol = symbol
        self.style = style
        self.rules = rules
        self.principles = principles
    }
}

extension EditorPlaybook {
    /// Built-in styles keep one identity across launches, so a style picked last week is still that style.
    static func styleID(_ n: Int) -> UUID {
        let hex = String(n, radix: 16, uppercase: true)
        return UUID(uuidString: "50554C53-4500-4000-8000-" + String(repeating: "0", count: max(0, 12 - hex.count)) + hex) ?? UUID()
    }
    static let written = Date(timeIntervalSince1970: 1_780_000_000)

    /// Fast, loud and funny: the gaming-highlights cut.
    public static let retention = EditorPlaybook(
        id: "retention", name: "Retention cut",
        tagline: "Fast, loud and funny. Something changes every few seconds.",
        bestFor: "Gaming highlights, challenges and reaction videos", symbol: "bolt.fill",
        style: ReferenceStyle(id: styleID(1), name: "Retention cut", measuredAt: written, duration: 600, aspect: 16.0 / 9.0,
                              cutsPerMinute: 12, averageShotLength: 5, zoomsPerMinute: 5, zoomScale: 1.22,
                              captions: ReferenceStyle.CaptionLook(coverage: 0.45, positionY: 0.82, lineHeight: 0.06, wordsOnScreen: 3, uppercase: true),
                              popupsPerMinute: 1.0, wordsPerMinute: 190, pauseRatio: 0.04, musicBed: 0.75, effectsPerMinute: 4,
                              fadesPerMinute: 0.1, opensFast: true),
        rules: PacingRules(hookDeadline: 8, maxStaticStretch: 15, openingStaticStretch: 8, rehookInterval: 120,
                           maxZoomsPerMinute: 8, maxEffectsPerMinute: 8, maxCaptionWords: 4, maxCaptionLineLength: 26, zoomRamp: 0.16),
        principles: [
            Principle("Open on the moment", "No greeting, no logo. The first seconds show the best thing that happens, then the story starts."),
            Principle("Change something every few seconds", "A cut, a punch-in, a word on screen or a sound. Vary which one, or the changes become the pattern."),
            Principle("Cut the breath, keep the reaction", "Pauses and false starts go. The laugh, the scream and the beat after it stay."),
            Principle("Sound sells the hit", "A whoosh for movement, a hit on the reveal, the music pulled out for a beat before the punchline."),
            Principle("Every second earns its place", "If a stretch neither moves the story nor gets a laugh, it is cut."),
        ])

    /// A promise, a build and a payoff.
    public static let story = EditorPlaybook(
        id: "story", name: "Story first",
        tagline: "A promise, a build and a payoff. Cuts follow the feeling, not a clock.",
        bestFor: "Challenges, vlogs, documentary-style videos and IRL streams", symbol: "book.fill",
        style: ReferenceStyle(id: styleID(2), name: "Story first", measuredAt: written, duration: 900, aspect: 16.0 / 9.0,
                              cutsPerMinute: 7, averageShotLength: 8.5, zoomsPerMinute: 1.5, zoomScale: 1.12,
                              captions: ReferenceStyle.CaptionLook(coverage: 0.2, positionY: 0.85, lineHeight: 0.045, wordsOnScreen: 6, uppercase: false),
                              popupsPerMinute: 0.4, wordsPerMinute: 165, pauseRatio: 0.09, musicBed: 0.85, effectsPerMinute: 1.5,
                              fadesPerMinute: 0.35, opensFast: true),
        rules: PacingRules(hookDeadline: 15, maxStaticStretch: 25, openingStaticStretch: 12, rehookInterval: 150,
                           maxZoomsPerMinute: 3, maxEffectsPerMinute: 4, maxCaptionWords: 8, maxCaptionLineLength: 42, zoomRamp: 0.3),
        principles: [
            Principle("Make a promise in fifteen seconds", "Say what the viewer will get and show a taste of it. Then start delivering."),
            Principle("Pace is new information", "A video feels fast when something new keeps arriving, not when the cuts come quicker."),
            Principle("Close one loop, open the next", "Each section settles a question and raises the next, about every two to three minutes."),
            Principle("Emotion before continuity", "Cut where the feeling changes. A cut that is right for the moment forgives one that is rough on the eye."),
            Principle("Change the music when the story changes", "One bed per chapter, never one song looped under everything."),
        ])

    /// Calm and clear; the edit stays out of the way.
    public static let commentary = EditorPlaybook(
        id: "commentary", name: "Clean commentary",
        tagline: "Calm, clear and unhurried. The edit stays out of the way of the voice.",
        bestFor: "Podcasts, interviews, talking-head and tutorial streams", symbol: "mic.fill",
        style: ReferenceStyle(id: styleID(3), name: "Clean commentary", measuredAt: written, duration: 900, aspect: 16.0 / 9.0,
                              cutsPerMinute: 3, averageShotLength: 20, zoomsPerMinute: 0.6, zoomScale: 1.08,
                              captions: ReferenceStyle.CaptionLook(coverage: 0.9, positionY: 0.86, lineHeight: 0.04, wordsOnScreen: 7, uppercase: false),
                              popupsPerMinute: 0.05, wordsPerMinute: 155, pauseRatio: 0.11, musicBed: 0.25, effectsPerMinute: 0.2,
                              fadesPerMinute: 0.25, opensFast: false),
        rules: PacingRules(hookDeadline: 20, maxStaticStretch: 40, openingStaticStretch: 20, rehookInterval: 180,
                           maxZoomsPerMinute: 2, maxEffectsPerMinute: 1.5, maxCaptionWords: 10, maxCaptionLineLength: 42, zoomRamp: 0.4),
        principles: [
            Principle("Cut on a change of thought", "Hold a shot through the whole statement. A cut mid-gesture or mid-word reads as a mistake."),
            Principle("Push in slowly", "A gentle move across a long answer keeps the frame alive without calling attention to itself."),
            Principle("The voice leads", "Music sits far under the talking or is left out. Nothing competes with the words."),
            Principle("Leave room after the big line", "A beat of quiet lets a strong statement land, and makes the next section feel quicker."),
            Principle("Captions are for reading", "Two lines at most, about forty characters each, on screen long enough to finish."),
        ])

    /// The phone short.
    public static let punchyShort = EditorPlaybook(
        id: "short", name: "Punchy short",
        tagline: "Hook in two seconds, a word or two at a time, out on the laugh.",
        bestFor: "TikTok, YouTube Shorts and Instagram Reels", symbol: "iphone",
        style: ReferenceStyle(id: styleID(4), name: "Punchy short", measuredAt: written, duration: 35, aspect: 9.0 / 16.0,
                              cutsPerMinute: 18, averageShotLength: 3.3, zoomsPerMinute: 9, zoomScale: 1.2,
                              captions: ReferenceStyle.CaptionLook(coverage: 0.95, positionY: 0.68, lineHeight: 0.07, wordsOnScreen: 2, uppercase: false),
                              popupsPerMinute: 1.5, wordsPerMinute: 200, pauseRatio: 0.03, musicBed: 0.3, effectsPerMinute: 4,
                              fadesPerMinute: 0, opensFast: true),
        rules: PacingRules(hookDeadline: 2, maxStaticStretch: 6, openingStaticStretch: 4, rehookInterval: 0,
                           maxZoomsPerMinute: 10, maxEffectsPerMinute: 10, maxCaptionWords: 3, maxCaptionLineLength: 22, zoomRamp: 0.12),
        principles: [
            Principle("Win the first three seconds", "Lead with the most interesting moment. If the first sentence takes three seconds to reach its point, start later."),
            Principle("One or two words per beat", "Animated captions in mixed case, with the stressed word coloured, kept above the bottom of the frame where the app's buttons sit."),
            Principle("No intro, no outro", "Almost no short that performs opens on a logo. End early, on the upswing."),
            Principle("Loop it", "The last line hands back to the first, so a second watch starts before the viewer decides to leave."),
            Principle("Rough is fine", "A quick reframe beats a designed transition. Polish that slows the short down costs more than it adds."),
        ])

    /// Every move eases; nothing snaps.
    public static let smooth = EditorPlaybook(
        id: "smooth", name: "Smooth and cinematic",
        tagline: "Every move eases and nothing snaps. Music leads, effects whisper.",
        bestFor: "Showcases, travel, essays and polished channel videos", symbol: "wand.and.rays",
        style: ReferenceStyle(id: styleID(5), name: "Smooth and cinematic", measuredAt: written, duration: 600, aspect: 16.0 / 9.0,
                              cutsPerMinute: 6, averageShotLength: 10, zoomsPerMinute: 2.5, zoomScale: 1.1,
                              captions: ReferenceStyle.CaptionLook(coverage: 0.3, positionY: 0.86, lineHeight: 0.045, wordsOnScreen: 5, uppercase: false),
                              popupsPerMinute: 0.2, wordsPerMinute: 150, pauseRatio: 0.1, musicBed: 0.95, effectsPerMinute: 2,
                              fadesPerMinute: 0.6, opensFast: false),
        rules: PacingRules(hookDeadline: 12, maxStaticStretch: 20, openingStaticStretch: 12, rehookInterval: 150,
                           maxZoomsPerMinute: 4, maxEffectsPerMinute: 4, maxCaptionWords: 7, maxCaptionLineLength: 42, zoomRamp: 0.6),
        principles: [
            Principle("Smoothness is the secret", "Graphics ease on instead of snapping, zooms glide, transitions never start abruptly. Harsh moves pull the viewer out."),
            Principle("Shape the speed of every move", "A move that starts slow, travels and settles reads as intended. A constant-speed one reads as a preset."),
            Principle("Whooshes on motion, risers into reveals", "An effect matches the movement it sits under and stays under the voice."),
            Principle("Match moves across a cut", "Two shots zooming at the same speed join without a seam."),
            Principle("Let the music carry it", "Sections change on the phrase, and the picture follows."),
        ])

    /// Cuts on the kick.
    public static let onTheBeat = EditorPlaybook(
        id: "beat", name: "On the beat",
        tagline: "Cuts land on the kick. The music is the script.",
        bestFor: "Highlight reels, frag movies and recaps", symbol: "metronome.fill",
        style: ReferenceStyle(id: styleID(6), name: "On the beat", measuredAt: written, duration: 240, aspect: 16.0 / 9.0,
                              cutsPerMinute: 22, averageShotLength: 2.7, zoomsPerMinute: 4, zoomScale: 1.18,
                              captions: nil, popupsPerMinute: 0.3, wordsPerMinute: nil, pauseRatio: nil, musicBed: 1, effectsPerMinute: 3,
                              fadesPerMinute: 0.3, opensFast: true),
        rules: PacingRules(hookDeadline: 3, maxStaticStretch: 6, openingStaticStretch: 4, rehookInterval: 60,
                           maxZoomsPerMinute: 8, maxEffectsPerMinute: 6, maxCaptionWords: 4, maxCaptionLineLength: 26, zoomRamp: 0.1),
        principles: [
            Principle("Cut on the kick and the snare", "Hard cuts sit on the beat. The eye forgives almost anything that lands in time."),
            Principle("Build, drop, breathe", "Short shots into the drop, the biggest play on it, a longer shot after."),
            Principle("Slow down for the best one", "A time ramp into the play of the video, then back to full speed."),
            Principle("No talking, no captions", "The game's sound and the track do the work. Text is for a name or a score."),
            Principle("Leave them wanting the next one", "Three minutes of the best beats ten of everything."),
        ])

    public static let all: [EditorPlaybook] = [.retention, .story, .commentary, .punchyShort, .smooth, .onTheBeat]

    public static func playbook(id: String) -> EditorPlaybook? { all.first { $0.id == id } }

    /// The playbook a style came from, when it is one of the built-in ones.
    public static func playbook(for style: ReferenceStyle) -> EditorPlaybook? { all.first { $0.style.id == style.id } }

    /// The style most recordings of this kind are cut in — a starting point, not a verdict.
    public static func suggested(for profile: ContentProfile, format: EditFormat = .longForm) -> EditorPlaybook {
        if format == .short { return .punchyShort }
        switch profile {
        case .gameplayWithFacecam, .gameplay: return .retention
        case .talkingHead, .podcast: return .commentary
        case .unknown: return .story
        }
    }

    /// The pacing rules an edit is held to: its playbook's when it was cut in one, else the standard ones for
    /// its format.
    public static func rules(for timeline: Timeline) -> PacingRules {
        timeline.editStyle.flatMap(playbook(id:))?.rules ?? .standard(for: EditFormat.of(timeline))
    }

    /// One line per number, for the style's card: what the auto-editor will actually do.
    public var recipe: [String] {
        var lines: [String] = []
        lines.append("A cut about every \(ReferenceStyle.seconds(style.averageShotLength))")
        if style.hasZooms {
            lines.append("A punch-in about every \(ReferenceStyle.seconds(60 / style.zoomsPerMinute)), \(Int(((style.zoomScale - 1) * 100).rounded()))% closer"
                         + (rules.zoomsGlide ? ", easing in over \(String(format: "%.1f", rules.zoomRamp)) s" : ""))
        }
        if let captions = style.captions, style.hasCaptions {
            lines.append(captions.wordsOnScreen < 2.5 ? "Captions a word or two at a time" : "Captions about \(Int(captions.wordsOnScreen.rounded())) words at a time")
        } else {
            lines.append("No burned-in captions")
        }
        lines.append(style.hasMusic ? "Music under it" : (style.musicBed >= 0.15 ? "Music in places" : "No music bed"))
        if style.hasSoundEffects { lines.append("A sound effect about every \(ReferenceStyle.seconds(60 / style.effectsPerMinute))") }
        if style.hasPopups { lines.append("A pop-up about every \(ReferenceStyle.seconds(60 / style.popupsPerMinute))") }
        lines.append("The hook lands in the first \(Int(rules.hookDeadline)) s")
        return lines
    }
}

extension EditorPlaybook {
    /// `base` cut in this style: the style decides the touches and their spacing; the length, the extras and
    /// the things that are yours (handle, pop-up wording, tighten, chapter titles, progress bar) stay as asked.
    public func styled(_ base: LongFormOptions) -> LongFormOptions {
        var answers = ReferenceAnswers.recommended(for: style)
        if answers.length == .shorts { answers.length = .youtube }
        var options = style.longFormOptions(answers)
        options.minimumLength = base.minimumLength
        options.maximumLength = base.maximumLength
        options.extras = base.extras
        options.socialHandle = base.socialHandle
        options.memeTexts = base.memeTexts
        options.tighten = base.tighten
        options.shortenPauses = base.shortenPauses
        options.musicLevel = base.musicLevel
        options.chapterTitles = base.chapterTitles
        options.progressBar = base.progressBar
        options.cutGameOnly = base.cutGameOnly
        options.keepStoryOrder = base.keepStoryOrder
        options.endScreen = base.endScreen
        options.nextVideoAssetID = base.nextVideoAssetID
        options.openLoop = base.openLoop || plantsTease
        return options
    }

    /// The styles built on a promise kept late: they plant a tease for the strongest later moment (#582).
    public var plantsTease: Bool { id == EditorPlaybook.retention.id || id == EditorPlaybook.story.id }
}

extension AISettings {
    /// Stored in `editStyleByProfile` for a kind of recording that should keep PULSE's own way.
    public static let ownStyle = "own"

    /// The style a new edit of this kind of recording is cut in (#626): nil when the switch is off or the
    /// kind is set to PULSE's own way. Shorts always get the short-form style.
    public func defaultPlaybook(for profile: ContentProfile, format: EditFormat = .longForm) -> EditorPlaybook? {
        guard autoEditStyle else { return nil }
        if format == .short { return .punchyShort }
        if let id = editStyleByProfile[profile.rawValue] {
            if id == AISettings.ownStyle { return nil }
            if let playbook = EditorPlaybook.playbook(id: id), !playbook.style.isShortForm { return playbook }
        }
        return EditorPlaybook.suggested(for: profile, format: .longForm)
    }

    /// What the Settings row for a kind of recording shows: your pick, else the suggested style's id.
    public func editStyleID(for profile: ContentProfile) -> String {
        if let id = editStyleByProfile[profile.rawValue],
           id == AISettings.ownStyle || EditorPlaybook.playbook(id: id).map({ !$0.style.isShortForm }) == true { return id }
        return EditorPlaybook.suggested(for: profile, format: .longForm).id
    }
}

/// Holds a finished edit to a playbook's rules and says, in editing terms, where it falls short.
public enum PlaybookCoach {
    /// Stretches of the edit where nothing about the picture's editing changes: no cut, no new layer, no move
    /// in progress, no layout change. Footage can be busy inside one; the edit isn't.
    public static func staticStretches(in timeline: Timeline) -> [TimeRange] {
        let duration = timeline.duration
        guard duration > 0 else { return [] }
        var busy: [TimeRange] = []
        func event(_ t: Seconds) {
            guard t > 0.05, t < duration - 0.05 else { return }
            busy.append(TimeRange(start: t - 0.02, end: t + 0.02))
        }
        for track in timeline.tracks where track.kind != .audio && !track.isHidden {
            for clip in track.clips where clip.isEnabled {
                event(clip.start)
                if case .text = clip.content { event(clip.end) }
                let t = clip.transform
                for property in [t.zoom, t.scale, t.panX, t.panY, t.positionX, t.positionY, t.rotation, t.opacity] {
                    for (a, b) in zip(property.keyframes, property.keyframes.dropFirst()) where abs(a.value - b.value) > 1e-4 {
                        if a.interpolation == .hold {
                            event(clip.start + b.time)
                        } else {
                            busy.append(TimeRange(start: clip.start + a.time, end: clip.start + b.time))
                        }
                    }
                }
            }
        }
        for change in timeline.layoutChanges {
            busy.append(TimeRange(start: change.time, end: change.time + max(change.duration, 0.04)))
        }
        busy.sort { $0.start < $1.start }
        var stretches: [TimeRange] = []
        var cursor: Seconds = 0
        for range in busy {
            if range.start > cursor + 0.01 { stretches.append(TimeRange(start: cursor, end: min(range.start, duration))) }
            cursor = max(cursor, range.end)
            if cursor >= duration { break }
        }
        if cursor < duration - 0.01 { stretches.append(TimeRange(start: cursor, end: duration)) }
        return stretches
    }

    /// How long each zoom-in on the footage takes to arrive, in seconds (0 for one that jumps). Pop-up text is
    /// left out: a word that pops is meant to.
    public static func zoomArrivals(in timeline: Timeline) -> [Seconds] {
        var arrivals: [Seconds] = []
        for track in timeline.tracks where track.kind == .video && !track.isHidden {
            for clip in track.clips where clip.isEnabled {
                guard case .media = clip.content else { continue }
                for property in [clip.transform.zoom, clip.transform.scale] {
                    for (a, b) in zip(property.keyframes, property.keyframes.dropFirst()) where b.value > a.value + 1e-3 {
                        arrivals.append(a.interpolation == .hold ? 0 : max(0, b.time - a.time))
                    }
                }
            }
        }
        return arrivals
    }

    /// How many zoom-ins one clip has (`aiOnly`: only the ones PULSE made).
    public static func zoomArrivals(of clip: TimelineClip, aiOnly: Bool = false) -> Int {
        var count = 0
        for property in [clip.transform.zoom, clip.transform.scale] {
            for (a, b) in zip(property.keyframes, property.keyframes.dropFirst()) where b.value > a.value + 1e-3 {
                if !aiOnly || (a.aiGenerated && b.aiGenerated) { count += 1 }
            }
        }
        return count
    }

    /// Times a long video marks a new section: a chapter marker, a new music bed, a transition, a layout change.
    public static func resets(in timeline: Timeline) -> [Seconds] {
        var times = timeline.markers.map(\.time) + timeline.layoutChanges.map(\.time)
        for clip in timeline.allClips where clip.isEnabled {
            if clip.role == .music || clip.transitionIn != nil { times.append(clip.start) }
        }
        return times.sorted()
    }

    /// What a playbook would change about this edit. `existing` holds the ids the coach already raised, so the
    /// same advice isn't given twice in different words. Moving footage (gameplay) is given twice the room a
    /// still frame gets before a held shot counts as static.
    public static func suggestions(for timeline: Timeline, format: EditFormat, rules: PacingRules, profile: ContentProfile = .unknown,
                                   existing: Set<String> = []) -> [EditSuggestion] {
        let duration = timeline.duration
        guard duration > 4 else { return [] }
        var out: [EditSuggestion] = []
        let room: Double = (profile == .gameplay || profile == .gameplayWithFacecam) ? 2 : 1

        // A held picture. The opening is held to the tighter figure.
        if !existing.contains("zooms") {
            var worst: (range: TimeRange, limit: Seconds, excess: Double)?
            for stretch in staticStretches(in: timeline) {
                let limit = (stretch.start < 30 ? rules.openingStaticStretch : rules.maxStaticStretch) * room
                let excess = stretch.duration / max(limit, 0.5)
                if excess > 1.15, excess > (worst?.excess ?? 0) { worst = (stretch, limit, excess) }
            }
            if let worst {
                let opening = worst.range.start < 30
                out.append(EditSuggestion(
                    id: "static-stretch", title: "No cut, zoom or pop-up for \(Int(worst.range.duration.rounded())) s",
                    detail: "From \(Timecode.short(worst.range.start)) the edit holds one framing. A punch-in, a cutaway or a word on screen about every \(Int(worst.limit.rounded())) s keeps eyes on it"
                        + (opening ? "; the opening is where most viewers decide to stay." : "."),
                    severity: opening || worst.excess > 2 ? .recommended : .tip, fix: .addZooms, symbol: "rectangle.dashed"))
            }
        }

        // Zooms that jump in, in a style whose moves glide.
        if rules.zoomsGlide {
            let arrivals = zoomArrivals(in: timeline)
            let snaps = arrivals.filter { $0 < rules.zoomRamp * 0.5 }.count
            if snaps >= 2, snaps * 2 >= arrivals.count {
                out.append(EditSuggestion(
                    id: "snap-zooms", title: "Zooms snap in",
                    detail: "\(snaps) of \(arrivals.count) zooms arrive in under \(String(format: "%.1f", rules.zoomRamp * 0.5)) s. This style lets a move start slow, travel and settle over about \(String(format: "%.1f", rules.zoomRamp)) s, so it reads as intended instead of as a jolt. Pull the two keyframes apart and set the first to ease in and out.",
                    severity: .tip, fix: .none, symbol: "plus.magnifyingglass"))
            }
        }

        // No new section for too long (long videos only).
        if format == .longForm, rules.rehookInterval > 0, duration > rules.rehookInterval * 2 {
            let marks = [0] + resets(in: timeline) + [duration]
            var longest: (start: Seconds, length: Seconds) = (0, 0)
            for (a, b) in zip(marks, marks.dropFirst()) where b - a > longest.length { longest = (a, b - a) }
            if longest.length > rules.rehookInterval * 1.6 {
                let every = max(1, Int((rules.rehookInterval / 60).rounded()))
                out.append(EditSuggestion(
                    id: "rehook", title: "No new section for \(Int((longest.length / 60).rounded())) min",
                    detail: "Nothing marks a change from \(Timecode.short(longest.start)) to \(Timecode.short(longest.start + longest.length)). Long videos hold people in cycles: settle one thing, open the next. A chapter card, a change of music or a line that looks ahead about every \(every) min gives them a reason to stay.",
                    severity: .tip, fix: .none, symbol: "arrow.triangle.2.circlepath"))
            }
        }

        // Sound effects until none of them land.
        let effects = timeline.allClips.filter { $0.role == .soundEffect && $0.isEnabled }.count
        let effectsPerMinute = Double(effects) / max(duration / 60, 0.25)
        if effects >= 4, effectsPerMinute > rules.maxEffectsPerMinute {
            out.append(EditSuggestion(
                id: "over-sfx", title: "Ease off the sound effects",
                detail: "\(effects) effects in \(Timecode.short(duration)) is one about every \(Int((duration / Double(effects)).rounded())) s. Kept for reveals, mistakes and punchlines, each one still lands.",
                severity: .tip, fix: .none, symbol: "speaker.slash"))
        }

        // Captions too long to read at a glance.
        if let captions = timeline.captions, captions.isEnabled, !captions.words.isEmpty {
            if format == .short, captions.style.maxWordsPerPage > rules.maxCaptionWords {
                out.append(EditSuggestion(
                    id: "caption-pages", title: "Shorter caption pages",
                    detail: "Captions show up to \(captions.style.maxWordsPerPage) words at once. On a phone, \(rules.maxCaptionWords) or fewer reads at a glance and keeps pace with the voice.",
                    severity: .tip, fix: .none, symbol: "captions.bubble"))
            } else if format == .longForm, captions.style.maxCharsPerLine > rules.maxCaptionLineLength {
                out.append(EditSuggestion(
                    id: "caption-lines", title: "Caption lines run long",
                    detail: "Lines of up to \(captions.style.maxCharsPerLine) characters take longer to read than they stay up. About \(rules.maxCaptionLineLength) per line, two lines at most, is the subtitling standard.",
                    severity: .tip, fix: .none, symbol: "captions.bubble"))
            }
        }
        return out
    }
}
