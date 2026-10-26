import Foundation

/// One tip a day on the Home page (#450). Short, true, and each about something people miss.
public enum HomeTips {
    public static let all: [String] = [
        "Press I and O on the timeline to set in and out points, then ⌥L loops them and ⌥⌘E exports just that stretch.",
        "⇧⌘M while recording marks a moment — analysis treats it as a sure thing, like a win banner.",
        "Set up for my stream (Home or Settings → General) sets clip length, captions, extras and safe areas in one go.",
        "Select several clips and change one value in the inspector — it applies to all of them.",
        "Timeline → Snapshots keeps a named copy of an edit; Make More Entertaining takes one by itself first.",
        "J, K and L shuttle playback: press L again for 2×, 4× and 8×.",
        "⌘F finds words, clips and actions: type “qexp” to Quick Export.",
        "Drop a whole folder of recordings onto PULSE — the overnight batch takes them all.",
        "The AI Clips card says why a moment was picked (“big laugh + chat spike”); the panel shows the signals.",
        "“20 % shorter” in the clip panel trims setup and tail by what's in them, never through a word.",
        "Edit My VOD → Shorten pauses plays 1–4 s pauses at 1.6× instead of cutting them.",
        "Captions → Style to all shorts gives every short in the project the same caption look.",
        "Settings → AI Features → Audio under swear words bleeps or mutes what the caption filter masks.",
        "Settings → Transcription → Custom vocabulary fixes names speech-to-text gets wrong (“valerant” → “Valorant”).",
        "⌥⌘C and ⌥⌘V copy and paste a clip's look and sound onto other clips.",
        "⌘T adds your default transition at the selected clips' edges, or on the cut under the playhead.",
        "The export panel says what each platform does to an upload and flags a video over its length limit.",
        "Audio only export turns an edit into an .m4a — the podcast version.",
        "Double-click a slider's label to reset it; click its number to type a value.",
        "Top 3 Shorts from This Edit (Edit My VOD menu) pulls the best shorts out of a finished YouTube edit.",
        "The de-esser in the audio inspector tames harsh s sounds; Warm, Clear and Radio are one-click EQ presets.",
        "Help → What's New shows the release notes for the version you're on.",
    ]

    /// The tip for a day: the same one all day, a different one tomorrow.
    public static func tip(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[((day % all.count) + all.count) % all.count]
    }
}
