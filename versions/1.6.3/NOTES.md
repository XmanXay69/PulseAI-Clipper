## PULSE 1.6.3

A hardening pass on top of [1.6.2](../1.6.2/NOTES.md): the roadmap is complete, so this build goes back over
the engine code the last batches shipped and makes each piece behave the way the frameworks expect, before
any of it meets a real recording.

### Design
A restrained, professional look across the whole app, in the spirit of a grading and editing suite rather than a
dashboard — the same features, the same workflows, quieter surfaces.
- **One design system.** Deep charcoal surfaces (never pure black; the viewer well is the darkest), hairline
  borders and tonal steps instead of shadows, corner radii of 3–8 pt, flat fills with no gradients or glows, one
  accent for primary actions, selected tools and the playhead, the AI violet only as a marker on what the AI made,
  and semantic colours only for warnings, errors and success. Muted track colours keep a dense timeline calm.
- **Chrome.** A 40 pt title bar reads "Project / Page" with the save state beside the name, a compact search
  field, the background-task and system indicators and an outlined version badge. The rail marks the current
  section with a 2 pt accent bar. The page bar along the bottom is a flat tab strip — Media · AI Clips · Edit ·
  Captions · Deliver — with a 2 pt indicator over the current page.
- **Editor.** The workspace bar holds the editor's own layouts (Editing, Color, Audio); AI Clips, Captions and
  Export are pages of their own, so they no longer repeat there (View → Workspace still lists every preset). The
  viewer sits on a darker well with a thin frame; the transport is flat with the timecode in the primary text
  colour and an accent-filled play button only while playing. Timeline clips are flat tiles with a plain label,
  a hairline in the clip's colour and a white border when selected; the playhead is a 1 pt line with no glow;
  the toolbar and track headers sit on the panel colour.
- **Pages.** Home is a plain panel with a headline, the two starting points and a grid of compact action rows
  with monochrome icons — no gradient hero, no lifted cards. Project cards, clip cards, media tiles and the drop
  zone follow the same tokens. Preset swatches have a flat backdrop.

### Fixes
- **Two-pass export** (#343) now drives AVFoundation's multi-pass API the way it is documented: every pass
  starts from the encoder's pass description, the reader is reset to the stretches it names, media is
  requested for that pass alone, and the encoder is told when the pass runs dry. The earlier version
  requested media once and could stall after the first pass. When the encoder declines a second pass the
  seekable reader is still told reading is over.
- **YouTube upload** (#482) resumes instead of failing: a dropped connection or a 500–504 from Google makes
  PULSE wait, ask the upload session where it got to (`Content-Range: bytes */size`) and carry on from that
  byte, up to five times with a growing pause. An expired session says so plainly. The sign-in's redirect
  address is handed over inside the sign-in itself rather than through a shared box.
- **Dubbing** (#486): the synthesizer's "done" callback can arrive more than once; the job now resumes exactly
  once, gives up on a voice that produces nothing within a minute instead of hanging, and the silence between
  lines is written from zeroed buffers (a fresh buffer's memory is not promised to be silent; planar and
  interleaved formats are filled correctly).
- **Signal plugins** (#495): stderr is drained while the plugin runs, so a plugin that logs a lot can't fill
  the pipe and stall; a plugin whose output isn't an event log is noted in the app log rather than treated as
  "no events".
- **Waveform video** (#9) for audio-only recordings: a frame the encoder refuses is now an error with the
  encoder's reason, rather than a silently shorter video.
- **Split recordings** (#322): when both the screen and the camera were split, their parts were sorted into
  one sequence; each file now joins with its own parts on its own timeline (the screen's first).
- **Cancelling an analysis stops whisper.cpp.** Before, Stop on an analysis job left whisper working through the
  whole file at full CPU until it finished on its own; the job's cancel flag is now polled once a second while
  whisper runs and the process is stopped, and the task's own cancellation does the same. An FFmpeg conversion
  (for formats AVFoundation can't open) stops the same way when its import is cancelled.
- **Recording can't hang on the camera.** A camera or microphone that never reports "started" (unplugged
  mid-countdown, claimed by another app) made the countdown wait forever; it now fails after 10 seconds with
  the device named, and the screen recording starts without it is not lost: a stop the device never finishes
  writing gives up after 20 seconds, keeping the screen file and reporting the camera file as the problem.
- **Screen capture failures are heard.** The ScreenCaptureKit stream was created without a delegate, so a
  stream that stopped on its own (display unplugged, permission revoked mid-recording) was never recorded as a
  failure; a delegate proxy now forwards the stop, which is logged and reported when nothing was captured.
- **Restoring an archive is a job** with "Unpacking" and "Relinking media" steps, instead of freezing the window
  while a multi-gigabyte zip unpacks.
- **VOD downloads by link** (#1, #467) failed for anything over 60 MB with "Unexpected file size" — the music
  library's size guard — and held the whole file in memory. The ranged download now writes each 1 MiB piece
  straight into the file at its offset, allows up to 12 GB for a VOD (60 MB stays the limit for music and
  B-roll clips), checks the disk has room first, reports "Downloading — 42% of 1.3 GB" in the job, and a
  cancelled job stops every request and removes the partial file.

### Under the hood
- `ExportPump.transferMultiPass` keeps the last pass description it started, so a description announced twice
  (once on registration, once on change) starts one request.
- `YouTubeUploader.resumeOffset(session:size:fallback:reason:)` and `lastByte(in:)` are the status query and
  the `Range` parse; `recoveries` caps the retries at five, `resends` the refused pieces at three.
- `DubSynthesizer.speak(_:with:)` is the one-shot continuation around `AVSpeechSynthesizer.write`.
- `PluginRegistry.DrainedPipe` reads a pipe to its end on a background thread.
- `ChildProcess` (engine) wraps a `Process` with `terminate()` for a task's cancellation handler and `watch(_:)`
  for a job's cancel flag; `WhisperCppTranscriber.isCancelled` is set by the analysis pipeline, and `FFmpeg.run`
  uses the task handler.
- `RangedDownloader` (engine) is the one ranged download: `OnlineMusicLibrary.rangedDownload` (60 MiB) and
  `downloadLarge` (12 GiB, with byte progress) call it.
- `Sources/PulseApp/Design/Theme.swift` is the design system: surfaces, borders, text, accents, track colours,
  radii, the type scale. `accentGradient`, `aiGradient` and `edgeHighlight` remain as flat no-ops so older call
  sites compile; `elevation(1)` draws nothing, `elevation(2)` a soft popover shadow. `PulseButtonStyle` is flat;
  `WorkspaceBar.editorPresets` lists the layouts the bar shows.
