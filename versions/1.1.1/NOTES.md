## PULSE 1.1.1

### Fixed
- **Edits show up in the viewer instantly.** After Edit My VOD (or any edit with volume leveling / Enhance
  audio), the viewer used to wait until a processed audio file had been rendered for every clip — with hundreds
  of jump-cut clips that took a long time, whichever caption model you use. The picture now appears right away
  with the original audio, the leveled audio renders in the background (several at once) and swaps in without
  moving the playhead. A small "Leveling audio…" tag shows while that happens. Exports are unchanged.

### New
- **Update from inside the app.** PULSE checks GitHub once a day; when a new version is out, the version badge
  (top right) turns into **Update to x.y**. Click it (or PULSE → Check for Updates…, Help menu, Settings →
  General) to see what's new, then **Install & Relaunch** — it downloads, verifies the checksum, replaces the app
  and reopens. Your projects, settings and downloaded caption models (e.g. Large v3 Turbo) live outside the app,
  so nothing is re-downloaded. Updating from 1.1.0 needs this one manual install; after that it's one click.
