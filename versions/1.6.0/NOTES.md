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

### Editing
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
- **Rate from the keyboard** (#63) — K = 👍, J = 👎, ← → move between clips while the grid has focus.
- **Overlap warning** (#73) — a clip that covers mostly the same stretch as a short you've already edited says so.

### Delivery
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

### Everywhere
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
