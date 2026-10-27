# PULSE — Handoff / Status

> Living status document, updated with every push so work can be picked up at any time
> (by you, a new Claude session, or another developer). If you are a new Claude session:
> read this file first, then `git log --oneline | head -20`.

**Branch:** `claude/exciting-bardeen-df149p`
**Build:** Swift Package (`Package.swift`, tools 5.10, Swift 5 language mode), macOS 14+ (Apple Silicon first,
works on macOS 15 and 26). CI compiles, tests and screenshots the app on GitHub Actions runners
(`.github/workflows/ci.yml`, matrix `macos-14`, `macos-15`, `macos-26`, `macos-15-intel`) because the cloud dev
box used to write it is Linux. Apple-silicon runners are often queued or cancelled for lack of capacity; the
Intel and `macos-15` jobs are the ones that usually finish, and one green job is enough to trust a push.

## Versions

`VERSION` holds the current version (1.6.2). Release notes per version live in `versions/<version>/NOTES.md`
(the Release workflow prepends them to the GitHub Release); `versions/README.md` explains how to cut a new one.

## Download (the easy way)

`PULSE.dmg` is published by `.github/workflows/release.yml` on commits containing `[release]` (or a manual
run) as the latest GitHub Release: https://github.com/XmanXay69/PulseAI-Clipper/releases/latest/download/PULSE.dmg
— universal (arm64 + x86_64), with a static whisper.cpp (`scripts/build-whisper.sh`, Metal embedded,
system libraries only) in `Contents/MacOS/whisper-cli` and `ggml-base.en.bin` in `Contents/Resources`.
The workflow checks the mounted image: signature, both slices, the app binary running, and a real `say` →
whisper transcription using only what's inside the image. Without Developer ID secrets the app is ad-hoc
signed, so the first launch needs Privacy & Security → Open Anyway (macOS 15) or right-click → Open
(macOS 14); the README lists the secrets that make it signed + notarized.

## Run it on your Mac

```bash
git clone https://github.com/XmanXay69/PulseAI-Clipper.git
cd PulseAI-Clipper
git checkout claude/exciting-bardeen-df149p

swift run PULSE              # quickest way to launch (Xcode 16+ command line tools)
# or
./scripts/build-app.sh       # builds build/PULSE.app (+ build/PULSE.zip), ad-hoc signed
open build/PULSE.app
```

- Open `Package.swift` in Xcode 16 to edit/debug; choose the **PULSE** scheme and "My Mac".
- Apple Speech transcription needs the **app bundle** (it requires `NSSpeechRecognitionUsageDescription`
  from `Resources/Info.plist`). With `swift run`, use whisper.cpp (`brew install whisper-cpp` + a ggml model)
  or import an SRT/VTT.
- First launch shows the welcome guide: **Open Sample Project** generates a 75-second gameplay + facecam
  stream locally and runs the whole pipeline (analysis → AI clips → 9:16 short with captions).

## Architecture

| Module | What it is |
|---|---|
| `PulseCore` (pure Swift, 392 unit tests) | Timeline model + all edit ops (split, ripple, trim, speed, link, text-based delete/restore), snapshot undo/redo, `.pulse` project packages (autosave, rotating backups, versions, crash recovery), transcripts (SRT/VTT/whisper.cpp/OpenAI JSON), filler words, silence detection, audio sync, engagement model + AI clip generation (HOOK→CONTEXT→PAYOFF→END, AI Potential), titles/hooks, captions (8 presets, paging, word timing, emphasis, safe areas), streamer layouts + facecam detection, AI reframing, punch-ins, one-click short builder, "Make More Entertaining", templates, export presets/queue, AI provider abstraction + privacy policy (Local / Claude / OpenAI-compatible), settings, global search, multicam (sync groups, angle cuts, AI switching, grid layouts), compound clips (nested timelines), speaker diarization (segmenting, embedding clustering, MFCC fallback clustering, labels) |
| `PulseEngine` (AVFoundation, Vision, Speech, Core Image/Metal, SQLite) | Media probing/import, thumbnails, waveforms, proxies, audio analysis, Vision face detection, Apple Speech + whisper.cpp transcription, composition builder + custom `AVVideoCompositing` compositor (layouts, masks, crops, keyframes, captions, text, color, LUTs, effects, transitions), AVAssetWriter export (H.264/HEVC hardware, ProRes), playback controller, demo media generator, SQLite library index with FTS5 transcript search, ScreenCaptureKit + camera/mic session recorder (pause/resume), audio enhance chain, neural speaker encoder (GE2E LSTM via BLAS) + MFCC fallback |
| `PulseApp` (SwiftUI) | Sidebar app: Home, Projects, Import, AI Clips, Editor (viewer, timeline, inspector, transcript), Captions, Media, Templates, Exports, Settings; onboarding, recovery, ⌘F global search, background jobs, toasts, keyboard shortcuts |

