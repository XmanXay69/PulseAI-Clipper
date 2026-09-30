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

- [x] Phase 0 — repository bootstrap, CI (build, unit tests, engine end-to-end test, UI screenshots)
- [x] Phase 1 — core foundation: models, project system, autosave/backups/recovery, app shell ✅ (app compile in CI ⏳ — see below)
- [x] Phase 2 — video engine: import, probe, thumbnails, waveforms, proxies, composition, playback, export (verified by engine test)
- [x] Phase 3 — AI: audio/visual analysis, transcription, clip candidates, scoring, titles, hooks
- [x] Phase 4 — short-form: layouts, facecam, reframing, captions, safe areas, punch-ins
- [x] Phase 5 — pro editing: timeline ops, inspector, keyframes, color/LUT, effects, transitions, text, transcript editing
- [x] Phase 6 — AI auto edit: one-click short, Make More Entertaining, silence/filler removal, strip AI edits
- [x] Phase 7 — export: presets, batch queue, progress/cancel, hardware encoders

✅ = implemented in code. "Verified" means exercised by CI tests. The SwiftUI app has only been verified
by compiling + automated screenshots on CI, not by a human clicking through it yet.

## Honest gaps (architecture only / not yet implemented)

- **Audio enhance** (noise reduction, EQ, compressor, loudness normalize): UI section says "Coming soon"; volume, fades, keyframes, ducking and mute *do* work.
- **Compound clips, multicam, screen capture**: data model hooks exist, no UI/engine yet.
- **Cross-dissolve** between A/B clips renders as a fade-in over the lower layer (not a true two-sided dissolve).
- **Speaker diarization**: transcripts carry speaker IDs from imported files; there is no local diarization model.
- **Cloud AI** (Claude / OpenAI-compatible) is optional and only used for titles/captions copy; untested against live keys in CI.
- **Music/SFX library**: uses media you import (role = Music / Sound Effect); no bundled library.
- Dynamic layouts (switching layout mid-clip) are done by splitting segments, not keyframed layout morphs.

## CI tricks (for the next Claude session)

- Artifact/log blob URLs are blocked from the cloud box. Read CI output with the GitHub MCP tool
  `get_job_logs` (`return_content: true`). The workflow prints `SNAPSHOT <name> <base64 jpeg>` lines;
  decode them with a small Python script to view engine stills and `ui-*.png` app screenshots.
- `PULSE --ui-snapshots <dir>` opens the sample project, visits every section and saves PNGs, then quits.
- `PULSE --render-icon <dir>` writes the app iconset (used by `scripts/build-app.sh`).
- Put `[app]` in a commit message to also build and upload `PULSE.zip` as a CI artifact.

## Next steps

1. Get the `PulseApp` target compiling in CI (first push of the full app — fix errors from `get_job_logs`).
2. Review the `ui-*` screenshots from CI and polish layout/visual issues.
3. Build the `.app` via `[app]` commit, then test by hand on a Mac: import a real long video, analyze, create shorts, export.
4. Fill the honest gaps above, starting with audio enhance (AVAudioUnitEQ / dynamics processor in the export mix).
