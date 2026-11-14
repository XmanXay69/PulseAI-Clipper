## PULSE 1.8.0 (in progress)

The first twenty items of [the 800 ideas](../../docs/IDEAS-800.md), built in the order that list gives.
This file grows as each one lands; the numbers are the list's.

### Editing styles everywhere
- **A style for each kind of recording (#626).** Settings → AI Features → Editing style has one switch:
  "Cut each recording in the style that suits it". On, Edit My VOD opens on Retention cut for gameplay,
  Clean commentary for podcasts and talking-head recordings and Story first for anything else; the overnight
  batch and the one-click pipeline use the same style when you haven't picked one; shorts take the Punchy
  short pacing, zooms and effects and keep the caption look you chose. Each kind has its own menu, PULSE's
  own way included. A recording that isn't analyzed yet gets its style when the edit starts, once PULSE
  knows what kind it is. Edit My VOD has the same switch as a checkbox. Off by default: nothing changes
  until you turn it on.
- **Compare two styles (#627).** Edit My VOD → "Compare two…" drafts the open recording in two styles and
  shows them side by side: the coach's score and its seven factors, a predicted retention curve with the
  average share watched, and what each edit is made of (length, how often it cuts, zooms, pop-ups, sound
  effects, captions, music). Under them, a verdict in words: who is ahead, by how much and on what. "Use"
  sets Edit My VOD to that style; the full edit is built when you press Edit My VOD. The drafts are the
  picture, zooms, captions and pop-ups only: no music search, B-roll or audio levelling.
- The retention guess now follows an edit through its cuts and gives a little attention back at every
  change of picture, where before it only described the raw recording.

### Checked
- Core tests for both (default style per kind, your own pick per kind, old settings read as off; the edit
  retention curve; two trials and a verdict) pass on Linux. macOS results are filled in at release.
- Not checked: the predicted retention against real audience retention. It is a rule of thumb.
