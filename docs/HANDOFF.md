# PULSE — Handoff / Status

> Living status document, updated with every push so work can be picked up at any time
> (by you, a new Claude session, or another developer). If you are a new Claude session:
> read this file first, then `git log --oneline | head -20`.

**Branch:** `claude/exciting-bardeen-df149p`
**Build:** Swift Package (`Package.swift`, tools 5.10, Swift 5 language mode), macOS 14+ (Apple Silicon first,
works on macOS 15). CI compiles, tests and screenshots the app on a GitHub Actions `macos-15` runner
(`.github/workflows/ci.yml`) because the cloud dev box used to write it is Linux.

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
| `PulseCore` (pure Swift, 110 unit tests) | Timeline model + all edit ops (split, ripple, trim, speed, link, text-based delete/restore), snapshot undo/redo, `.pulse` project packages (autosave, rotating backups, versions, crash recovery), transcripts (SRT/VTT/whisper.cpp/OpenAI JSON), filler words, silence detection, audio sync, engagement model + AI clip generation (HOOK→CONTEXT→PAYOFF→END, AI Potential), titles/hooks, captions (8 presets, paging, word timing, emphasis, safe areas), streamer layouts + facecam detection, AI reframing, punch-ins, one-click short builder, "Make More Entertaining", templates, export presets/queue, AI provider abstraction + privacy policy (Local / Claude / OpenAI-compatible), settings, global search, multicam (sync groups, angle cuts, AI switching, grid layouts), compound clips (nested timelines), speaker diarization (segmenting, embedding clustering, MFCC fallback clustering, labels) |
| `PulseEngine` (AVFoundation, Vision, Speech, Core Image/Metal, SQLite) | Media probing/import, thumbnails, waveforms, proxies, audio analysis, Vision face detection, Apple Speech + whisper.cpp transcription, composition builder + custom `AVVideoCompositing` compositor (layouts, masks, crops, keyframes, captions, text, color, LUTs, effects, transitions), AVAssetWriter export (H.264/HEVC hardware, ProRes), playback controller, demo media generator, SQLite library index with FTS5 transcript search, ScreenCaptureKit + camera/mic session recorder (pause/resume), audio enhance chain, neural speaker encoder (GE2E LSTM via BLAS) + MFCC fallback |
| `PulseApp` (SwiftUI) | Sidebar app: Home, Projects, Import, AI Clips, Editor (viewer, timeline, inspector, transcript), Captions, Media, Templates, Exports, Settings; onboarding, recovery, ⌘F global search, background jobs, toasts, keyboard shortcuts |

Key files to know:
- `Sources/PulseApp/State/ProjectSession.swift` — every user action on an open project (goes through `edit`/`editTimeline` → undo history → autosave → playback rebuild).
- `Sources/PulseApp/State/AppModel.swift` — app-wide state, projects list, demo project, recovery.
- `Sources/PulseEngine/Composition/CompositionBuilder.swift` + `Rendering/FrameRenderer.swift` — how a timeline becomes pixels (same path for playback and export).
- `Sources/PulseCore/AutoEdit/ShortBuilder.swift` — candidate → finished 9:16 short.
- `Tests/PulseEngineTests/EngineSmokeTests.swift` — end-to-end: demo media → analysis → clips → short → rendered stills → exported MP4.

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

### What CI actually verifies on every push (macOS 15 runner)

- 138 unit/engine tests (timeline edit ops, undo, project save/recovery, transcript parsers, clip generation,
  captions, layouts, export settings, audio DSP, …).
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
- Cross-dissolves (video + linked audio crossfade) need media handles; at the very start/end of a recording they
  fall back to a fade over lower tracks.
- whisper.cpp itself must be installed with Homebrew (`brew install whisper-cpp`); models download in-app
  (Settings → Transcription). The `.app` bundle can use Apple's on-device speech instead.

## CI tricks (for the next Claude session)

- Artifact/log blob URLs are blocked from the cloud box. Read CI output with the GitHub MCP tool
  `get_job_logs` (`return_content: true`). The workflow prints `SNAPSHOT <name> <base64 jpeg>` lines;
  decode them with a small Python script to view engine stills and `ui-*.png` app screenshots.
- `PULSE --ui-snapshots <dir>` opens the sample project, visits every section and saves PNGs, then quits.
- `PULSE --render-icon <dir>` writes the app iconset (used by `scripts/build-app.sh`).
- Put `[app]` in a commit message to also build and upload `PULSE.zip` as a CI artifact.

## Next steps

1. Download `PULSE-app` from the latest green CI run (Actions → run → Artifacts) or run `./scripts/build-app.sh`,
   then try it by hand with a real long recording: import → Analyze & Find Clips → Open in Editor → Export.
2. Report anything confusing or broken; the CI screenshot loop (`--ui-snapshots`) makes UI fixes quick to verify.
3. Candidates for the next build phase: test with real recordings and tune from what breaks (speaker
   clustering threshold, music mix levels, layout morph timing), then notarized Developer ID builds.
