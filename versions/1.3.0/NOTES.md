## PULSE 1.3.0

### Extras — PULSE asks first
Pressing **Edit My VOD…** now asks which extras you want. Nothing in this list happens unless you tick it, and
PULSE remembers your answers as next time's starting point.
- **Facecam punch-ins** — on gameplay with a facecam, the biggest reactions push in on your face instead of the
  middle of the game, hold, and come back.
- **B-roll cutaways** — short Creative Commons meme/reaction clips, found and downloaded from YouTube with the
  built-in TubeGrab engine, cut in for ~2 s on the funniest moments (own "V2 B-roll" track, sound on the effects
  track, credits in the description). Kept in a B-roll Library and reused when offline.
- **Beat-synced music & zooms** — PULSE finds the beat of each music track; music pieces start on a beat and zoom
  hits are nudged (≤ 0.2 s) onto beats.
- **Speaker-aware cuts** — sections start and end on whole sentences, so nobody is cut off mid-thought; with speaker
  labels, stretches where people talk over each other (away from the punchline) are trimmed.
- **Approve the cut** — before anything is built, review every section: ▶ preview it, keep or drop it, move its
  start and end in 2-second steps, choose the hook, then **Approve & Build**. (The storyboard from **Choose
  Moments…** has the same preview and trim controls.)
- **Retention title cards** — short "THEN THIS HAPPENED…" / "20 MINUTES LATER…" cards where the video jumps ahead in
  the stream (at most one every 90 s, never on top of other text).
- **Loudness check at export** — measures the finished mix the way the export will sound (YouTube plays everything
  at −14 LUFS). If it's too loud or clips, it offers to turn it down; if it's quiet and some talking isn't leveled,
  it offers to level it. **Fix & Export / Export As Is / Cancel** — nothing changes unless you choose Fix (and
  that's undoable). Also a checkbox in Export.
- **Edit Like a Reference** asks the same question; the **overnight batch** can't ask, so it uses your last answers
  (never "Approve the cut") and says so in the batch window.

### Fixed
- When two big punchlines fell inside one music piece, only the second got its music drop.

### Edit My VOD, edited like an editor would
- **Boring stretches gone** — long stretches where nobody talks and nothing happens on screen are trimmed, even
  when game audio keeps the silence detector from seeing them (fights, screams and laughter stay).
- **No slivers** — flash frames and half-breaths (pieces under 350 ms without a whole word) left between cuts are
  removed.
- **No clicks at cuts** — every dialogue cut gets a 30 ms fade, the way editors clean jump cuts.
- **Hidden jump cuts** — inside a stretch, every other jump cut steps the framing in a little (the standard YouTube
  trick), so cuts read as deliberate instead of glitchy. Resets at each new section.
- **Chapter transitions** — big jumps in the stream get a quick zoom-through (with the whoosh) instead of a hard cut.
- **Music gets out of the way** — on the three biggest punchlines the music drops out for a beat, then comes back.
- **Gentle grade** — a touch more contrast and colour on the footage; never a filter look.
- **End screen** — 10 seconds at the end with "Thanks for watching" on the left and the right side clear for
  YouTube's end-screen cards; the music plays out under it.
- **Automatic edit check** — after every edit PULSE checks for slivers, clicks, black gaps, loud music, overlapping
  text, crowded zooms, very fast cutting, too-short chapters and length, fixes the mechanical ones and lists the
  rest. Run it on any edit with **Edit → Check Edit (⇧⌘K)**.

### Faster timeline
- The timeline no longer redraws every clip 30 times a second while playing or scrubbing — only the playhead moves.
- Only clips in view are drawn (long edits have hundreds), so scrolling and zooming stay smooth.
- Scrubbing follows the mouse instantly and the picture catches up without queueing seeks; it lands on the exact
  frame when you let go. Panels that follow the playhead (transcript, captions word list, inspector) update a few
  times a second instead of 30.
