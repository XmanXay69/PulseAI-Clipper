## PULSE 1.1.2

### Fixed
- **Play works right away after Edit My VOD.** In 1.1.1 the edit appeared instantly but could refuse to play while
  its audio was being leveled: every jump-cut piece got its own render, each re-opening the whole VOD file, and
  that starved the player. Leveled audio is now rendered once per stretch of the stream (a few dozen instead of
  hundreds), from one opened copy of the file, at low priority — so playback comes first and leveling finishes
  much sooner.
- **Percentage bar** — the viewer shows "Leveling audio NN%" while it works. You can play and edit meanwhile
  (the original audio plays until the leveled audio swaps in).
- If the viewer ever can't play something, it now says why instead of doing nothing.

### Changed
- **Updates show up as soon as they're released.** PULSE checks when it opens, every 30 minutes, and whenever you
  switch back to it. A highlighted **Update to x.y** button appears top right with a one-time notice — click it,
  then Install & Relaunch. Your projects, settings and caption models are kept.
