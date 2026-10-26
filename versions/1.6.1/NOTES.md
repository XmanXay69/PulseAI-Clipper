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

### Batch 17

#### Edit My VOD
- **Cuts land on sentence ends** (#97) — the edit check now notices a cut that stops mid-sentence; when the
  sentence ends within 1.5 s the piece is extended to it (and what follows ripples), otherwise it's noted, not
  changed — pace is a choice. Splits and pauses taken out of a sentence are left alone.
- **Drop the music here** (#288) — Timeline → Add Music Drop Marker puts a "Drop" marker at the playhead;
  Apply Music Drops pulls the music out for a beat at every one. Any marker you name "Drop…" counts.
- **Progress bar** (#92) — a thin accent-coloured bar along the bottom that fills as the video plays: a toggle
  in the Edit My VOD sheet, or Timeline → Add Progress Bar on any edit of 10 s or more.
- **Whoosh on the hook** (#77) — AI Features → One-click shorts: a quiet whoosh under the first words of every
  short, from the project's sounds or the built-in library.

#### Captions
- **Spelling** (#242) — a Spelling button in the caption style panel lists the words the system dictionary
  doesn't know, each with up to three fixes; names you taught PULSE, speaker names, GG / LOL / HP, numbers and
  emoji are never flagged. Learn adds a word to your vocabulary for good.

#### Delivery
- **Queue time** (#340) — the Exports page says how long the whole queue will take, from the running job's
  own estimate and the average of the ones already done.
- **Export into a synced folder** (#356) — next to Choose…, a cloud button lists iCloud Drive, Dropbox, Google
  Drive, OneDrive and Box when they're set up on this Mac; one click points exports at a PULSE Exports folder
  inside.

#### Everywhere
- **Command palette** (#459) — ⌥⌘P (or ⌘F as before): actions now match loosely — "qexp" finds Quick Export,
  and real substrings and word starts rank first.
- **Reduce motion** (#426) — with the system's Reduce Motion on, PULSE's hover lifts, scroll-to-word
  animations, toast springs and the recording pulse all go still.
- **Quicker launch** (#376) — the update check waits six seconds after the first window, instead of competing
  with it.
- **Safe mode** (#393) — Help → Use Safe Mode (CPU Rendering) for a Mac whose GPU driver misbehaves; the
  viewer and exports render on the CPU from the next edit you open.
- **Open in Default App** (#21) in the media panel's right-click menu, beside Reveal in Finder.

#### Already there, now on the list
- The Inspector's Removed Sections lists every cut stretch with its reason and a Restore button (#87); Edit →
  Edit My VOD Again makes it 10 % shorter or longer with the same answers (#115, #117); Timeline → Make a Short
  from Selection promotes a stretch of the YouTube edit to a short (#119); the edit check adds 30 ms cut fades
  to your own cuts as well as PULSE's (#274); Highlights, Shadows and Vignette have been in the Color section
  all along (#312, #313); frame stepping is frame-accurate (#186), safe areas have per-platform overlays (#189)
  and captions have max-lines and max-characters controls (#235).

### Batch 18

#### Media
- **Moved files find themselves** (#6) — when a project opens with missing media, PULSE looks where the
  file used to be, one folder up, beside the project and in the last import folder, and relinks what it finds.
- **Relink all at once** (#7) — a "Relink N Missing…" button in the media panel: pick the folder the files
  moved to and every missing file inside it is reconnected by name (and by size when names repeat).
- **Sidecars come along** (#13, #14) — import a recording and the `.srt` / `.vtt` with the same name beside
  it becomes its transcript (no transcription needed), and a `<name>.json` / `<name>-chat.json` beside it is
  taken as the chat replay.

#### Editing
- **Replace a clip by dropping on it** (#164) — drop a media item from the panel onto a clip: the clip keeps
  its place and length and the file behind it changes; its linked sound follows (or goes, for a silent file).
- **Insert or overwrite** (#163) — a toolbar toggle: in insert mode, media you add pushes what follows along
  instead of covering it.
- **Blade preview** (#146) — with the blade tool, a line follows the mouse where the cut will land.
- **Link badge** (#173) — clips linked to a sound piece show a small link mark in their name chip.

#### AI Clips
- **Cold-open card** (#90) — shorts that open cold get a quick line over the teaser — "WAIT FOR IT", "OH
  NO…", "WATCH THIS", "GUESS WHAT HAPPENED" — chosen from the moment's tags.
- **Your sounds** (#105) — AI Features → One-click shorts: pick which impact lands on the payoff and which
  whoosh PULSE uses for hooks, replays and cutaways; the YouTube edit uses the same choices.

#### Projects
- **Status board** (#474) — Projects gets a board view: Editing, Ready, Exported and Posted columns; drag a
  card between them. A project you haven't placed sits where its contents put it.

#### Already there, now on the list
- Analysis resumes from its last checkpoint after a crash, transcription included (#36); the first analysis
  calibrates the time estimates for your Mac (#55); with a second feed, multicam's AI switching cuts to whoever
  is talking (#98); ProRes 422 is an export preset (#345); the reference style card shows the measured stats
  (#365); striking words in the Transcript panel cuts them from the edit (#499).

### Batch 19

#### Editing
- **Slip, slide and roll** (#143) — Timeline → Trim Modes: slip moves what plays inside the selected clip
  (⌃, ⌃.), slide moves the clip between its neighbours while they give or take the room (⌃⌥, ⌃⌥.), roll moves
  the cut after it (⌃⇧, ⌃⇧.); ten-frame versions in the menu. Linked sound follows, and nothing else moves.
- **Levels drawn on the clip** (#151, #269, #270) — audio clips with a volume curve (ducking, music drops)
  show it as a line over the waveform, keyframes as dots.
- **Chapter band** (#418) — the ruler shows a band from each chapter marker to the next, with its name when
  there's room.

#### Captions
- **Hear the word** (#257) — double-click a word to retype it and PULSE plays that word.

#### Delivery
- **Preview 10 s** (#360) — encodes ten seconds from the in point with the real settings into a temporary file
  and opens it, so bitrate artifacts show before the full export.

#### Viewer
- **Platform buttons and caption** (#67) — the safe-area menu can draw the feed's own chrome: tabs, the
  like/comment/share column, the username and caption lines, the sound ticker and the bottom bar.

#### Recording
- **Setups and size** (#319) — Game + cam, Podcast and Screencast presets, a codec choice, and "about 2.8 GB
  an hour" for the chosen screen, frame rate and codec.

#### Everywhere
- **Transcription time per model** (#38) — each whisper model in Settings says roughly how many minutes it
  needs per hour of video on this Mac, from what PULSE has measured.
- **Delete a model** (#442) — downloaded models can be removed again from Settings → Transcription.
- **Offline** (#300) — the Sounds panel says when there's no connection; everything built in keeps working.
- **After a crash** (#383) — when PULSE didn't quit cleanly, the next launch offers Report a Problem with
  that session's log already bundled.
- **Caption look on each clip card** (#61, #249) — the AI Clips cards name the caption look a short will get.

#### Already there, now on the list
- Music downloads retry each piece three times (#302); the playhead has its glow (#417); the clip cards'
  potential ring (#437).

### Batch 20

#### Editing
- **Rubber-band selection** (#147) — drag on empty timeline across any tracks to select every clip the band
  touches; ⇧ adds to what's selected.
- **Compound clips on hover** (#166) — Open and Flatten buttons appear on the clip itself.
- **Timecode while scrubbing** (#417) — dragging the ruler shows the exact timecode in a bubble by the playhead.

#### Delivery
- **Frame rate** (#349) — Match source, 24, 30 or 60 in the export panel.
- **Low priority** (#342) — a checkbox that renders in the background so the timeline and viewer stay smooth;
  slower, but you keep working.

#### Recording
- **Menu bar status** (#321) — a red dot with the elapsed time in the menu bar while recording, with Stop and
  Pause in its menu; orange while paused.

#### Everywhere
- **Energy search** (#285) — the music library answers "calm", "steady" and "driving", worked out from each
  track's tempo.
- **Performance log** (#395) — PULSE keeps how long its last 200 jobs took; Report a Problem bundles it as
  `performance.txt` (job titles and seconds, nothing else).
- **Brand Kit preview** (#372) — Settings → Brand Kit → Preview… builds the sample project's short with your
  kit on it and opens it.
- **Tasks with timings** (#399) — the Background Tasks list shows how long each task has been running and a
  Cancel on each.

#### Already there, now on the list
- A Test button checks the cloud provider from Settings (#453); the viewer's full-screen button (#195).

### Batch 21

- **Snap lines** (#144) — while a clip is dragged, the edge it locks onto shows as a line across the timeline.
- **B-roll tray** (#132) — a toolbar menu lists every cutaway a build placed: go there, remove it, or swap in
  another clip from the project.
- **Facecam confidence** (#45) — the Layout section says how often the analysis found the facecam and how much
  of the picture it covers; the canvas handles override it.

#### Already there, now on the list
- Gameplay that can't be cropped gets a blurred fill or bars (#78, Canvas → Background blur); filmstrips on
  video clips (#141); the breadcrumb inside a compound (#184); viewer zoom 50 / 100 / 200 % (#188, #202); effects
  can be bypassed one by one (#212) and include blur, sharpen, glow, vignette and grain (#213); a clip can be
  AI-reframed from its inspector (#222); paste attributes by section (#223); `.cube` LUTs with an amount (#309);
  the export queue keeps rendering after the project closes (#355); the studio look's elevation system, grouped
  sidebar, breadcrumb, hero, hover states, empty states and track stripes (#402, #404–#407, #410, #416).

### Under the hood
- `CaptionWord.pageBreakAfter` and `TimelineClip.labelColor` are decoded tolerantly, so 1.6.0 projects open
  unchanged; `Batch16Tests` covers the release-list parser, caption keyboard edits, the bumper's ripple, the
  pace mapping, the monitoring note, labels, humanized levels and 1,000 frame steps at 29.97.
- `Batch17Tests` covers mid-sentence detection (and the splits and pause removals it must ignore), drop
  markers, the progress bar's keyframes, the hook sting, fuzzy ranking, cloud-folder detection and the spelling
  candidates. `Batch18Tests` covers relink matching, import sidecars, clip replacement, the cold-open card,
  preferred sounds and the board's stages. `Batch19Tests` covers slip, slide and roll (linked sound,
  clamping, nothing else moving), the recording size model and the per-model transcription time.
  `Batch20Tests` covers energy search, the low-priority flag and the performance log's ring buffer; 345 core
  tests in all.
