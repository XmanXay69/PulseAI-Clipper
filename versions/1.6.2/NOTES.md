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

### Batch 37

- **Loudness readout** (#262) — next to the mix meter: momentary (0.4 s), short-term (3 s) and the whole
  edit's integrated loudness against the −14 LUFS target most platforms normalise to; green within a dB,
  orange quiet, red hot. It reads the analysed recordings through every gain, so it costs nothing to show.
- **Better thumbnail frames** (#361) — the frames PULSE suggests now favour a face that just got bigger (a
  reaction), holding still, with room beside it for the text; each pick carries where that text space is.
- **Panel tabs** (#415) — the Media / Sounds / Transcript / Angles / Effects / AI strip is icons, with the
  name on the chosen tab and under the mouse.
- **Macros** (#479) — in Ask PULSE, Record Macro keeps the requests you type, Save names them, and the
  Macros menu replays them on any timeline, each step its own undo.
- **Import, one row per file** (#4) — every file imports as its own job with its stage (probing,
  fingerprinting, imported) and its own cancel button; the project updates once in one undo step when the
  last one lands.
- **One sheet header** (#413) — Edit My VOD, Make Thumbnail, Overnight Batch, Project Settings, Extras,
  Report a Problem and Edit Like a Reference share one header component.

### Batch 38

- **Show me around** (#432) — a four-step tour over the real window: the sidebar, the page bar, the editor
  and the search / Ask PULSE spots light up in turn with a card beside each. From the welcome screen or
  Help → Take the Tour; Return goes on, Escape ends it.
- **Sample projects per genre** (#449) — the sample project comes as a gaming stream, a two-host podcast
  or a handheld IRL vlog, each synthesized on your Mac with its own script, moments and faces. Help →
  Open Sample Project, or right-click the Home tile.
- **Media folders** (#20) — a folder strip in the media panel: click to filter, drop media on a folder to
  move it, right-click to rename, colour or delete; folders nest, and deleting one lifts its contents up.
- **The next video on the end screen** (#99) — a Thumbnail Studio export in the project (an image named
  "…thumbnail…") goes into the end screen's right half, where YouTube's card will sit.
- **Bars, not spinners** (#412) — checking for updates, installing, finding screens, grabbing frames,
  rebuilding the viewer and rewriting copy show a sweeping bar with words instead of a lone spinner.

### Batch 39

- **OBS multi-track recordings** (#11) — a recording with several audio tracks lands as one lane per
  track: Mix, Mic, Game, Music (and Chat, Alerts), each linked to the picture; the mix starts muted so
  nothing plays twice. Each clip remembers which track it plays.
- **A sticker that follows the face** (#81) — Timeline → Pin Emoji to Face… puts an emoji or a word over
  the selected clip that follows the biggest face, just above the head, through the crop and the zooms;
  the keyframes are on the sticker, so you can nudge them.
- **Voice-over** (#331) — Timeline → Record Voice-Over records the microphone from the playhead (or the in
  point) until Stop, then places it on its own lane with music ducked under it.
- **B-roll three at a time** (#134) — the online cutaways of Edit My VOD download in parallel and are
  placed in order once they land.
- **Caption pages cached** (#260) — a page's rendered picture is kept between word changes, so a
  20-minute captioned edit scrubs and plays without laying the text out every frame.

### Batch 40

- **Before / after wipe** (#193) — a button in the viewer's strip draws a line across the picture: the
  recording as shot on the left, the edit (grade, enhance, layout) on the right; drag the line.
- **See what an extra does** (#104, #126) — the Extras question and the Edit My VOD sheet show a small
  mock-up next to each choice: the memes in their colours, a title card, a film strip with its CC badge, a
  replay, the beat grid, a punch-in, speakers.
- **Before / after in the storyboard** (#108) — each moment's Before / After opens two silent loops side by
  side: the raw stretch around it and what the edit keeps.
- **Big-face cutout thumbnails** (#363) — a fourth thumbnail style cuts the person out of the frame with
  Vision's person segmentation and sets them big on a colour wash with the text beside them; without a
  clean cutout it falls back to the face zoom.

### Batch 41

- **Grid divider** (#330) — a Divider slider in the Angles panel moves the main pane's edge of a 2-up,
  3-up, 2×2 or featured grid between 30 and 70 % of the canvas; the shot is laid out again as you drag.
- **Sync by timecode** (#325) — recordings that carry a timecode track sync by it, exactly, with no audio
  listened to; otherwise audio sync as before, and both report how sure they are (the weakest match is
  the one to check).
- **Back from sleep** (#390) — a download that stops moving after the Mac wakes starts over by itself and
  carries on from its partial file.

### Batch 42

- **Translated captions, both kept** (#248) — Captions → Language → Translate… sends the captions sentence
  by sentence to the AI provider from Settings → AI (Claude, OpenAI, or a local OpenAI-compatible server
  such as LM Studio) and keeps the result as a second track; each translation's words follow the timing
  of the speech, and a picker switches between the original and every language you've added.
- **Transcript as it happens** (#39) — while a recording transcribes, the Transcript panel shows the words so
  far (Apple Speech after each chunk, whisper.cpp as each segment prints) instead of an empty state.

### Batch 43

- **Raw solo** (#282) — ⌥-click a track's S: it solos with its enhance chain bypassed (the button reads R),
  so you hear the recording as it is; a plain click is solo in place, effects and all.
- **Edit again, keep my changes** (#116) — Edit → Edit My VOD Again → Same Settings, Keep My Changes rebuilds
  the edit and puts your own clips, markers, notes, caption look and cover frame back onto it.
- **HEVC 10-bit** (#348) — a Main 10 codec choice for HDR-safe pipelines; the picture is rendered in SDR and
  VideoToolbox writes the 10-bit stream.
- **Isolation at 0 / 50 / 100 %** (#276) — the enhance preview plays the stretch three ways: voice isolation
  off, at half strength and as set.
- **Spacing grid and type scale** (#401) — `Theme.Spacing` (4 to 32 pt) and the 10/11/12/13/15/22/28 type
  scale are named constants for every new view.

### Batch 44

- **Per-game profiles** (#34) — the clip scorer knows that a shooter's best moments are on screen (kills,
  banners, chaos), a sandbox or Just Chatting stream's are in the voice, and a horror game's are the jump
  scares. Eight built-in profiles (Shooter, Horror, Sports, Racing, Fighting, Strategy / MOBA, Sandbox / Cozy,
  Just Chatting) scale each signal's share and the total is re-normalized so scores stay comparable. The game
  is detected from the project and file names, or from a game named at least twice in the transcript; File →
  Project Settings → Game profile pins one. The clips toast and the activity log say which profile scored the
  recording, and your taste profile still learns on top.
- **Audio-only recordings in Edit My VOD** (#9) — a podcast WAV or any recording without a picture gets a drawn
  waveform video: bars that move with the voice, the recording's name and a progress line, rendered once into
  the cache and placed under every cut of the edit, linked to its audio and cut like any camera. Running the
  edit again reuses the picture.

### Batch 45

- **A facecam that moves** (#46) — on a long stream whose webcam overlay changes corner between segments, the
  analysis keeps one position per stretch: each short's layout uses the position of its own moment, long-form
  facecam push-ins land on the right spot, and the Layout section says how many times it moved.
- **First look** (#35) — clips from the audio alone show up before transcription (the slow part) starts: the
  loud and surprising moments are scored and badged "First look" in AI Clips, then replaced by the full pass
  when the transcript lands; favorites and opened clips stay.
- **Exports that know their project** (#465) — every export gets a Finder comment ("PULSE · project › edit ·
  Project: path") and a Where-from entry pointing at the project package, so Get Info and Spotlight lead back
  to it; Quick Look previews the file as usual.

### Batch 46

- **Reframing that follows the action** (#56) — the video analysis now tracks where the picture is changing
  (the fight, the ball, the crosshair), and a tall gameplay short pans its crop toward it: the crop holds still
  while little moves, never whips on a cut-away and stays inside the frame. One-click shorts on gameplay do
  it on their own; the Auto Reframe button on a gameplay clip reads "Follow the Action".
- **Noise learned from a marked silence** (#263) — set In and Out around room tone, the fan or hiss and press
  Learn from In/Out in the Audio inspector: the classic noise reduction subtracts exactly that profile
  instead of guessing from the quietest frames, the profile is saved with the clip, and a learned profile
  gets its own cached render.

### Batch 47

- **Two-pass encoding** (#343) — Deliver → Options → Two-pass: the encoder sees the whole video first and
  spends the bitrate where it's needed, for the best quality at a given size at about twice the render time
  (H.264 and HEVC; the progress bar runs through both passes).
- **Music with a tempo and a license line** (#291) — every Creative Commons track gets its tempo measured
  after download and carries its license; a fast-cut edit prefers beds around 110–170 BPM, a slow one under
  95, the search casts a wider net per mood, and the music row in the inspector shows the shelf, the license,
  the BPM and the page.
- **Shelves filled while idle** (#303) — Edit My VOD → Extras → "Download five tracks per mood while the Mac
  is idle": every ten minutes, with nothing running, no input for three minutes and the Mac plugged in, each
  mood's shelf is topped up so an edit never waits on a download.

### Batch 48

- **Recordings split under a size limit** (#322) — Record → Split files: when a recording stops, any file
  over the limit (2 / 4 / 8 / 16 GB) is cut into "part N of M" files without re-encoding, the parts are imported
  as one synced recording and joined back together on a timeline with a marker at every join, so a single
  file never outgrows a disk or a sync folder.
- **The voice leans toward the facecam** (#271) — Timeline → Pan Voice Toward the Facecam: the audio linked
  to each facecam pans a little (at most ±20 %) toward the side of the canvas the facecam sits on; nothing
  happens in the middle third.
- **Another project in a browser window** (#468) — Window → Open Another Project in a Browser Window…: its
  media and timelines beside the one you're editing; drag a file onto the main window to import it, or copy
  a file or a whole timeline (with the media it uses) into the current project. The other project is never
  changed.
- **Localization scaffolding** (#457) — a strings table under `Resources/en.lproj`, an `L("…")` lookup that
  falls back to the English key, the package set up for more languages and `docs/LOCALIZATION.md` saying how
  to add one; menu items go through it first.

### Batch 49

- **Moments found while recording** (#481) — the live meter watches the voice as you record: a burst well
  above its usual level that holds for a beat becomes a live moment, counted on the HUD next to Clip it; when
  the recording stops they seed the clip search like banners, so the first look proposes them straight away.
- **Exact timestamps from the game** (#488) — Record → "Riot live events (League / TFT)" polls the game
  client's Live Client Data API on this Mac while recording and stamps every kill, multi-kill, objective, ace
  and the result on the recording to the frame; Import Game Events… (on a recording's menu) reads a Riot
  event log, a CSV of time,kind,text lines or a JSON list from any other tool, asks where the game's 0:00 sits
  in the recording, and merges them with what the screen reader saw.

### Batch 50

- **Dub into a second language** (#486) — Captions → Language → Dub into Spanish (any translated language):
  the translated captions are spoken by the system voice for that language, line by line at their times, on a
  copy of the timeline named "… — Spanish dub" with the captions switched and the original voice 18 dB under
  the dub; export it for the second-language channel. Needs a voice installed under Accessibility → Spoken
  Content; Enhanced and Premium voices sound best.
- **Plugins** (#495) — a folder in Application Support/PULSE/Plugins with a plugin.json is a plugin: an
  *effect* names a chain of Core Image filters (from a safe list) with sliders that show in the Inspector and
  animate like any parameter, and sits in the Effects menus under the built-ins; a *signal* names a command
  that gets the recording's path, length and transcript on stdin and prints events that score like banners
  (run it from a recording's menu). Settings → Plugins lists them, says why one doesn't load, and writes two
  examples to copy; docs/PLUGINS.md has the format.

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
  Blur fill); timeline clips are rounded with a top highlight, a name chip, a filmstrip and tinted waveforms
  (#403); Home opens on a soft-gradient hero with two primary cards and a tidy grid of actions (#406); the
  app icon and the DMG background are drawn by the app itself (#440); a separate microphone recording is
  found as the voice companion of a screen recording and synced by its audio (#10); the enhance chain has a
  de-esser and plosive reducer (#264) and the Warm / Clear / Radio voice EQ presets with the A/B preview (#265).

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
