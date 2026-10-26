## PULSE 1.6.1

The sixteenth batch from the 500-item roadmap (`docs/ROADMAP-500.md`), on top of [1.6.0](../1.6.0/NOTES.md):

### Editing
- **Colour labels on clips** (#177) — the Inspector's Clip section has eight label dots; the timeline draws
  the label as a stripe on the clip's left edge, and the new tag button in the timeline toolbar shows only one
  label (everything else dims) or selects every clip that carries it.
- **Frame-locked stepping** (#178) — ← → always land on a frame start, so a hundred steps at 29.97 are a
  hundred frames: no drift between the playhead and the picture.

### Captions
- **Keyboard editing** (#256) — in Caption Text: tab / ⇧tab move between words, return starts a new caption
  page after the word (again to undo; a small ↵ marks it), ⌫ merges the word into the one before it ("Mc" +
  "Donald"), space seeks to it. Page breaks are kept in the project and honoured when captions render.

### Edit My VOD
- **Intro card** (#373) — Brand Kit → Intro & outro: with no intro clip, a name in the Intro card field adds a
  3-second slate at the start of every YouTube edit: your name slides up, your handle fades in under it, then a
  fade into the first shot. Taken out again like the intro clip when the kit is re-applied.
- **Music that keeps up** (#102) — the Creative Commons search asks for upbeat beds under a fast-cut edit (12+
  cuts a minute) and slower ones under a slow one (under 4); the library shelves them by pace.
- **Sound effects that don't sound copy-pasted** (#284) — every whoosh and sting in a built edit gets its own
  level within ±5 %, the same on every rebuild of the same recording.

### Everywhere
- **Accent colour** (#425) — Settings → General → Appearance: Pulse pink, Electric blue, Lime or Amber.
  AI features keep their violet whichever you pick.
- **Update channel** (#454) — Settings → General → Help: Stable, or Beta to get pre-releases a week or two
  early. The update sheet now lists everything since the version you have, not just the newest release.
- **Monitoring note** (#283) — Settings → General → Editing says what the Mac is playing through and warns
  when it's a poor place to judge a mix: laptop speakers (no bass, no sibilance), Bluetooth (sound 0.1–0.3 s
  behind the picture), HDMI/TV speakers, AirPlay.
- **Accessibility** (#458) — every toolbar icon button, settings control and colour dot has a VoiceOver label
  (the help text without the shortcut), and the active state is read as selected.

### Under the hood
- `CaptionWord.pageBreakAfter` and `TimelineClip.labelColor` are decoded tolerantly, so 1.6.0 projects open
  unchanged; `Batch16Tests` covers the release-list parser, caption keyboard edits, the bumper's ripple, the
  pace mapping, the monitoring note, labels, humanized levels and 1,000 frame steps at 29.97.
