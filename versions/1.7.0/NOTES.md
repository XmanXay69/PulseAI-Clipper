## PULSE 1.7.0

Two things on top of [1.6.3](../1.6.3/NOTES.md): the app takes on the look of BulkBoard, and the auto-editor
learns to cut in the styles working editors use.

### Design: the BulkBoard look
PULSE now shares one design language with [BulkBoard](https://github.com/XmanXay69/bulkboard). Every feature
is where it was; what changed is how it is drawn.
- **Tokens.** BulkBoard's surfaces (page `#161618`, sidebar `#1A1A1D`, cards `#1F1F22`, raised `#2A2A2E`),
  an 8 % hairline stroke, its text colours, and its two status colours used sparingly. The light theme takes
  BulkBoard's light values. Corners are continuous: 12 pt on cards and sheets, 10 on tiles, 7 on buttons,
  fields and rows.
- **One accent.** Blue by default (`#4C8DFF`, a deeper `#2563EB` on the light theme), with Pink, Violet,
  Lime and Amber in Settings → General → Appearance. What the AI made is marked with the accent and a
  sparkle, not a second colour. Lime and Amber carry over as chosen. "Pulse pink" (the old default)
  becomes Blue: pick Pink to get it back. "Electric blue" becomes Violet, since Blue is now the default.
- **Sidebar.** 216 pt wide with the mark, the app's name and the open project; a rounded selection with the
  icon in the accent; the ⌘-number shortcut shown on hover; "Runs on this Mac" at the foot (it changes when
  a cloud model is switched on). On the working pages it still folds to an icon rail.
- **Page headers.** Home, Projects, Import, AI Clips, Media, Templates, Exports and Settings open with a
  large title, one line of context (how many projects and where, how many clips and from what, what will be
  exported) and the page's own actions on the right. The strip above blends into the page and keeps the
  project's name, search, background tasks and where processing runs.
- **Cards.** Home is a dashboard: the two starting points, quick actions, recent projects, AI activity and
  storage with the free space as the figure. Exports is its settings and options as cards beside the queue.
  Settings groups are cards under sentence-case labels. Tags are quiet capsules; "On this Mac" replaces the
  green LOCAL pill and only cloud processing is called out.
- **Controls.** Buttons are drawn like the system's bordered ones: grey for most things, the accent filled
  for the one thing a screen is for, the accent tinted for AI actions, red tinted for what destroys. Every
  system segmented picker (38 of them) is replaced by the app's own, which follows the accent and sizes each
  segment to its label. The workflow bar along the bottom is one segmented control.
- **Mark.** The app icon and the sidebar mark are a graphite tile with a white pulse line and a blue play
  cue, in the same family as BulkBoard's mark.
- **Fixes along the way.** The mini viewer on AI Clips and Media is as wide as its picture instead of
  stretching across the window. Track headers are wide enough for "A1 Dialogue". Edit My VOD's footer no
  longer shortens its buttons to "Choos…". An AI Clips card drops a tag before it grows wider than its
  column, so cards line up with even gaps. Home's quick actions fit their words, and "Like a Reference"
  there and on AI Clips is now "Editing styles". A project's status sits on a dark pill over its thumbnail
  so it reads in both themes.
- **A freeze fixed.** Opening Media in a project with many audio files could stop everything PULSE does in
  the background, for good: analysis, exports, even its own timers. Each audio tile read its waveform on one
  of the few threads Swift keeps for background work, and with a reader parked on every one of them nothing
  was left to run the work the readers were waiting for. The window still responded, which hid it. Waveforms
  are now read on ordinary threads, two files at a time, and a read that goes 30 seconds without progress is
  given up on. CI's walk-through found it on a three-core runner: it now opens Media after the project has
  gained music and sound effects, names each step, and fails with a stack sample when it stalls.
- **Tests.** The engine tests that speak a sentence with the system voice now try three times and skip
  when a machine's voice makes no sound (a hosted runner's speech service sometimes isn't up yet); the
  release check speaks its sentence up to three times for the same reason.

### Editing styles
Six built-in styles the auto-editor can cut in, each written down from what editors and retention
strategists teach in public: **Retention cut** (gaming highlights), **Story first** (challenges, vlogs),
**Clean commentary** (podcasts, talking head), **Punchy short** (TikTok, Shorts, Reels), **Smooth and
cinematic** and **On the beat** (montages).
- **Where.** Edit My VOD opens with an **Editing style** menu: "PULSE's own" (as before) or one of the
  styles, with the one suggested for the open recording a click away. Picking a style sets the sheet's
  switches to what that style does, and they stay yours to change; your choice is remembered. Edit Like a
  Reference lists the styles above the drop zone, shows each one's principles in plain words and asks the
  same questions it asks about a studied video. The overnight batch can use a style too.
- **What a style is.** A fingerprint in the form a studied reference gets (cuts and zooms a minute, zoom
  strength, caption look, pop-ups, pause tightness, music, effects, fades, a fast opening), the pacing rules
  it lives by, and five principles. The existing editors turn the fingerprint into the edit.
- **How a zoom arrives.** Each style also says how fast a punch-in lands. Retention cut, Punchy short and
  On the beat snap in within a tenth to a sixth of a second. Clean commentary takes 0.4 s. Smooth and
  cinematic takes 0.6 s and eases in and out, so the move starts slow, travels and settles. Edit My VOD,
  shorts cut in a style and Make More Entertaining all use the style's figure.
- **The coach knows the rules.** New advice: a stretch with no cut, zoom or pop-up (held tighter in the
  opening, given twice the room on gameplay); no new section for minutes on a long video; sound effects
  piled up until none land; caption pages or lines too long to read at a glance; zooms that jump in on an edit cut in a style whose
  moves glide. An edit remembers the
  style it was cut in and is judged by that style's rules, so "Clean commentary" isn't told to cut faster.
- **What it is not.** Nothing here is a trained model. The styles are editing craft turned into numbers:
  a hook that lands early, something new before attention drifts, a reset every couple of minutes, effects
  kept for the moments that deserve them, moves that ease instead of snapping. The numbers come from
  published guidance, not from a study of any one creator's videos, and have run on the generated sample,
  not on hours of real streams. Treat them as starting points and say what feels wrong.

### Where the styles' rules come from
Read for this release and summarised in our own words; none of it is copied, and none of it is an
endorsement by the people named.
- Finzar, [The Real Secret to PRO Level Editing](https://finzar.substack.com/p/the-real-secret-to-pro-level-editing):
  smoothness first; graphics that ease on, zooms that glide, transitions that don't start abruptly. His
  [course outline](https://school.storezar.com/p/how-to-edit-using-premiere-pro-from-beginner-to-professional)
  names the same building blocks the styles are made of: keyframed zooms, subtitles, sound effects,
  background music and the voice. Only his written material was read; his videos were not watched.
- Vidpros on Mario Joos, [retention editing](https://vidpros.com/retention-editing-what-you-can-learn-from-mario-joos/):
  hook, then steadily arriving new information, then a payoff; pace is new information, not cut rate.
- AIR Media-Tech, [cutting patterns that keep viewers past minute 8](https://air.io/en/youtube-hacks/advanced-retention-editing-cutting-patterns-that-keep-viewers-past-minute-8):
  shot-change ranges by audience, a reset around 25–35 s, re-hooks every two to three minutes, music levels,
  big transitions saved for big moments.
- OpusClip, [what high-performing clips have in common](https://www.opus.pro/blog/video-editing-tips): captions
  on most clips, a word or two per beat, mixed case, above the platform's buttons; almost no intros.
- Walter Murch's Rule of Six, as taught in [this course note](https://cloud.wikis.utexas.edu/wiki/spaces/rtf318/pages/80022510/Murch+s+Rule+of+Six):
  a cut serves emotion first, then story, then rhythm.
- YouTube Help, [key moments for audience retention](https://support.google.com/youtube/answer/9314415): the
  first thirty seconds are the part to work on.
- Subtitle line-length and reading-speed conventions (about 42 characters a line, two lines, about 20
  characters a second), as used in streaming style guides.

### Also
- `docs/IDEAS-800.md`: 800 more ways to make PULSE better, numbered 501–1300 to continue the first roadmap,
  with the twenty to do first at the top.

### Checked
- Compiled and tested on GitHub's macOS 26 (Apple silicon) and macOS 15 (Intel) runners: 507 tests, no
  failures. 486 are core tests (eleven new for the styles and the coach, four for keeping blocking reads off
  Swift's background threads) and 21 run the engine end to end. On the Apple silicon runner the two engine
  tests that need the system voice were skipped because its voice made no sound; both ran and passed on Intel.
- Every page and sheet screenshotted on CI in the dark theme and reviewed. In the light theme: all ten pages,
  plus Edit My VOD, the editing styles sheet, search and onboarding. The README's screenshots are from that
  run. Sheets follow the app's theme instead of always opening dark.
- The freeze: the walk-through opens Media with eleven audio files and reports a waveform for all eleven
  within two seconds; before the fix it never got past that page.
- Not checked: the look on a real display at window sizes other than CI's 1440 × 900; the other sheets in the
  light theme (record, batch, thumbnails, publish); the styles on real recordings; the freeze fix on a real
  Mac with a large library. The Intel runner has no graphics device, so the walk-through and its screenshots
  come from Apple silicon only.
