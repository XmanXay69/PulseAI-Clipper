## PULSE 1.2.0

### New
- **Creative Commons music, found and downloaded for you** — Edit My VOD now searches YouTube with its
  Creative Commons filter for calm background tracks (lo-fi, chill, ambient, soft acoustic; loud, vocal, "epic",
  hour-long and unclear-rights uploads are skipped), downloads just the audio with the same engine as TubeGrab
  (YouTubeKit, local extraction only, parallel ranged downloads) and keeps it in a music library
  (~/Library/Application Support/PULSE/Music Library) so tracks are reused. A credit line per track is added to
  the edit's description (Notes) — paste it into your YouTube description. Turn it off in the Edit My VOD sheet;
  offline it falls back to the built-in calm beds.
- **Better gameplay moments** — for gameplay recordings, on-screen action (fights, kills, chaos) now counts much
  more when PULSE picks moments, not just how loud you are.

### Changed
- **Music sits under you, not over you** — every bed is leveled first (so a loud track and a quiet one end up the
  same), placed about 22 dB under your voice, ducked another 14 dB while anyone talks, with long fades. Tracks
  repeat to fill a chapter instead of stopping early. The built-in fallback now uses only calm beds.
- **Captions you can read anywhere** — no box behind them: white bold text with a dark outline and a soft
  shadow, a bit smaller (YouTube edits 42 pt, TikTok style 66 pt), 7 words max per screen on YouTube edits.
  Reference-matched captions can't blow up either.

### Fixed
- **"Leveling audio" no longer sits at 0 %** — the bar moves as audio is processed (it used to only move when a
  whole stretch finished, and stretches could be 10 minutes long). Stretches are now at most 2 minutes, and each
  one is written to the app log.
