## PULSE 1.6.0

Three releases in one: the **studio look** (1.5.0), the **instant replays and editing fixes** (1.4.0), and the
first batches from the 500-item roadmap (`docs/ROADMAP-500.md`), picked for impact. See
[1.5.0](../1.5.0/NOTES.md) and [1.4.0](../1.4.0/NOTES.md) for those two; what's new on top:

### Edit My VOD
- **Mic checks and sign-offs stay out** (#120, #121) — "can you hear me?", "mic check", "thanks for watching,
  raiding now" and the like are recognised from what's said; moments inside them only make the cut when they're
  genuinely strong.
- **Tighten** (#95) — a new toggle in Edit My VOD cuts the ums, uhs and false starts out of the story (off by
  default: word timing isn't perfect, so check the result).
- **Cuts never land inside a word** (#123) — the edit check now finds in/out points that chop a syllable; small
  ones are repaired by extending the piece to the end of the word (and rippling everything after it), the rest are
  listed for you. Crosstalk trims are left alone on purpose.

- **Dead air: Light / Normal / Tight** (#122) — a picker in Edit My VOD for how eagerly pauses are cut.
- **Music per chapter** (#100) — with Creative Commons music on, each chapter's bed is picked for that chapter's
  mood (a fight gets driving music, a story gets ambient), never the same track twice.
- **Title cards in your own words** (#125) — when a section's punchline is short ("CRAZIEST CLUTCH EVER!"), the
  card says that instead of a stock line.
- **Captions clear of cards** (#244) — caption words under a title card, meme or replay tag are hidden.
- **Outro in the chapter list** (#93), an **unbalanced-chapters note** (#113) and a **fast-captions note** (#251)
  in the edit check; repeated sound effects vary a touch in level so they don't sound copy-pasted (#284).

- **Your own meme pop-ups** (#103) — Settings → AI Features lets you set the text for each mood (fail, hype,
  funny…); leave one empty for PULSE's default.
- **Words to censor** (#44) — add your own to the caption filter.
- **Your own B-roll folder** (#131) — point Settings → Transcription → B-roll at a folder of meme / reaction clips
  and the B-roll extra cuts those in first (a file named after the mood — fail, hype, laugh — is picked for that
  mood); YouTube Creative Commons clips fill the rest.
- **Sections open on scene changes** (#31) — a section that starts within a second of a scene cut snaps to it, so
  chapters open on a fresh screen instead of mid-transition.

- **Music crossfades between chapters** (#101) — beds now sit on two music tracks (A2 / A2b) so one chapter's
  music overlaps the next for 3 s instead of fading out, a gap, and fading in.

### Editing
- **Hum removal** (#275) — a toggle in the audio inspector notches 50/60 Hz mains hum and its harmonics out of a
  clip, as part of the enhance chain.
- **J/K/L shuttle** (#157) — L plays 1×, then 2×, 4×, 8× on each press; J the same backwards (or a second back
  per press when the composition can't play in reverse); K stops.
- **Zoom In / Out / to Fit** in the Timeline menu (⌘= / ⌘- / ⇧Z) (#153).
- **Excitement strip** (#48) — the recording's energy drawn along the bottom of the ruler, mapped through your
  cuts, so you see where the heat is; toggle it in the toolbar.
- **Pacing graph** (#114) — cuts per minute, minute by minute, in the Coach, with the comfortable band shaded.
- **Inspector sections remember** whether you collapsed them (#228).
- **Nudge** (#155) — ⌥, / ⌥. move the selected clips a frame; add ⇧ for ten.
- **Type a time** (#200) — click the timecode in the transport bar, type 12:34 (or 1:02:03, or 12:34:15 for
  frames) and press return.
- **Markers list** (#160) — a toolbar button lists every marker and chapter: click to jump, rename, delete.
- **Timeline → Freeze Frame ⇧F** (#171) — hold the frame under the playhead for two seconds; the sound pauses with
  it and everything after moves along.
- **Timeline → Close All Gaps** (#162) ripples every black gap on the main track closed.
- **Low-confidence words** (#41) are dimmed and underlined in the Transcript panel, so they're easy to spot and fix.
- **One-click looks** (#306) — Clean / Punchy / Film / Cold / Warm in the Color section of the Inspector, each a
  gentle starting point you can tune.

### AI Clips
- **Game banners count as moments** (#27) — on gameplay, analysis reads the game's own VICTORY, ELIMINATED,
  DOUBLE KILL, YOU DIED and the like off the screen (on-device text recognition, about a minute per hour). Wins,
  multi-kills and deaths score higher, the clip is tagged Hype or Fail, and the card shows the banner. Settings →
  AI Features → Read game banners turns it off.
- **Rate from the keyboard** (#63) — K = 👍, J = 👎, ← → move between clips while the grid has focus.
- **Overlap warning** (#73) — a clip that covers mostly the same stretch as a short you've already edited says so.

### Delivery
- **Platform specs in the export panel** (#333) — each preset says what the platform does to the upload and
  flags a timeline over its length limit (Shorts and Reels 3 min, TikTok 10 min, X 2:20) or a bitrate below what
  survives the re-encode.
- **Software-encoder warning** (#334) — when the chosen codec has no hardware encoder on this Mac, the panel says
  so before you queue a slow export.
- **Description next to the video** (#336, #338) — every export writes a `.txt` beside the file with title ideas,
  the YouTube chapter list, music and clip credits and hashtags, ready to paste.
- **Exports are verified** (#350) — PULSE reopens the finished file and checks its length before calling the job
  done; a short or broken file is reported as failed instead of silently sitting in the queue.
- **An .srt beside the file** (#75, #246) when captions aren't burned in, for the platform's own subtitles.
- **A notification when an export finishes** (#341) while PULSE is in the background.
- **Quick Export ⌘E** (#359) — the current timeline straight into the queue with the project's last settings.

### Extras
- Extras that can't apply to this video (no facecam, not gameplay) are greyed out with the reason (#130), and each
  says roughly how long it adds (#129).

### Captions
- **Six highlight looks** (#232) — Classic, Boxed, Pop, Neon, Fill and Subtle, one click each in the captions
  workspace; the current one is lit.
- **Bleep or mute swear words** (#243) — Settings → AI Features → Audio under swear words makes every AI-built
  short and VOD edit mute or bleep the words the caption filter masks; the captions workspace has the same switch
  per timeline. It's rendered into the enhance cache; the source file is never touched.

### Everywhere
- **Shorts + YouTube video in one click** (#460) — a Home tile picks a recording (or a folder of them) and
  runs the whole pipeline: analysis, the best shorts, the YouTube edit with your saved extras, and the Mac stays
  awake until it's done.
- **Drop a folder** (#2) — the import panel, the drop zone and the overnight batch take folders and bring in
  their videos, audio and transcripts (one level, in name order).
- **"Clip it" while recording** (#318) — ⇧⌘M (or the HUD button) marks the moment; analysis treats marked
  moments as sure things, like a win banner. From the game too when macOS lets PULSE see keys (Input
  Monitoring).
- **Layouts that match what you stream** (#57) — after Set up for my stream, shorts with a facecam open in the
  split that suits the content: corner cam for shooters and battle royale, face-first for Just Chatting and IRL,
  half-and-half for variety and horror.
- **Reset any slider** (#206) — inspector sliders show a reset arrow while off their default, and double-clicking
  the label resets too (an animated value loses its keyframes).
- **Set up for my stream** (#441) — six questions (platform, content, facecam, mic, where shorts go, pace) set
  clip length, captions, extras, safe areas and the export preset in one go, with a list of exactly what changes.
  From the welcome screen, Home, Settings → General and the Help menu.
- **Disk check before analysis** (#387) — PULSE refuses to start an analysis the cache disk can't hold, and says
  how much to free.
- **What's new after an update** (#448) — a note on first launch after updating, and Help → What's New opens
  the release notes.
- **Actions in search** (#422) — ⌘F now also runs things: type "export", "edit my vod", "check", "gaps",
  "settings"… (fuzzy, so "qexp" finds Quick Export).

### Under the hood
- **Fuzz-tested timeline** (#396) — 1,000 random edit sequences (splits, ripples, freeze frames, source removals,
  gap closes, word-safe extensions, inserts) must leave no overlaps, no reads outside the file and linked
  video/audio in sync. It found and fixed two real bugs before you'd hit them.
- **Two-hour stream benchmark** (#394) — Edit My VOD with every extra on builds a 2-hour stream in about 5 s in a
  debug build; the test fails if that ever regresses.
