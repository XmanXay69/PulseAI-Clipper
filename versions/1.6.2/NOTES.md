## PULSE 1.6.2

Batch 23 from the 500-item roadmap (`docs/ROADMAP-500.md`), on top of [1.6.1](../1.6.1/NOTES.md):

### Delivery
- **Chapter art** (#493) — Timeline → Export Chapter Art… saves a 1280×720 picture per chapter marker: the
  frame at that moment with the chapter's name set over it, for the description and the end screen.

### Media
- **List view** (#18) — the media panel can show a table with Name, Length, Size, Imported and Role columns;
  click a column to sort, double-click a row to add it to the timeline.

### Everywhere
- **GPU self-test** (#392) — at launch PULSE renders one frame through the GPU; when that fails it switches to
  safe mode (CPU rendering) on its own and says so.
- **Shuttle speed** (#420) — the transport bar shows the J/K/L speed while you shuttle.

### Batch 24

#### Viewer & playback
- **Viewer quality** (#187) — Full / ½ / ¼ render size from the viewer header or Settings → Proxies & Playback.
  With "drop a step when playback stutters" on, PULSE watches whether playback keeps up with the clock and
  steps the viewer down on its own, says so, and marks the pill "auto". Exports always render in full.
- **Viewer in a separate window** (#205) — Window → Viewer in Separate Window (⌥⇧⌘V) puts the picture and
  transport on a second monitor, driven by the same player so it never drifts.
- **Frame-step tick** (#198) — an optional soft click on every ← / → step (Settings → General).

#### Audio
- **Fade shapes** (#169) — Linear, Equal power or Smooth per clip; equal power keeps a crossfade at one
  loudness through the middle instead of dipping.
- **Keep pitch at this speed** (#170) — slowed or sped-up clips keep the voice's pitch by default; off gives
  tape-style varispeed.
- **Audio quality in plain words** (#347) — the export sheet offers Voice / Standard / High / Studio / Maximum
  with a line on what each is for.
- **Waveforms follow the gain** (#150) — a louder clip draws a taller wave, a muted one a flat line.
- **Seamless music loops** (#294) — PULSE looks for the two points in a bed where the sound matches and loops
  between them, so a 90-second track tiles under a 20-minute edit without the restart bump.

#### Colour
- **Grain** (#315) — amount and size, soft-lit over the midtones.
- **Protect skin tones** (#308) — saturation boosts go through vibrance so faces stay natural.
- **Crop aspect readout** (#227) — the Crop section shows the ratio and pixel size of the crop as you drag.

#### Media & import
- **Import presets** (#25) — Twitch VOD, OBS recording or Podcast (Settings → General) settle roles and whether a
  batch is synced as one session, instead of guessing from the file names alone.
- **Thumbnails survive a move** (#398) — thumbnails and waveforms are keyed by the file's content hash, so a
  relinked or renamed recording keeps its filmstrips.
- **Memory ceiling** (#377) — Settings → Performance → Memory sets how much decoded frame cache PULSE keeps,
  shows what it's using right now, and PULSE empties the cache itself on a system memory warning.

### Batch 25

- **No black flash** (#204) — while the timeline rebuilds the viewer keeps the last picture, dimmed, until the
  new composition is ready.
- **Proxies from the viewer** (#382) — the quality menu has the proxy switch and the pill says "proxy" when
  they're in use.
- **Track rename, reorder and colour** (#149) — double-click a track name to rename it; the header menu moves a
  track up or down and gives it a colour label.
- **Keyframe sparklines** (#211) — an animated property shows its curve beside the slider, with the playhead on it.
- **Beat grid** (#287) — music clips show a tick per beat once PULSE knows the track's beats: after a
  beat-synced Edit My VOD, or from the clip menu's Detect Beats.
- **Sound packs** (#298) — Cinematic, Punchy, Soft or Retro switch the payoff hit and the whoosh as a family
  (Settings → AI Features); the rows below still fine-tune each.
- **Thumbnail after export** (#357) — with the setting on and Thumbnail Studio installed, every finished export
  sends a design for that edit to the studio.
- **A/B thumbnail pairs** (#375) — the thumbnail sheet can save two moments in one layout as "… A" and "… B".

### Batch 26

- **Chroma key** (#221) — Inspector → Chroma Key: green or blue screen (or any hue) goes transparent, with
  tolerance, softness, spill removal and a floor so hair and shadows stay.
- **Feathered masks** (#220) — a soft edge on any mask shape, for a circle facecam that fades into the game.
- **Scopes** (#310) — a luma waveform and a vectorscope of the frame in the viewer (header button), with a
  clipping readout.
- **Match grade** (#311) — Inspector → Colour → Match grade to previous clip: exposure, saturation and
  temperature set so the two clips' average look lines up (the webcam from two days).
- **Brand logo on an export** (#353) — the export sheet burns the Brand Kit logo into that export, in the kit's
  corner, size and opacity (#369).
- **Captions never clip** (#234) — a page wider than the safe width shrinks its type to fit.
- **Media cards say "Preparing preview…"** (#15) while a thumbnail decodes instead of sitting blank.

### Batch 27

- **Reverse clip** (#172) — the clip menu renders a reversed copy of a video clip (up to 60 s) as new project
  media and swaps it in, audio muted.
- **Speaker chips** (#252) — speaker names above captions as a lower-third chip in the highlight colour, or
  plain small caps (Captions → Style → Speaker).
- **Frosted captions** (#253) — the caption box can blur the picture behind the words instead of a solid colour.
- **Auto white balance** (#307) — a per-layer grey-world correction for the facecam that leaves the game alone.
- **Sound effect variations** (#305) — every effect in the Sounds panel comes in −5 / −2 / +2 / +5 semitone
  versions generated from the one sample.
- **One system dot** (#421) — the top bar's LOCAL / CLOUD pill is now one quiet indicator whose popover lists
  processing location, memory, GPU mode and network; the save state is a dot you can hover (#405).

### Batch 28

- **Transparent exports** (#346) — Apple ProRes 4444 with a transparent background keeps the alpha channel,
  for overlays and stingers that go on top of something else.
- **True peak** (#280) — the loudness check reports the inter-sample peak in dBTP next to the LUFS figure.
- **Hear it first** (#261) — Inspector → Audio → Enhance → "Hear 10 s raw vs processed" plays both and a switch
  picks which one you hear, before the setting is committed.
- **Audio scrub** (#156) — a blip of sound where the playhead lands while dragging (Settings → General).
- **Track height** (#148) — Small / Medium / Large from Settings → General or any track header's menu.
- **Project settings** (#445) — File → Project Settings… pins the export preset, target platform, loudness target
  and caption look for one project while everything else follows Settings.
- **Inspector and transcript in their own windows** (#429) — Window → … in Separate Window (⌥⇧⌘I / ⌥⇧⌘T).
- **"= EXPORT" badge** (#197) — the viewer says it runs the export's renderer, so what you see is what ships.

### Batch 29

- **Your own shortcuts** (#431) — Settings → Shortcuts → Customize changes the key for twenty menu commands;
  clashes with another command or a standard Mac shortcut show in amber, and the menus pick the change up at once.
- **Trim two-up** (#142) — while a trim handle drags, the frame on each side of the new cut floats by the handle.
- **Conform frame rate** (#24) — a variable-frame-rate recording re-encodes at a constant rate from the media
  panel; the project points at the new file, the original stays put.
- **Open with PULSE** (#466) — videos and audio files open with PULSE from the Finder or the Dock: into the open
  project, or waiting for the next one.
- **Recently changed** (#423) — Settings → General lists what you've touched this session.
- **Font picker with previews and recents** (#215) — every font shows in itself; the last six you picked sit
  at the top.
- **Focus rings** (#408) — keyboard focus on icon buttons draws in the accent colour.

### Batch 30

- **Speed Edit** (#500) — ⌃⇧E (or the bolt in the timeline toolbar) turns the editor into a keyboard pass over
  the recording's moments: N / P jump between them with in → out set around each, I / O re-mark, X makes a
  short, D dismisses, return exports in → out, J K L shuttle, escape leaves. A whole VOD in minutes.
- **Transition handles** (#167) — drag the inner edge of a transition's wedge to change its length.
- **Live level while recording** (#323) — a small meter in the recording strip, amber over −12 dBFS and red
  when the microphone clips.

### Batch 31

- **Storyboard in your order** (#109) — the arrows on a storyboard row move a moment earlier or later; the edit
  then keeps that order instead of the recording's, so a payoff can open the video. Rows show the moment's
  waveform with the payoff marked (#438).
- **Predicted retention** (#490) — a line along the ruler guesses where viewers leave, from the recording's
  energy and your cuts; red where it falls fastest.
- **Text templates and a live look** (#217, #214) — the text inspector shows the layer as the renderer draws
  it and applies Lower third, Callout, Meme, Big title or Subtitle looks; Save Look keeps yours.
- **Where the drop is** (#293) — a previewed sound shows its waveform with the drop marked.
- **Sharpening waits for the export** (#314) — proxy or reduced-size playback skips it, so the viewer doesn't
  show halos the file won't have.

### Batch 32

- **Light theme** (#424) — Settings → General → Appearance: Dark, Light or Match macOS. Every surface, border
  and text colour has a paper-white counterpart; the viewer and timeline stay as they were.
- **Word pop** (#216) — a text animation where each word lands on its own, one after the other.
- **Shape layers** (#218) — Timeline → Add Shape: rectangle, circle, a highlight ring to point at things, or a
  line; they take the same colour, mask, border and shadow controls as any layer.
- **Brand kit per platform** (#371) — Settings → Brand Kit → Per platform: a different corner or size for the
  logo on TikTok, Shorts, Reels or YouTube, or no logo at all; new shorts resolve the kit for their platform.

### Batch 33

- **Keyframe lane** (#152) — a selected clip with keyframes shows them as diamonds along its bottom edge:
  click one to jump there, drag it to retime it.
- **Rotation on the canvas** (#191) — a knob above the selection box rotates the layer; ⇧ snaps to 15°,
  double-click resets.
- **Looping storyboard previews** (#112) — rest the mouse on a storyboard thumbnail and the moment loops.
- **Colour-matched angles** (#326) — the multicam inspector matches every angle to the first one's look.
- **Two people in frame** (#487) — face-aware reframing centres between two faces of comparable size when
  both fit in the crop, instead of flipping between them.
- **Help where you are** (#433) — small "?" chips next to loudness, enhance, chroma key and Speed Edit open a
  paragraph on what the thing does.

### Batch 34

- **Crop tool on the canvas** (#192) — the crop button in the viewer's strip turns the selection box into a
  crop: drag the picture to pan it inside its frame, drag the corner to zoom into it, double-click to show
  all of it again. Keyframed zoom and pan get a keyframe at the playhead, like the other handles.
- **Mini viewer** (#196) — on the AI Clips and Media pages the edit keeps playing in a small floating
  viewer: click to play or pause, drag it anywhere, the arrow opens the editor. View → Mini Viewer hides it.
- **Edit the caption on screen** (#231) — the text-cursor button in the viewer's strip opens the caption
  page under the playhead as text fields; retype a word and press Return.
- **Levelled audio under the playhead first** (#289) — the background enhance renders go in play order
  from the playhead, not timeline order, so what you're hearing is the first to switch over.
- **Multicam switching sensitivity** (#327) — a Patient … Eager slider in the Angles panel sets how long
  shots are and how clear a change of speaker has to be before AI Switch cuts; "Cut on the beat" moves each
  switch onto the nearest beat once Detect Beats has run on an angle.
- **Edit like my last videos** (#489) — every export leaves a fingerprint of how it was cut (pace, zooms,
  captions, music, effects, fades); the Reference sheet offers the average of your last ten as a style to
  edit the next one the same way. Nothing leaves your Mac.

### Batch 35

- **Meters** (#194, #281) — a mix-bus meter next to the transport with peak hold and a clip light that
  stays lit until you click it, and a small meter in every audio track's header. They read the cached
  waveforms through each clip's volume, gain, mute and solo, so they cost nothing while playing.
- **Voice ◀ ▶ Game** (#267) — when the microphone and the game are on separate tracks, the timeline
  inspector gets one slider that turns the game down behind your voice (or the other way round), up to 12 dB.
- **Room tone** (#273) — Timeline → Fill Gaps with Room Tone puts the recording's own quietest moment,
  6 dB down with short fades, into every short silence between audio clips, so cuts stop dropping to nothing.
- **Instrumental stems** (#295) — a "Song (Instrumental)" next to "Song" in your media goes under the talking
  when Edit My VOD picks music.
- **Shortcuts in every tooltip** (#229, #430) — icon buttons show their key in one format, taken from your
  own shortcut map, so a remapped Split reads right in its tooltip too.
- **Face guide** (#324) — the Record sheet shows the chosen webcam live with an oval and an eye line to sit
  in before you press record.

### Batch 36

- **Ask PULSE** (#498) — a speech-bubble button on the timeline toolbar takes plain English: "cut the first
  10 seconds", "make the hook punchier", "tighten the pauses", "make it 20 % shorter", "captions like
  TikTok", "turn the music down", "fewer zooms", "add a progress bar", "speed up 1.5×", "fill the gaps with
  room tone", "undo". Each request becomes one ordinary undo step. It's rules, not a model — nothing is
  uploaded and nothing needs downloading.
- **Render load on the ruler** (#183) — a gauge button draws a thin bar along the ruler: green where a frame
  is cheap, red where chroma keys, blurs, glows and stacked layers may stutter at full viewer quality.
- **Caption gallery that moves** (#233) — rest the mouse over the caption presets and every swatch plays its
  highlight through three words, scale and box included.
- **Game + Cam multicam** (#328) — a multicam session with a gameplay angle offers a picture-in-picture
  edit: the game stays full-frame and whoever is talking sits small in a rounded, bordered corner, switching
  with the AI cuts.

#### Already there, now on the list
- Chat bursts count toward every moment's score once a chat replay is attached (#26); the media grid and the
  timeline are virtualized (#386); when whisper.cpp isn't there, Apple's on-device speech takes over (#400);
  the viewer's strip shows the format, resolution and frame rate (#419); replays get a sting and a slightly
  desaturated look you can switch off (#137) and title cards draw on your own phrase list (#138), both in the
  Extras controls; each multicam cut is its own undo step (#329); waveforms are generated at low priority in the
  background on import (#381); the Edit / Captions / Colour / Audio / Deliver workspaces each remember their own
  panel sizes (#427, #428); ⇧⌘M marks a moment from any app while recording once Input Monitoring is allowed
  (#464); window recording with the window's title is in the recording sources (#332); image overlays take the same
  masks and shadows as any layer (#219); the composition builds off the main thread with cancellation (#379);
  icon buttons share one symbol weight and size (#409); the microphone and the screen's audio record to
  separate files (#320); edits during a drag coalesce into one rebuild and undo step, with a 20–100 ms
  debounce (#380); inspector sections have disclosure arrows, reset icons and a per-section AI badge (#414);
  the canvas can fill the bars around a 16:9 source with a blurred copy of the same frame (#79, Canvas →
  Blur fill).

### Under the hood
- `ChapterArt` (engine) draws with AppKit on the source frame, so a marker over a cutaway or gap is skipped.
- `PlaybackController.load(renderScale:)` passes a smaller `renderSize` to the composition builder; the
  periodic time observer compares media time against the wall clock and publishes `isStruggling`, which
  `ProjectSession` turns into a `playbackQualityOverride`.
- `MemoryPressure` (engine) wraps a `DispatchSourceMemoryPressure` and reads the process footprint with
  `task_info`; `ThumbnailService.setMemoryCeiling` / `trimMemory` act on it.
- Chroma keying is a cached 32³ `CIColorCube` built from `ChromaKey.alpha(red:green:blue:)` (core, tested);
  feathering insets the mask shape by the feather and blurs it. `ScopeData` and `FrameStats` (core) read RGBA
  bytes; the app downsamples `PlaybackController.currentFrame()` (an `AVPlayerItemVideoOutput`) to feed them.
- `LoopPoints` (core) finds the seam in a peak envelope and `segments(loop:trackDuration:duration:)` lays the
  pieces; `LongFormEditor` uses it for music beds when the app hands it the bed's peaks.
