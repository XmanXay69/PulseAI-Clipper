# PULSE — Handoff / Status

> Living status document, updated with every push so work can be picked up at any time
> (by you, a new Claude session, or another developer). If you are a new Claude session:
> read this file first, then `git log --oneline | head -20`.

**Branch:** `claude/exciting-bardeen-df149p`
**Build:** Swift Package (`Package.swift`, tools 5.10, Swift 5 language mode), macOS 14+ (Apple Silicon first,
works on macOS 15). CI compiles, tests and screenshots the app on a GitHub Actions `macos-15` runner
(`.github/workflows/ci.yml`) because the cloud dev box used to write it is Linux.

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
| `PulseCore` (pure Swift, 76 unit tests) | Timeline model + all edit ops (split, ripple, trim, speed, link, text-based delete/restore), snapshot undo/redo, `.pulse` project packages (autosave, rotating backups, versions, crash recovery), transcripts (SRT/VTT/whisper.cpp/OpenAI JSON), filler words, silence detection, audio sync, engagement model + AI clip generation (HOOK→CONTEXT→PAYOFF→END, AI Potential), titles/hooks, captions (8 presets, paging, word timing, emphasis, safe areas), streamer layouts + facecam detection, AI reframing, punch-ins, one-click short builder, "Make More Entertaining", templates, export presets/queue, AI provider abstraction + privacy policy (Local / Claude / OpenAI-compatible), settings, global search |
| `PulseEngine` (AVFoundation, Vision, Speech, Core Image/Metal, SQLite) | Media probing/import, thumbnails, waveforms, proxies, audio analysis, Vision face detection, Apple Speech + whisper.cpp transcription, composition builder + custom `AVVideoCompositing` compositor (layouts, masks, crops, keyframes, captions, text, color, LUTs, effects, transitions), AVAssetWriter export (H.264/HEVC hardware, ProRes), playback controller, demo media generator, SQLite library index with FTS5 transcript search |
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

### What CI actually verifies on every push (macOS 15 runner)

- 89+ unit/engine tests (timeline edit ops, undo, project save/recovery, transcript parsers, clip generation,
  captions, layouts, export settings, audio DSP, …).
- **Engine end-to-end:** generate a 75 s gameplay+facecam stream → probe → analyze (audio + Vision faces) →
  AI clip candidates → one-click 9:16 short (split-screen, captions, normalized dialogue audio) → rendered
  stills → exported H.264 MP4 → landscape re-layout → two-sided cross-dissolve.
- **Real speech-to-text:** macOS `say` → whisper.cpp (tiny.en) → word-timed transcript
  (“No way, that was the craziest clutch I have ever seen. Let's go.”).
- **The app itself:** launches, builds the sample project, visits every section, screenshots them, grabs a
  live viewer frame, opens ⌘F search, and exports the short through the app's export queue (≈8.8 MB MP4).
- **Release bundle:** `scripts/build-app.sh` builds, icons, ad-hoc signs and zips `PULSE.app` on `[app]` commits.

Not verified by CI: a human clicking through with real long recordings, Apple Speech (needs a permission
prompt), cloud AI providers with live keys.

## Honest gaps (architecture only / not yet implemented)

- **Noise reduction** is a downward expander (quiets the floor between words), not spectral denoising.
  Upgrade path: vDSP FFT spectral subtraction or an ML denoiser inside `AudioEnhanceChain`.
- **Compound clips, multicam, screen capture**: data-model hooks only, no UI/engine yet.
- **Speaker diarization**: transcripts keep speaker IDs from imported files; there is no local diarization model.
- **Cloud AI** (Claude / OpenAI-compatible) is optional, used only for titles/captions copy; untested with live keys.
- **Music/SFX library**: uses media you import (role = Music / Sound Effect); nothing is bundled.
- Dynamic layouts (switching layout mid-clip) are done by splitting segments, not keyframed layout morphs.
- Cross-dissolves need media handles; at the very start/end of a recording they fall back to a fade over lower tracks.
- Audio crossfades under video dissolves are not automatic (use fades on the audio clips).

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
3. Candidates for the next build phase: spectral noise reduction, audio crossfades for dissolves, compound
   clips, multicam switching UI, screen/webcam capture (ScreenCaptureKit + AVCaptureSession).
