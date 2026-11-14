import Foundation

/// What kind of video is being made. You pick it once, with a button, and it decides which editing style the
/// auto-editor cuts in: what a stream highlights video keeps is not what a montage keeps.
///
/// A genre is a front door to an `EditorPlaybook`. The playbook holds the numbers and the principles; the
/// genre says who it is for in the words a creator would use, and where its rules were read.
public enum VideoGenre: String, CaseIterable, Codable, Identifiable, Sendable {
    case streamHighlights, gamingVideo, challenge, vlog, commentary, cinematic, montage

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .streamHighlights: return "Stream highlights"
        case .gamingVideo: return "Gaming video"
        case .challenge: return "Challenge or story"
        case .vlog: return "Vlog"
        case .commentary: return "Commentary or podcast"
        case .cinematic: return "Cinematic"
        case .montage: return "Montage"
        }
    }

    public var symbol: String { playbook.symbol }

    /// One line: what this kind of video is, in a creator's words.
    public var blurb: String {
        switch self {
        case .streamHighlights: return "The best of a long stream, in order, with the dead time gone and your reactions kept."
        case .gamingVideo: return "A tightly edited gaming video: fast, funny, zooms and sound on the jokes."
        case .challenge: return "A video with a goal: the promise up front, the tries and setbacks, the ending."
        case .vlog: return "A day or a trip told as a story, cut to music."
        case .commentary: return "People talking: the voice leads and the edit stays out of the way."
        case .cinematic: return "Slow, smooth and music-led. Every move eases and shots are given time."
        case .montage: return "No talking: the best plays cut on the beat of a track."
        }
    }

    /// The editing style this genre is cut in.
    public var playbook: EditorPlaybook {
        switch self {
        case .streamHighlights: return .streamHighlights
        case .gamingVideo: return .retention
        case .challenge: return .story
        case .vlog: return .vlog
        case .commentary: return .commentary
        case .cinematic: return .smooth
        case .montage: return .onTheBeat
        }
    }

    /// The genre a style belongs to, when it is one a genre uses.
    public static func genre(forPlaybook id: String) -> VideoGenre? { allCases.first { $0.playbook.id == id } }

    /// The genre most recordings of this kind turn into: a starting point for the button, not a verdict. A
    /// game with a facecam is nearly always a stream; a game without one is usually a recorded video.
    public static func suggested(for profile: ContentProfile) -> VideoGenre {
        switch profile {
        case .gameplayWithFacecam: return .streamHighlights
        case .gameplay: return .gamingVideo
        case .talkingHead, .podcast: return .commentary
        case .unknown: return .challenge
        }
    }

    /// Something that was read, or watched, for this genre's rules.
    public struct Source: Hashable, Sendable {
        public var title: String
        public var url: String
        /// What it contributed, in a few words.
        public var gave: String

        /// Titles of videos that were watched (frames and captions), as opposed to articles that were read.
        public static let watchedPrefix = "Watched: "
        public var wasWatched: Bool { title.hasPrefix(Source.watchedPrefix) }
    }

    /// A video that was watched for the study of 14 November 2026 (`docs/EDITING-STUDY-FINDINGS.md`).
    private static func watched(_ title: String, _ id: String, _ gave: String) -> Source {
        Source(title: Source.watchedPrefix + title, url: "https://www.youtube.com/watch?v=" + id, gave: gave)
    }

    /// Where this genre's rules were read, and which videos were watched for them: see `studyNote`.
    public var sources: [Source] {
        let retention = Source(title: "Vidpros on Mario Joos: retention editing", url: "https://vidpros.com/retention-editing-what-you-can-learn-from-mario-joos/",
                               gave: "hook, then steadily arriving new information, then a payoff")
        let patterns = Source(title: "AIR Media-Tech: cutting patterns that keep viewers past minute 8",
                              url: "https://air.io/en/youtube-hacks/advanced-retention-editing-cutting-patterns-that-keep-viewers-past-minute-8",
                              gave: "a reset around every half minute, a re-hook every two to three minutes")
        let rhythm = Source(title: "StudioBinder: how an editor controls the rhythm of a film",
                            url: "https://www.studiobinder.com/blog/how-does-an-editor-control-the-rhythm-of-a-film/",
                            gave: "shot length as the lever: shorter shots raise tension, longer ones release it; feelings take time")
        let nineCuts = Source(title: "PremiumBeat: nine essential cuts", url: "https://www.premiumbeat.com/blog/9-essential-video-editing-cuts",
                              gave: "the jump cut needs something to tie it together; the L-cut shows a listener without leaving the speaker; cutting on action, match cuts, montage for time passing")
        let finzarArticle = Source(title: "Finzar: The Real Secret to PRO Level Editing (newsletter)", url: "https://finzar.substack.com/p/the-real-secret-to-pro-level-editing",
                                   gave: "smoothness: nothing snaps on, zooms don't jolt, transitions don't start abruptly")
        let neebs = Source(title: "Creator Handbook: how Neebs Gaming edits videos to make them funnier",
                           url: "https://www.creatorhandbook.net/how-neebs-gaming-edits-videos-to-make-them-funnier-and-how-you-can-too/",
                           gave: "timing first; cut the dead space so the joke lands; a zoom on what the player missed; a freeze, a sting or the wrong music for the joke")
        let dovey = Self.watched("Jeven Dovey: How To Vlog and Be a Better Storyteller", "KdsWzPMCv7w",
                                 "five beats (setup, challenge, complications, payoff, change); setup, context and challenge inside 30 s; his own edit cuts 4 to 7 times a minute")
        let runia5 = Self.watched("Tim Runia: The ONLY 5 Editing Secrets You Need to Tell Any Story", "dhpazqW_OaU",
                                  "voiceover and music laid down before the shots; pace as fast bursts against calm holds, with silence at the turn; a new topic about every two minutes")
        switch self {
        case .streamHighlights:
            return [Source(title: "Nicole Rojas: edit Twitch streams for YouTube", url: "https://thenicolerojas.com/en/guides/edit-twitch-streams-for-youtube/",
                           gave: "cut whatever drags; find moments by the loud parts; captions and memes are for the short clips"),
                    neebs, patterns,
                    Self.watched("Cpaws Music: How To EDIT Your Twitch Streams", "x5frer5MoKk",
                                 "what gets cut from a stream: the chat before the game, breaks, other games; one game per highlight; about a fifth of the stream kept in his example. Nothing on how it should look"),
                    Self.watched("Patrick Stirling: The Easiest Ways to Edit Hours of Gameplay Footage", "57azbqwdcqM",
                                 "how a person finds the moments: scrub with the audio on, slower for a shooter than for a MOBA")]
        case .gamingVideo:
            return [finzarArticle, neebs,
                    Self.watched("Finzar: The Secret To Editing Professional Videos in 2026", "RutTgrCATwk",
                                 "smoothness is the shape of a move: ease out of the first keyframe and into the last, a fast start and a long soft landing, motion blur on"),
                    Self.watched("Finzar: How To Edit Super Smooth Transitions in Premiere Pro", "eEVxr6lzQSc",
                                 "a transition is about 12 frames, 0.2 s at 60 fps, and the cut sits under the moment it covers most of the frame"),
                    Self.watched("Storezar: How to Edit The BEST Sound Effects For Beginners", "L4da128D6Xc",
                                 "effect levels by role: whooshes about 16 dB down, transition whooshes about 12 dB down, always under the voice"),
                    Self.watched("Finzar: How To Edit Memes in Your Gaming Videos", "Ormb3Z0QJVs",
                                 "a quick meme runs about a second on a punchy ending; flash and shake recipes in frames; one homemade meme per video"),
                    Self.watched("Finzar: How I'd Edit a Viral Gaming Video in 2026", "_laioiIuvtw",
                                 "the 2026 version: sound on every major move, fewer memes, no need to cut every pause"),
                    Self.watched("Learn By Leo: How to edit SO good your viewers get addicted", "sLgHqZSe2o0",
                                 "cut density is an audience choice; captions three words or fewer; nothing just pops on screen")]
        case .challenge:
            return [retention, patterns,
                    Source(title: "Murch's Rule of Six (course note)", url: "https://cloud.wikis.utexas.edu/wiki/spaces/rtf318/pages/80022510/Murch+s+Rule+of+Six",
                           gave: "a cut serves emotion first, then story, then rhythm"),
                    dovey, runia5,
                    Self.watched("Tim Runia: The ONLY 7 Cuts You Need To Tell Any Story", "J0ydlAqg6_8",
                                 "smash cut when the sound drops too; cut during an action; speed of the cut as rhythm, a burst of shots against a long hold")]
        case .vlog:
            return [Source(title: "Artlist: the editing and storytelling techniques in Casey Neistat's videos",
                           url: "https://artlist.io/blog/editing-storytelling-techniques-casey-neistat/",
                           gave: "leaving mid-sentence, finishing a thought in the next place, quick-cut montages of a task"),
                    Source(title: "No Film School: seven storytelling techniques from Casey Neistat",
                           url: "https://nofilmschool.com/2016/08/7-storytelling-techniques-you-can-learn-filmmaker-youtube-star-casey-neistat",
                           gave: "the same seven techniques, from the editor who broke them down"),
                    retention,
                    Self.watched("Casey Neistat: How to vlog like Casey Neistat", "Q980C74SdYQ",
                                 "setup, conflict, resolution; equal handheld, locked-off and establishing shots; time-lapse and drone only for transition or context; his own edit runs 4 to 6 cuts a minute"),
                    dovey, runia5]
        case .commentary:
            return [Source(title: "OpusClip: what high-performing clips have in common", url: "https://www.opus.pro/blog/video-editing-tips",
                           gave: "captions on, short lines, no intro"),
                    nineCuts, rhythm,
                    Self.watched("Think Media: How to Edit a YouTube Video in 2026", "AV4UnrHznR8",
                                 "music about 33 dB down on its fader; b-roll of 2 to 4 s on the layer above covers the cuts in the talking head"),
                    Self.watched("Content Creators: Edit PRO YouTube Videos in CapCut", "Ex1R3rsdlms",
                                 "cut pauses out outright; music about 20 dB down with a new song per chapter; sound effects on the graphics"),
                    Self.watched("indietrix: How To Make A Video Essay: Editing", "Z2z514tcwpc",
                                 "a voice-led essay: voiceover first, gaps spaced by ear, sparing graphics, film sound only where nobody is talking"),
                    Self.watched("Olufemii: Cutting Talking Head Footage is a Science", "y7GoUICupVM",
                                 "angle changes cut on a motion; slow zoom on a static shot; a sound for every visual cue in a fast talking head"),
                    Self.watched("Joe Sbiti: How To Make VIRAL Podcast Clip Videos", "uTNnpkpYr0A",
                                 "podcast clips for social are calm: about 3 cuts a minute, no zooms, one small caption line under the chin")]
        case .cinematic:
            return [rhythm, nineCuts, finzarArticle,
                    Self.watched("Finzar: The Secret To Editing Professional Videos in 2026", "RutTgrCATwk",
                                 "moves shaped on the velocity graph: a fast start and a long soft landing, exits that mirror entrances"),
                    Self.watched("Joris Hermans: How to Edit a Cinematic Video in CapCut", "5QUSuMPD95k",
                                 "cut on every second or fourth beat, not every beat; a speed ramp shaped on a curve to the music"),
                    Self.watched("Andrew: The Power of SIMPLE Editing", "pdLEHfkwgV8",
                                 "pick the music first and cut at its dips; a fast run of shots as the hook"),
                    Self.watched("StudioBinder: 6 Ways to Edit Any Scene", "FVR8zz8ci2k",
                                 "J and L cuts so a conversation never stops dead; cut on action; keep the subject in the same place across a cut"),
                    Self.watched("Jonny Duncan: 10 Editing Cuts Every Video Editor Should Know", "YtULPT1aBWM",
                                 "fades and dissolves for time passing; a smash cut as the rare exception")]
        case .montage:
            return [Source(title: "Eklipse: how to make a gaming montage", url: "https://blog.eklipse.gg/beginner-guide-2/how-to-make-gaming-montage.html",
                           gave: "music first, cuts on the strong beats, the best fifteen to twenty-five clips a few seconds each"),
                    Source(title: "CapCut: matching cut speed to music", url: "https://www.capcut.com/create/music-video-pacing-emotional-montage-rhythm",
                           gave: "hold longer before the drop, one bold change on it"),
                    Self.watched("MagnnuM: CS2 fragmovie tutorial", "ByZ6vHSeX5A",
                                 "the best clip first and the standout shot on the climax; cut two or three frames after the kill with a zoom and a flash; a timeline of about 2.7 s per clip"),
                    Self.watched("Joshyy: How to EDIT Gaming Montages", "WYqTvyXRZ-c",
                                 "a marker on every drop and on every kill, then line them up; a short slow-motion tail after the kill"),
                    Self.watched("Vaultcar: How To Actually Make GOOD EDITS", "UDgKrsb1X7A",
                                 "cut every two to four beats but speed-ramp on every beat; a shake with a 7-frame attack; sounds matched exactly to each effect")]
        }
    }

    /// The videos among `sources` that were actually watched.
    public var watchedSources: [Source] { sources.filter(\.wasWatched) }

    /// How this genre's rules were arrived at, said plainly wherever they are shown: what was watched, and what
    /// the watching did and did not settle. Only a genre whose videos were really watched says so.
    public var studyNote: String {
        let tail = " They are starting points: change any switch below."
        switch self {
        case .streamHighlights:
            return "Five videos about editing stream clips were watched on 14 November 2026, but none of them showed how a long highlights video should look (four were about vertical clips or software). These rules were written from published guides, not learned by watching videos." + tail
        case .gamingVideo:
            return "Written from published guides, then checked against 18 editing videos watched on 14 November 2026 (the main ones are listed above). The zoom and pop-in speed, the length of a transition, effect levels and the layering of sound come from them. The gaming tutors disagree with one another on how often to cut and how many effects to use, so those numbers are still judgement." + tail
        case .challenge:
            return "Written from published guides, then checked against 4 story-craft videos watched on 14 November 2026. The promise by about twenty seconds, a new section about every two minutes and changing the pace on purpose come from them." + tail
        case .vlog:
            return "Written from published guides, then checked against 4 videos watched on 14 November 2026, which put a vlog-style edit at about 4 to 7 cuts a minute. \"Leave mid-thought\" comes from a written breakdown of Casey Neistat's videos; none of the videos watched said it." + tail
        case .commentary:
            return "Written from published guides, then checked against 6 videos watched on 14 November 2026. The music levels and the length of a cutaway come from them. Finished YouTube talking-head edits cut faster than a calm commentary, so the pace here is still the calm one, as written." + tail
        case .cinematic:
            return "Written from published guides, then checked against 6 videos watched on 14 November 2026. None gave a shot length or an ease time in seconds, so 6 cuts a minute and a 10 s shot are still judgement; the shape of a move, cutting on every second or fourth beat, and the fast opening come from them." + tail
        case .montage:
            return "Written from published guides, then checked against 3 montage videos watched on 14 November 2026. They confirm about 2.7 s per clip and line the kill up with the drop; nothing watched said what to hold back before a drop." + tail
        }
    }
}

extension ProjectDocument {
    /// The style a new edit in this project is cut in because of its genre, when one was chosen.
    public var genrePlaybook: EditorPlaybook? { genre?.playbook }
}
