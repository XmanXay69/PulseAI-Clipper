## PULSE 1.3.0

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
