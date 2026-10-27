## PULSE 1.6.3

A hardening pass on top of [1.6.2](../1.6.2/NOTES.md): the roadmap is complete, so this build goes back over
the engine code the last batches shipped and makes each piece behave the way the frameworks expect, before
any of it meets a real recording.

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

### Under the hood
- `ExportPump.transferMultiPass` keeps the last pass description it started, so a description announced twice
  (once on registration, once on change) starts one request.
- `YouTubeUploader.resumeOffset(session:size:fallback:reason:)` and `lastByte(in:)` are the status query and
  the `Range` parse; `recoveries` caps the retries at five, `resends` the refused pieces at three.
- `DubSynthesizer.speak(_:with:)` is the one-shot continuation around `AVSpeechSynthesizer.write`.
- `PluginRegistry.DrainedPipe` reads a pipe to its end on a background thread.
