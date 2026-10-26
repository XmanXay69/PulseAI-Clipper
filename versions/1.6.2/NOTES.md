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

#### Already there, now on the list
- Chat bursts count toward every moment's score once a chat replay is attached (#26); the media grid and the
  timeline are virtualized (#386); when whisper.cpp isn't there, Apple's on-device speech takes over (#400);
  the viewer's strip shows the format, resolution and frame rate (#419).

### Under the hood
- `ChapterArt` (engine) draws with AppKit on the source frame, so a marker over a cutaway or gap is skipped.
- `PlaybackController.load(renderScale:)` passes a smaller `renderSize` to the composition builder; the
  periodic time observer compares media time against the wall clock and publishes `isStruggling`, which
  `ProjectSession` turns into a `playbackQualityOverride`.
- `MemoryPressure` (engine) wraps a `DispatchSourceMemoryPressure` and reads the process footprint with
  `task_info`; `ThumbnailService.setMemoryCeiling` / `trimMemory` act on it.
- `LoopPoints` (core) finds the seam in a peak envelope and `segments(loop:trackDuration:duration:)` lays the
  pieces; `LongFormEditor` uses it for music beds when the app hands it the bed's peaks.
