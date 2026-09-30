# PULSE — Handoff / Status

> Living status document. Updated with every push so work can be picked up at any time
> (by you, a new Claude session, or another developer).

**Branch:** `claude/exciting-bardeen-df149p`
**Build:** Swift Package (`Package.swift`), macOS 14+ (Apple Silicon first). CI compiles and tests on a
GitHub Actions macOS runner (`.github/workflows/ci.yml`) because the cloud dev box is Linux.

## Architecture

| Module | What it is | Status |
|---|---|---|
| `PulseCore` | Pure-Swift models + algorithms: timeline & edit ops, undo/redo, project packages (autosave, backups, versions, crash recovery), transcripts (SRT/VTT/Whisper JSON), filler words, silence detection, audio sync, engagement model + AI clip generation & scoring, titles/hooks, captions (styles, paging, word timing, safe areas, emphasis), streamer layouts, AI reframing, punch-ins, one-click short builder, "Make More Entertaining", templates, export presets/queue, AI provider abstraction (Local / Claude / OpenAI-compatible), settings, global search | Written + unit tested |
| `PulseEngine` | macOS engine: AVFoundation probing/thumbnails/waveforms, audio & visual analysis, Vision face detection, Apple Speech / whisper.cpp transcription, composition builder + Core Image compositor (layouts, masks, captions, effects), AVAssetWriter export, playback | In progress |
| `PulseApp` | SwiftUI app: sidebar, Home, Projects, Import, AI Clips, Editor (viewer, timeline, inspector, transcript), Captions, Media, Templates, Exports, Settings, onboarding, recovery | In progress |

## Phase status

- [x] Phase 0 — repository bootstrap, CI
- [ ] Phase 1 — core foundation (models ✅, project system ✅, app shell ⏳)
- [ ] Phase 2 — video engine
- [ ] Phase 3 — AI (algorithms ✅ in core; engine analysis ⏳)
- [ ] Phase 4 — short-form editing (core ✅; rendering ⏳)
- [ ] Phase 5 — professional editing
- [ ] Phase 6 — AI auto edit (core ✅)
- [ ] Phase 7 — export

## How to build on a Mac

```bash
git clone https://github.com/XmanXay69/PulseAI-Clipper.git
cd PulseAI-Clipper
git checkout claude/exciting-bardeen-df149p
swift build            # or open Package.swift in Xcode 16+
swift test
./scripts/build-app.sh # produces build/PULSE.app
```

## Next steps

See the bottom of this file after each push for the exact next task.

**Next:** finish PulseEngine + PulseApp shell, get CI green.
