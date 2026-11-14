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

### Shorts
- **Make it loop (#541).** The coach looks for an ending that cuts cleanly back to the opening and offers
  it as "Make it loop": end between phrases, where the sound sits at about the level the opening starts
  at, and best of all on words left hanging for the opening to finish ("…and that's when"), a question, or
  a return to the words the short opened with. It never cuts through a word, before the payoff, or more
  than the last third. The fix trims the ending in one undo step. The **Loop** button in the coach panel
  plays the last seconds into the opening three times so you can hear and see the seam.
- **Opening lines (#542).** For a short made from a clip, the coach panel's Opening menu offers five lines
  for the first two seconds: a question, a claim, the stakes, a tease and the clip's own words. Each is
  true to the clip. The question is one that was asked when there is one, the stakes name the banner the
  game put on screen, the tease counts down to the payoff that is really there ("WAIT 9 SECONDS"), and the
  quote is made of words that were said. Choosing one puts it high in the frame for two seconds; choosing
  another replaces it. Written on this Mac from the clip, with no cloud model.
- **Caption pages split at reading speed (#721).** A page that would need reading at more than about twenty
  characters a second (the subtitling standard for adults) is shown a few words at a time instead, split at
  a comma or a breath when one is near the middle. Fast talk can't be slowed, but a small page takes a
  glance, not a read. On for new captions, with a switch in Captions → Style; captions in projects saved
  before this keep the pages they had. One-word-at-a-time captions and page breaks set by hand are untouched.

### Long videos that tell a story
- **The story in the moments (#581).** "Choose moments…" in Edit My VOD now reads the kept moments as a
  story: which is the goal, which are obstacles, which are attempts, which is the result. The reading comes
  from what was said in each moment ("we're going to…", "oh no", "one more try", "we did it"), its tags and
  where in the stream it sits. Each row carries its beat, the header says what there is ("A goal, 2
  obstacles, an attempt and a result") and names what is missing with something to do about it. **Arrange
  as a story** puts the goal first even when it was said twenty minutes in, keeps the setbacks and tries in
  the order they happened, and ends on the strongest result. Nothing is sent anywhere.
- **A tease that is kept (#582).** Edit My VOD has a **Tease** switch: a small line in the first half minute
  ("COMING UP: THE CLUTCH") that points at the strongest moment landing in the second half of the edit, not
  the one the cold open already shows. Retention cut and Story first turn it on. The promise is stored with
  the edit and checked after every change: cut the moment, or move it in front of the tease, and the coach
  says "The tease isn't paid off" with a one-click removal. A long edit with no tease gets a "Give them
  something to stay for" tip that plants one. PULSE only ever promises a moment that is really in the edit.

### Checked
- Core tests for both (default style per kind, your own pick per kind, old settings read as off; the edit
  retention curve; two trials and a verdict) pass on Linux. macOS results are filled in at release.
- Core tests for the loop (a hanging ending beats a trail-off; questions and returns to the opening; never
  through a word, before the payoff or too early; the coach's offer), the opening lines (five kinds, all
  different, short enough, true to the clip; one line on the short at a time) and reading-speed pages
  (unhurried speech untouched; a burst split at a phrase boundary with no word lost; old projects not
  re-paged) pass on Linux.
- Core tests for the story (a challenge stream read beat by beat; a goal said late told first; what is
  missing named; no transcript) and the tease (planted for a moment that really lands late; a cut moment
  caught and the coach's fix; offered on a long edit, never on a short) pass on Linux.
- Not checked: the predicted retention against real audience retention. It is a rule of thumb. The loop
  and the opening lines have run on synthetic clips and the generated sample, not on real shorts. The story
  reading is keyword and position based: it has been tested on scripted transcripts, not on real streams,
  and it reads English only. The generated sample is too short for a tease, so the tease has only run in
  tests.
