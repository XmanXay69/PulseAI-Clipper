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

    /// Something that was read for this genre's rules.
    public struct Source: Hashable, Sendable {
        public var title: String
        public var url: String
        /// What it contributed, in a few words.
        public var gave: String
    }

    /// Where this genre's rules were read. Written guides and breakdowns only: see `studyNote`.
    public var sources: [Source] {
        let retention = Source(title: "Vidpros on Mario Joos: retention editing", url: "https://vidpros.com/retention-editing-what-you-can-learn-from-mario-joos/",
                               gave: "hook, then steadily arriving new information, then a payoff")
        let patterns = Source(title: "AIR Media-Tech: cutting patterns that keep viewers past minute 8",
                              url: "https://air.io/en/youtube-hacks/advanced-retention-editing-cutting-patterns-that-keep-viewers-past-minute-8",
                              gave: "a reset around every half minute, a re-hook every two to three minutes")
        let rhythm = Source(title: "StudioBinder: how an editor controls the rhythm of a film",
                            url: "https://www.studiobinder.com/blog/how-does-an-editor-control-the-rhythm-of-a-film/",
                            gave: "shot length as the lever: shorter shots raise tension, longer ones release it; feelings take time")
        switch self {
        case .streamHighlights:
            return [Source(title: "Nicole Rojas: edit Twitch streams for YouTube", url: "https://thenicolerojas.com/en/guides/edit-twitch-streams-for-youtube/",
                           gave: "cut whatever drags; find moments by the loud parts; captions and memes are for the short clips"),
                    Source(title: "Creator Handbook: how Neebs Gaming edits videos to make them funnier",
                           url: "https://www.creatorhandbook.net/how-neebs-gaming-edits-videos-to-make-them-funnier-and-how-you-can-too/",
                           gave: "cut the dead space so the joke lands; a bit that runs long is cut where it should have ended"),
                    patterns]
        case .gamingVideo:
            return [Source(title: "Finzar: The Real Secret to PRO Level Editing", url: "https://finzar.substack.com/p/the-real-secret-to-pro-level-editing",
                           gave: "smoothness: nothing snaps on, zooms don't jolt, transitions don't start abruptly"),
                    Source(title: "Creator Handbook: how Neebs Gaming edits videos to make them funnier",
                           url: "https://www.creatorhandbook.net/how-neebs-gaming-edits-videos-to-make-them-funnier-and-how-you-can-too/",
                           gave: "timing first; a zoom on what the player missed; a freeze, a sting or the wrong music for the joke"),
                    retention, patterns]
        case .challenge:
            return [retention, patterns,
                    Source(title: "Murch's Rule of Six (course note)", url: "https://cloud.wikis.utexas.edu/wiki/spaces/rtf318/pages/80022510/Murch+s+Rule+of+Six",
                           gave: "a cut serves emotion first, then story, then rhythm")]
        case .vlog:
            return [Source(title: "Artlist: the editing and storytelling techniques in Casey Neistat's videos",
                           url: "https://artlist.io/blog/editing-storytelling-techniques-casey-neistat/",
                           gave: "leaving mid-sentence, finishing a thought in the next place, quick-cut montages of a task"),
                    Source(title: "No Film School: seven storytelling techniques from Casey Neistat",
                           url: "https://nofilmschool.com/2016/08/7-storytelling-techniques-you-can-learn-filmmaker-youtube-star-casey-neistat",
                           gave: "the same seven techniques, from the editor who broke them down"),
                    retention]
        case .commentary:
            return [Source(title: "OpusClip: what high-performing clips have in common", url: "https://www.opus.pro/blog/video-editing-tips",
                           gave: "captions on, short lines, no intro"),
                    Source(title: "PremiumBeat: nine essential cuts", url: "https://www.premiumbeat.com/blog/9-essential-video-editing-cuts",
                           gave: "the jump cut needs something to tie it together; the L-cut shows a listener without leaving the speaker"),
                    rhythm]
        case .cinematic:
            return [rhythm,
                    Source(title: "PremiumBeat: nine essential cuts", url: "https://www.premiumbeat.com/blog/9-essential-video-editing-cuts",
                           gave: "cutting on action, match cuts, montage for time passing"),
                    Source(title: "Finzar: The Real Secret to PRO Level Editing", url: "https://finzar.substack.com/p/the-real-secret-to-pro-level-editing",
                           gave: "moves shaped on the speed graph so they start slow, travel and settle")]
        case .montage:
            return [Source(title: "Eklipse: how to make a gaming montage", url: "https://blog.eklipse.gg/beginner-guide-2/how-to-make-gaming-montage.html",
                           gave: "music first, cuts on the strong beats, the best fifteen to twenty-five clips a few seconds each"),
                    Source(title: "CapCut: matching cut speed to music", url: "https://www.capcut.com/create/music-video-pacing-emotional-montage-rhythm",
                           gave: "hold longer before the drop, one bold change on it")]
        }
    }

    /// How the rules were arrived at, said plainly wherever they are shown.
    public static let studyNote = "These rules were written from published guides and editors' own breakdowns, not learned by watching videos. They are starting points: change any switch below."
}

extension ProjectDocument {
    /// The style a new edit in this project is cut in because of its genre, when one was chosen.
    public var genrePlaybook: EditorPlaybook? { genre?.playbook }
}
