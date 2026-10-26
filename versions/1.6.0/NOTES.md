## PULSE 1.6.0

The first batch from the 500-item roadmap (`docs/ROADMAP-500.md`), picked for impact:

### Edit My VOD
- **Mic checks and sign-offs stay out** (#120, #121) — "can you hear me?", "mic check", "thanks for watching,
  raiding now" and the like are recognised from what's said; moments inside them only make the cut when they're
  genuinely strong.
- **Tighten** (#95) — a new toggle in Edit My VOD cuts the ums, uhs and false starts out of the story (off by
  default: word timing isn't perfect, so check the result).
- **Cuts never land inside a word** (#123) — the edit check now finds in/out points that chop a syllable; small
  ones are repaired by extending the piece to the end of the word (and rippling everything after it), the rest are
  listed for you. Crosstalk trims are left alone on purpose.

### Editing
- **Timeline → Close All Gaps** (#162) ripples every black gap on the main track closed.
- **One-click looks** (#306) — Clean / Punchy / Film / Cold / Warm in the Color section of the Inspector, each a
  gentle starting point you can tune.

### Delivery
- **Description next to the video** (#336, #338) — every export writes a `.txt` beside the file with title ideas,
  the YouTube chapter list, music and clip credits and hashtags, ready to paste.
- **Exports are verified** (#350) — PULSE reopens the finished file and checks its length before calling the job
  done; a short or broken file is reported as failed instead of silently sitting in the queue.
- **Quick Export ⌘E** (#359) — the current timeline straight into the queue with the project's last settings.

### Everywhere
- **Actions in search** (#422) — ⌘F now also runs things: type "export", "edit my vod", "check", "gaps",
  "settings"… (fuzzy, so "qexp" finds Quick Export).