Key files to know:
- `Sources/PulseApp/State/ProjectSession.swift` — every user action on an open project (goes through `edit`/`editTimeline` → undo history → autosave → playback rebuild).
- `Sources/PulseApp/State/AppModel.swift` — app-wide state, projects list, demo project, recovery.
- `Sources/PulseEngine/Composition/CompositionBuilder.swift` + `Rendering/FrameRenderer.swift` — how a timeline becomes pixels (same path for playback and export).
- `Sources/PulseCore/AutoEdit/ShortBuilder.swift` — candidate → finished 9:16 short.
- `Tests/PulseEngineTests/EngineSmokeTests.swift` — end-to-end: demo media → analysis → clips → short → rendered stills → exported MP4.
- 1.6.2 additions: `Sources/PulseEngine/Playback/PlaybackController.swift` takes a `renderScale` (viewer quality,
  #187) and publishes `isStruggling` when media time falls behind the clock; `ProjectSession.playbackQualityOverride`
  is the automatic step-down. `Sources/PulseEngine/System/MemoryPressure.swift` (#377) trims
  `ThumbnailService` on a system memory warning. `Sources/PulseCore/Audio/LoopPoints.swift` (#294) finds a music
  bed's seam; `LongFormEditor.addMusic(loops:)` lays the pieces. `Sources/PulseEngine/Export/ChapterArt.swift`
  (#493) renders a PNG per chapter marker. Thumbnails and waveforms are keyed by `MediaAsset.contentHash` when
  the session registers it (#398). `Sources/PulseCore/AutoEdit/OwnStyle.swift` (#489) measures a finished
  timeline into the same `ReferenceStyle` a studied reference gets; `AppSettings.ownStyleSamples` keeps the
  last ten exports and `ownStyle` averages them. `MulticamEditor.SwitchTuning` (#327) maps the Angles panel's
  slider onto `autoSwitch`'s minimum shot and crosstalk threshold; `snapped(_:toBeats:)` moves cuts onto beats.
  `PlayheadOrder` (#289) orders the pending enhance renders from the playhead; `ProjectSession.canvasTool`
  (#192) switches the viewer's handles between move/scale and pan/zoom. `Sources/PulseCore/Audio/PeakMeter.swift`
  (#194, #281) turns cached waveform peaks into meter levels with hold/decay ballistics; `MixBalance` (#267),
  `RoomTone` (#273) and `MusicStems` (#295) sit next to it. `Sources/PulseCore/AutoEdit/EditorAssistant.swift`
  (#498) parses plain-English requests into `EditorIntent`s that `ProjectSession+Assistant.swift` applies as
  ordinary edits; `RenderLoad` (#183) scores each second's drawing cost for the ruler; `MulticamEditor.pipTimeline`
  (#328) builds the game-plus-cam layout.

## Phase status

- [x] Phase 0 — repository bootstrap, CI (build, unit + engine tests, whisper test, UI screenshots, `.app` bundle)
- [x] Phase 1 — core foundation: models, project system, autosave/backups/recovery, app shell
- [x] Phase 2 — video engine: import, probe, thumbnails, waveforms, proxies, composition, playback, export
- [x] Phase 3 — AI: audio/visual analysis, transcription, clip candidates, scoring, titles, hooks
- [x] Phase 4 — short-form: layouts, facecam, reframing, captions, safe areas, punch-ins
- [x] Phase 5 — pro editing: timeline ops, inspector, keyframes, color/LUT, effects, true cross-dissolves, text, transcript editing, audio enhance
- [x] Phase 6 — AI auto edit: one-click short, Make More Entertaining, silence/filler removal, strip AI edits
- [x] Phase 7 — export: presets, batch queue, progress/cancel, hardware encoders
- [x] Phase 8 — capture + multicam: screen/window + system audio + webcam + mic recording with pause/resume,
      synced sessions, Angles panel, live 1–9 cuts, AI active-speaker switching, grid layouts (2-up, 3-up, 2×2, featured)
- [x] Phase 9 — compound clips (nest/open/break apart, rendered and exported) and local speaker diarization

### What CI actually verifies on every push (macOS 14 / 15 / 26 / 15-intel runners)

- 366 unit/engine tests (timeline edit ops, undo, project save/recovery, transcript parsers, clip generation,
  captions, layouts, export settings, audio DSP, the fuzzed timeline invariants, and one `BatchNTests.swift`
  per 1.6.0 roadmap batch, …).
- **Engine end-to-end:** generate a 75 s gameplay+facecam stream → probe → analyze (audio + Vision faces) →
  AI clip candidates → one-click 9:16 short (split-screen, captions, normalized dialogue audio) → rendered
  stills → exported H.264 MP4 → landscape re-layout → two-sided cross-dissolve → multicam edit → 2-up grid render → compound clip render.
- **Real speech-to-text:** macOS `say` → whisper.cpp (tiny.en) → word-timed transcript
  (“No way, that was the craziest clutch I have ever seen. Let's go.”).
- **Screen recording:** ScreenCaptureKit records the runner's display with a pause in the middle; the file
  length excludes the pause.
- **Layout morphs:** the demo short morphs split screen → circle facecam over 1 s without splitting clips;
  before/mid/after frames are rendered and differ (mean pixel change 35 / 31), mid-morph has no black bars
  (`layout-morph-*.png`, app screenshot `13d-layout-morph`).
- **Per-speaker captions:** a two-speaker caption track renders the guest's words in their own color (cyan vs
  white) with a name tag above when labels are on.
- **AI noise removal:** speech under keyboard clicks, music and fan noise → SI-SDR 10.3 dB noisy, 11.9 dB
  classic, 17.9 dB AI voice isolation, output sample-aligned (7.6 s of audio in 2.7 s on the CI VM).
- **Sound library:** every track and effect renders (exact length, −16 LUFS music / −3 dBFS effects, clean
  ending); the upbeat groove measures 122 BPM as written; the end-to-end short exports with a library music
  bed and impact; in the app a composed bed is added to the sample short in ~5 s (screenshot `13c-sounds-added`).
- **Speaker diarization:** the Swift speaker encoder matches the PyTorch model (cosine 0.999999); on six pairs of
  macOS voices (incl. female/female and male/male) neural diarization labels 100% of words correctly vs 67%
  for the old MFCC method; three voices → 3 speakers (100%); one voice → one speaker.
- **The app itself:** launches, builds the sample project, visits every section, screenshots them, grabs a
  live viewer frame, opens ⌘F search, and exports the short through the app's export queue (≈8.8 MB MP4).
- **Release bundle:** `scripts/build-app.sh` builds, icons, ad-hoc signs and zips `PULSE.app` on `[app]` commits.

Not verified by CI: a human clicking through with real long recordings, Apple Speech (needs a permission
prompt), cloud AI providers with live keys.

## Honest gaps (architecture only / not yet implemented)

- **Noise reduction** has two methods (Inspector → Enhance → Method). **AI Voice Isolation** (default for new
  clips) runs Apple's on-device neural voice isolation model (the `AUSoundIsolation` audio unit, macOS 13+)
  offline, sample-aligned by cross-correlation, and mixes the original back in by the slider amount; it removes
  non-steady noise (keyboard, music, crowd). It is Apple's model, not one trained for PULSE, and it only keeps
  speech (singing or instruments you want to keep will be removed — use Classic there). **Classic** is spectral
  subtraction + expander, used for old projects and whenever the model isn't available. Speed on the CI VM is
  ~2.8× real time per channel (Apple Silicon should be faster); renders are cached per clip + settings.
- **Compound clips** (⌥G to nest, double-click to open, ⇧⌘G to break apart) render and export, and can be sped
  up or slowed down (everything inside plays at that speed); effects on the compound apply to the flattened
  result.
- **Multicam** works for synced sessions (imported multi-camera recordings via audio sync, or PULSE recordings):
  Angles panel, 1–9 live cuts, Inspector switching, grid shots (2-up / 3-up / 2×2 / featured, on "Grid N"
  tracks), AI active-speaker switching with a 2-up grid on crosstalk (needs one mic per angle; otherwise it
  falls back to the wide shot).
- **Screen capture** (ScreenCaptureKit, pause/resume) is verified on CI with a real display; webcam/mic capture
  can't be tested on CI (no devices) — test on your Mac.
- **Speaker diarization** uses a neural speaker-embedding model: Resemblyzer's pretrained GE2E encoder
  (3-layer LSTM, 256-d embeddings, trained on LibriSpeech + VoxCeleb, Apache-2.0 — license in
  `Resources/Models`), reimplemented in Swift with Accelerate (`SpeakerEncoder`) and checked against the
  PyTorch original. Speakers are found by cutting an average-linkage tree where the silhouette is best, then
  merging near-identical voices (cosine > 0.92). Calibrated on macOS synthetic voices only — real rooms,
  overlapping speech and laughter will be harder; the Speakers menu (fixed count, rename, merge) is the
  override. Notably, one voice split by the tree scored 0.40 silhouette on CI and was rescued by the 0.92 merge
  rule, so watch for over-splitting on real solo recordings. The old MFCC+pitch clustering remains as the
  fallback if the model file is missing. Multicam sessions with one mic per person still use mic loudness.
- **Cloud AI** (Claude / OpenAI-compatible) is optional, used only for titles/captions copy; untested with live keys.
- **Music/SFX library** is built in and generated on the Mac (`PulseCore/Library`): 14 music tracks in 10 styles
  (lo-fi, trap, upbeat pop, acoustic, synthwave, cinematic, chiptune, suspense, comedy, ambient) composed by
  code to any exact length with an intro, breakdown and real ending, plus 28 synthesized SFX (whoosh, riser,
  impact, boom, pop, ding, rimshot, sad trombone, record scratch, applause, 8-bit coin, countdown…). Royalty-free
  because nothing is sampled. It's synthesis, not recorded instruments — it sounds like clean electronic
  production, not a live band; judge by ear and tweak `Synth`/`MusicComposer` voices if something sounds off.
  Editor → Sounds tab (preview, search, add); AI shorts / Make More Entertaining use it when the project has no
  music/SFX of its own (Settings → AI music / sound effects).
- **Per-speaker captions:** caption tracks keep speaker names and per-speaker overrides (text/highlight color,
  position). "Color by speaker" gives each extra voice its own color (one-click shorts do it automatically when
  two or more people talk); optional name tags above captions; Captions → Speakers to edit; re-detecting,
  renaming or merging speakers updates existing captions.
- **Layout morphs:** a timeline has a starting layout plus `layoutChanges` (time, layout, morph length);
  `LayoutMorpher.rebuild` turns them into eased keyframes on the gameplay and facecam clips — position, scale,
  keyframed crop (`VisualTransform.cropAnimation`), keyframed style (`TimelineClip.styleKeyframes`: corners,
  border, shadow; a box rounds into a circle) and facecam opacity (it fades when a layout has no facecam). No
  clips are split. In-between frames move each clip's on-screen box and crop together (sampled 30×/s) so a
  clip always exactly fills its box, and the canvas "Blur fill background" (on automatically once a timeline
  has morphs) shows a blurred copy of the video wherever two layouts' boxes don't cover the frame.
  Inspector → Layout → "Morph at Playhead"; AI Dynamic layouts use the same morphs. Rebuilding
  rewrites position/scale/crop/style keyframes on laid-out clips (zoom/pan punch-ins are separate and kept), so
  hand-made keyframes on those four properties are replaced when the layout schedule changes. Cutting and
  restoring sections moves markers and layout changes with the content.
- **Editor layout at small window sizes:** the viewer gets an exact width between the side panels (which
  shrink toward their minimums so the viewer keeps ≥ 420 pt), side panels are clipped, the Inspector lays out
  at its column width, and the viewer header/transport bar compress (in/out chips and the canvas readout drop
  out first). Checked on CI at a 1280 × 720 window; very small windows (< ~1000 pt) will still crowd.
- README screenshots in `docs/screenshots/` are copied from CI snapshots; refresh them from a newer run after
  UI changes (decode the `SNAPSHOT` lines as described below).
- **Edit My VOD (1.0)** — `PulseCore/AutoEdit/LongFormEditor.swift`: picks moments with `ClipGenerator`
  (45 s windows, potential-ranked) until the 10–20 min target (15 % of the source, clamped; 60 % for short
  recordings), merges near-touching picks, orders them chronologically, opens with a 4–7 s cold-open hook +
  title, jump-cuts silences (balanced), adds spaced reaction zooms, meme pop-ups (text/emoji + matching library
  SFX) and transition whooshes with per-minute caps (`Restraint`), YouTube subtitles, chapter markers and a
  chapter list in `timeline.notes`. The app (`ProjectSession+LongForm`) renders library SFX, composes one music
  bed per ~4-min chapter, then `LongFormEditor.addMusic`. Tuned on synthetic streams only — real VODs will
  need taste tuning (what counts as "funny" comes from laughter words, loudness spikes and keywords).
- **Edit coach (1.0)** — `EditCoach.review` samples the engagement curve through the edit (timeline → source
  via the main clips) and scores hook / energy / payoff / pacing / ending / length / polish with format-specific
  weights; suggestions carry `Fix` values the app applies (`ProjectSession+Coach`). It's a heuristic
  prediction, not trained on real view data.
- **Time estimates (1.0)** — `AnalysisSpeedProfile` (seconds per media-minute per stage, learned with an EMA
  after each analysis, stored in AI settings) weights pipeline progress by expected stage time; `ProgressClock`
  blends the prior with the observed rate for the countdown.
- **TikTok Sans (1.0)** — `Resources/Fonts/TikTokSans.ttf` (variable, OFL) registered at launch by
  `BundledFonts`; weights/slant via variation axes. Default for new text and most caption presets.
- **1.1.0 features** —
  taste: `PulseCore/Clips/TasteProfile.swift` (logistic model over ClipScores + tags; `applyingTaste` keeps
  `basePotential`); chat: `PulseCore/Chat/ChatReplay.swift` (parsers, lexicon, `ChatSignals` with 5 s lag)
  feeding `EngagementModel.compute(analysis:)`, stored in `MediaAnalysis.chat`; storyboard:
  `LongFormEditor.planMoments` + `Views/LongFormStoryboard.swift`; batch: `State/BatchController.swift`
  (drives the normal session steps, waits for the job center to go idle); brand kit:
  `PulseCore/Templates/BrandKit.swift` + `ProjectSession+Brand.swift`; calibration:
  `PulseCore/AutoEdit/Calibration.swift` (CSV import, title matching, ridge fit) with history in
  Application Support/PULSE/performance-history.json; resume: `AnalysisCheckpoint` in
  `AnalysisPipeline.swift`; logging/report: `PulseEngine/Support/PulseLog.swift` (~/Library/Logs/PULSE) and
  `PulseApp/Support/ProblemReporter.swift`; Thumbnail Studio tie-in: `PulseCore/Thumbnails/ThumbnailDesigns.swift`
  (frame picker, headline, the studio's `ThumbDocument` JSON format and three layouts),
  `PulseEngine/Support/ThumbnailStudioLink.swift` (writes frames to `~/Library/Application Support/VODEditor/ThumbAssets`
  and designs to `…/VODEditor/ThumbLab`, launches `com.xavier.thumbstudio` with `--open <design>`),
  `ProjectSession+Thumbnails.swift`, `Views/ThumbnailSheet.swift`. Edit Like a Reference:
  `PulseCore/AutoEdit/ReferenceStyle.swift` (`ReferenceStyleAnalyzer.measure` — cuts, punch-ins from face-size
  jumps, caption look/pop-ups from Vision text with persistent overlays removed, pauses from word gaps, music from
  level between words, effect hits from spectral-flux spikes, dips to black; `ReferenceAnswers`; `StyleTuning`
  carried in `LongFormOptions.style` and read by `LongFormEditor.build`; `shortOptions` for shorts),
  `PulseEngine/Analysis/ReferenceScanner.swift` (pipeline + finer frame pass + `VNRecognizeTextRequest`),
  `State/ReferenceController.swift`, `ProjectSession+Reference.swift`, `Views/ReferenceSheet.swift`. Saved styles
  live in `AppSettings.referenceStyles`. It copies editing *rhythm and ingredients*, not specific shots, B-roll,
  memes or music tracks from the reference — those can't be lifted from a finished video. The studio needed no changes — it re-reads its
  gallery folder when it comes to the front. If the studio's document format changes, update the `ThumbStudio*`
  structs (a test decodes PULSE's output with synthesized enum coding, the way the studio does). Not verified
  against a running Thumbnail Studio on a Mac yet. All tuned on synthetic data — real VODs/analytics will need tuning.
- **Viewer speed / updates (1.1.1)** — the viewer builds with `CompositionBuilder.Options.renderEnhancements =
  false` (only already-cached Enhance renders are used; the rest come back as `pendingEnhancements`), installs that,
  renders the pending ones (one per source stretch via `CompositionBuilder.enhanceSpans`, shared parsed asset, utility priority, `enhanceProgress`) and rebuilds. Exports keep rendering everything. In-app updates:
  `PulseCore/Settings/AppUpdate.swift` (version compare, release parsing) + `PulseApp/Support/AppUpdater.swift`
  (checked at launch, every 30 min and on app activation; GitHub latest release → DMG → SHA-256 check → hdiutil/ditto beside the app → a shell helper swaps bundles after
  quit and reopens). Needs the app's folder to be writable; ad-hoc signing means macOS may re-ask for
  Screen Recording/Microphone permission after an update.
- **Online music (1.2.0)** — `PulseCore/Library/OnlineMusic.swift` (YouTube search-page parsing, Creative Commons
  filter `sp=EgIwAQ%3D%3D`, calm-track ranking, credits) + `PulseEngine/Media/OnlineMusicLibrary.swift` (YouTubeKit
  ≥ 0.4.9 local extraction like TubeGrab, 1 MiB parallel ranged downloads, library.json). YouTube may block
  extraction from data-center IPs (GitHub runners); it falls back to built-in beds and logs why. "Creative
  Commons" is YouTube's filter — uploaders' claims aren't verified by PULSE.
- **Editing polish & checks (1.3.0)** — `PulseCore/AutoEdit/EditPolish.swift`: dead-span trimming (no words ≥ 3.5 s
  and excitement ≤ the segment median), sliver removal (< 350 ms without a whole word), 30 ms cut fades, alternating
  jump-cut zooms, music drops, grade, end screen; `EditQualityCheck.run` (fix + report) runs at the end of
  `LongFormEditor.build` and from Edit → Check Edit. Timeline performance: `PlaybackController.clock`/`slowClock`
  carry the playhead (not `@Published` on the controller), `TimelineClipView` is `Equatable` and doesn't observe the
  session/player, lanes only build clips inside the visible window, the ruler scrubs with chase seeking.
- **Ask-first extras (1.3.0)** — `PulseCore/AutoEdit/EditExtras.swift` (`EditExtras` answers, saved in
  `AISettings.editExtras`; `SpeakerAware`, `RetentionCards`, `FacecamPunchIn`, `BeatSync`, `BrollPlacer`,
  `StreamingLoudness`, `LoudnessVerdict`), wired into `LongFormEditor.build` via `LongFormOptions.extras`. Engine:
  `BeatDetector` (onset envelope → autocorrelation tempo + local beat tracking), `OnlineBrollLibrary` (extension
  of `OnlineMusicLibrary`; progressive MP4 ≤ 720p), `MixLoudness` (AVAssetReaderAudioMixOutput over the export
  composition). App: `EditExtrasSheet` (the question), storyboard ▶ preview / trims / approve mode, export
  loudness alert in `ExportsView`. Limits: B-roll and music downloads depend on YouTube allowing extraction
  (blocked from GitHub runners, so CI only sees search + fallback); "Creative Commons" is YouTube's filter, not
  verified by PULSE; facecam punch-ins need the facecam detected at analysis; crosstalk trimming needs speaker
  labels; the loudness fix can lower or level but can't boost an already-leveled quiet mix (AVAudioMix caps at
  1.0); beat detection is a lightweight tempo tracker (steady-beat music; ambient beds may have no clear beat).
- **1.4.0** — `InstantReplay` (plan + apply: splits V1/A1 at payoff+2 s, shifts every later clip, inserts a 0.5× replay
  clip with role `.graphic`, a "▶ REPLAY" tag and a whoosh), `EditPolish.breathingZooms`, `BeatSync.alignMusic`
  continuation pieces, `BrollPlacer.place` removing the meme/sting it replaces, `RemovedSection.Reason.crosstalk`.
  Role `.graphic` on a clip of the main recording means "cutaway": captions (`CaptionLayoutEngine.timelineWords`),
  the story time map in `LongFormEditor.build` and `EditPolish.jumpCutZooms` skip it.
- **1.5.0 UI** — `Theme` gained `accentGradient` / `aiGradient` / `edgeHighlight` / `elevated` / `radiusXL`, and the
  view modifiers `elevation(_:)` and `raisedSurface(cornerRadius:fill:border:)`; use them instead of ad-hoc
  shadows/borders. `PulseButtonStyle` fills primary/AI with the gradients. Sidebar groups live in `Sidebar.groups`.
  `docs/ROADMAP-500.md` is the improvement backlog.
- **1.6.0 roadmap batches** — `docs/ROADMAP-500.md` numbers are cited in commit messages and release notes.
  Core: `StreamEdges` (intro/outro cues), `LongFormOptions.tighten/deadAir/memeTexts`, `EditQualityCheck`
  gained word-safe cuts (`choppedWords` + `rippleExtend`), `closeGaps`, chapter balance and fast-caption notes;
  `Timeline.freezeFrame`, `[ClipCandidate].overlappingPairs`, `ColorAdjustments.look`, `ExportSidecar`,
  `RetentionCards.phrase` / `hideCaptionsUnderCards`, `SearchResultKind.action`, `EngagementLexicon.customProfanity`.
  App: actions in `GlobalSearchView`, `AppModel.quickExport` / `notifyIfInBackground` / `noteVersionChange`,
  `ProjectSession.closeAllGaps` / `freezeFrame` / `nudgeSelection`, `MarkersListView`, the transport bar's
  editable timecode, per-chapter music in `onlineMusicBeds`, sidecar `.txt`/`.srt` + verification in
  `ExportQueueController`. `Tests/PulseCoreTests/TimelineFuzzTests.swift` is the invariant check for every
  timeline edit (run it after touching `TimelineEditor`, `EditPolish` or `EditExtras`).
- **1.6.0 roadmap batches 3–15** — each batch is one commit (`git log --grep 'batch'`), one `Tests/PulseCoreTests/BatchNTests.swift`
  and one section in `versions/1.6.0/NOTES.md`. The bigger core pieces: `AutoEdit/EndCards.swift` (end CTA),
  `AutoEdit/ChapterOutline.swift` (story chapters before the edit), `AutoEdit/ReferenceExplain.swift` /
  `ReferenceBlend.swift`, `AutoEdit/EditReport.swift` (plain-language edit report), `Audio/SpeakerLeveler.swift`
  (guests levelled to the host via hold keyframes), `Audio/AudioCensor` tone + `MonoSource` fold, `Clips/TitleVariations.swift`,
  `Clips/Hashtags.swift`, `Clips/SeriesDetector.swift`, `Timeline/TimelineMerge.swift` (merge moments),
  `Timeline/TimelineSearch.swift`, `Captions/CaptionEdits.swift` (sentence case, fillers, shift-after, platform
  positions), `CaptionLayoutEngine.balanced`, `Export/FCPXMLExporter.swift`, `Export/ReviewPage.swift` (HTML
  review page), `Media/ContentFingerprint.swift` (duplicate imports), `Media/ChapterMark.swift` (file chapters,
  YouTube IDs), `Project/ProjectMaintenance.swift` (schema migration v2, unused media, trash), `Project/ProjectStructure.swift`
  (anonymized bug reports), `Settings/GradePresets.swift`, `Settings/LifetimeStats.swift`, `Settings/NotesChecklist.swift`,
  `History(limit:coalesceWindow:maxCost:)`. Engine: `Media/VODDownloader.swift` (YouTube link import via YouTubeKit),
  `Transcription/Retranscriber.swift` (re-run a stretch), `System/PowerState.swift` (battery-aware batch),
  `MediaProbe` VFR / colour primaries / chapters / one-sided mic detection, `LibraryDatabase` deadline + editing columns.
  App: `Support/Intents.swift` (App Intents + Shortcuts), `ImportURLSheet`, watch folder + nightly batch in
  `AppModel`, the timeline toolbar popovers (search, pauses, notes, undo history, edit report, edit check, minimap)
  in `Views/Editor/TimelinePanel.swift`, inspector search (`InspectorQueryKey`), settings search + Statistics pane,
  smart project filters, deadlines/archive on Home. Every new `Codable` field is decoded tolerantly
  (`decode(_:forKey:default:)`) so older projects and settings files keep loading.
- **1.6.1 roadmap batches 16–21** — same shape as before (one commit, one `BatchNTests.swift`, one section in
  `versions/1.6.1/NOTES.md`). Core: `Timeline/TrimModes.swift` (slip / slide / roll), `Timeline/ClipLabels.swift`
  (labels, drop markers, cuts per minute), `Timeline/ReplaceClip.swift`, `AutoEdit/IntroBumper.swift`,
  `AutoEdit/ProgressBar.swift` (a cropped, keyframed solid — the renderer now places solids like any layer),
  `AutoEdit/ColdOpenCard.swift`, `AutoEdit/HumanizeEffects.swift`, `EditQualityCheck.midSentenceCuts`,
  `Captions/CaptionSpelling.swift`, caption page breaks and keyboard edits in `CaptionEdits.swift`,
  `Search/FuzzyMatch.swift`, `Media/MediaRelinker.swift`, import sidecars in `ImportPlan.make(siblings:)`,
  `Media/RecordingEstimate.swift`, `Export/CloudFolders.swift`, `Common/PerfLog.swift`, `Audio/MixingAdvice.swift`,
  `Settings/Appearance.swift`, `UpdateChannel` + `ReleaseInfo.parseAll`, `WorkflowStage` on documents and summaries
  (library column `workflow`). Engine: `System/AudioOutput.swift` (CoreAudio default output), `System/Connectivity.swift`,
  `FrameRenderer.safeMode`, whisper `speedFactor`. App: `Support/RecordingStatusItem.swift` (menu bar), the
  timeline's marquee / snap line / blade line / label filter / B-roll tray, `ProjectBoard` in `ProjectsView`,
  `CaptionSpellingPopover`, `PlatformChrome` in `ViewerView`, `EffectChoiceRow` and `MonitoringNoteRow` in Settings.
  `Theme.accent` is now computed from `Theme.accentChoice` (set from settings) — never cache it in a `static let`.
- **Local core check (no Mac needed)** — the scratch package `corepkg` (see the `scratchpad` folder of a cloud
  session; recreate it from `Package.swift` with only PulseCore + PulseCoreTests, `Audio/SpectralDenoiser.swift`
  stubbed and `AudioDSPTests.swift` left out) builds and runs the core tests on Linux with the swift.org 6.0.3
  toolchain (345 core tests as of 1.6.1): `./sync.sh && swift build --build-tests && swift test --skip-build`. `swiftc -parse` over every file
  (`parse-all.sh`) catches syntax slips in the engine/app before a 20-minute CI round; type errors there are
  only caught by CI, so read the `COMPILER ERRORS` summary at the end of a failed Build step.
- Cross-dissolves (video + linked audio crossfade) need media handles; at the very start/end of a recording they
  fall back to a fade over lower tracks.
- whisper.cpp itself must be installed with Homebrew (`brew install whisper-cpp`); models download in-app
  (Settings → Transcription). The `.app` bundle can use Apple's on-device speech instead.

## CI tricks (for the next Claude session)

- **Every release updates the README:** the download link text ("Download PULSE x.y.z"), the release-notes link,
  the "New in x.y.z" summary at the top of `README.md`, and the bold top row in `versions/README.md`. The
  release workflow's first step fails the release if any of these don't match `VERSION`.

- Artifact/log blob URLs are blocked from the cloud box. Read CI output with the GitHub MCP tool
  `get_job_logs` (`return_content: true`, `tail_lines` 300–400 is enough for the `COMPILER ERRORS` summary). The
  workflow prints `SNAPSHOT <name> <base64 jpeg>` lines; decode them with a small Python script to view engine
  stills and `ui-*.png` app screenshots.
- Find the jobs of a run with `gh api repos/XmanXay69/PulseAI-Clipper/actions/runs/<run>/jobs --jq '.jobs[] |
  "\(.id) \(.name) \(.status) \(.conclusion)"'`. The workflow's concurrency group cancels an in-progress run
  when you push again, and Apple-silicon jobs are frequently cancelled by GitHub for lack of runners — a run
  whose only failures are those cancellations is not red.
- `PULSE --ui-snapshots <dir>` opens the sample project, visits every section and saves PNGs, then quits.
- `PULSE --render-icon <dir>` writes the app iconset (used by `scripts/build-app.sh`).
- Put `[app]` in a commit message to also build and upload `PULSE.zip` as a CI artifact.

## Next steps

1. Download `PULSE.dmg` from the latest GitHub Release (link in the README), drag it into Applications,
   then try it by hand with a real long recording: import → Analyze & Find Clips → Open in Editor → Export.
2. Report anything confusing or broken; the CI screenshot loop (`--ui-snapshots`) makes UI fixes quick to verify.
3. Candidates for the next build phase: test with real recordings and tune from what breaks (speaker
   clustering threshold, music mix levels, layout morph timing), then notarized Developer ID builds.
4. Keep working through `docs/ROADMAP-500.md`; items done so far are cited by number in `versions/1.6.x/NOTES.md`
   and in the batch commits (about 369 of 500 as of 1.6.2). The big remaining ones (#481–#500: plugins, a render farm, collaborative editing,
   an iOS companion) need design work first.
