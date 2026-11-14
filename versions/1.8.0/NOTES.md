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

### Finding more, risking less
- **Music in the recording (#521).** PULSE now hears when the recording itself has a music track playing:
  a steady level with a regular beat held for a quarter of a minute or more, including a track running
  under talking. Where an edit uses such a stretch the coach says "Music in the recording" with the times,
  and Exports shows the same warning before anything is posted. **Silence It** mutes the recording's own
  sound over those stretches with a short fade each side; the picture, the captions and PULSE's own music
  stay, and one undo brings it back. It is a rule of thumb from rhythm and steadiness, not a song match:
  it does not know what the track is, it can miss quiet music under loud game sound, and it can flag a
  rhythmic game soundtrack. Short jingles under fifteen seconds are left alone.
- **Reactions on camera (#501).** During analysis PULSE reads the face in the facecam, or filling the frame
  on a talking-head recording, about once a second: how open the mouth is, how wide, how open the eyes,
  how high the brows. A change well past that person's own resting face counts as a reaction beside the
  sound, so a silent jaw-drop or a grin can make a moment, and "why this was picked" says "a reaction on
  camera". Shapes only, measured on this Mac with Apple's face landmarks: nobody is identified and no
  picture is kept. Settings → AI Features → "Read reactions on camera" turns it off. It adds a minute or
  two per hour of video, and recordings analyzed before this need analyzing again to get it.

### Learning from what really happened
- **The real retention graph on the timeline (#936).** After a video is up, export its audience retention
  from YouTube Studio (Analytics → the video → Engagement → Audience retention → See more → the download
  arrow → CSV) and bring it in with Timeline → Import Retention Graph… or the coach panel's "Import real
  retention…". The curve is kept with the edit and drawn along the ruler in the accent colour, over the
  predicted one, with a red mark under each stretch where viewers left fastest. Any CSV with a position
  column and a retention column reads: percentages, fractions or timecodes. A graph imported for another cut
  of the video is called out instead of being drawn against the wrong timeline.
- **What your audience leaves during (#937).** With the real graph in, the coach says where viewers left
  ("Viewers left at 0:42: 12 in every 100 who started were gone within ten seconds") and what was on screen:
  a shot held twelve seconds or more, dead air, a flat stretch of the recording, or nothing the edit
  explains. Held shots and dead air come with the fix. Each imported video also adds to a profile of your
  channel: how much faster or slower your viewers leave during each of those than on average. From two
  videos on, Settings → Performance says what stands out ("Your viewers leave 1.8× faster during held
  shots") and the coach gives held shots less room, or more, by up to a third. The first thirty seconds are
  never counted: every video loses viewers fastest there. A video is counted once however often its graph
  is imported, and Forget clears the profile.

### Finishing an edit faster
- **Dialogue-first mix (#761).** Timeline → Dialogue-First Mix, or the dial in the timeline toolbar, takes
  the voice as the reference and places everything else under it: game sound 10 dB below and set to drop
  another 9 while someone talks, music 20 dB below and set to drop another 6, sound effects no louder than
  4 dB under the voice. A voice far from a normal speaking level is brought to it first, and voice clips
  that differ from each other are evened out. It then lists what it changed in words ("Music down 14 dB to
  sit 20 dB under the voice and set to drop another 6 dB while someone talks"). It only moves clip gain and
  switches ducking on; the sound itself is untouched and one undo puts every level back. Levels come from
  each recording's analysis, or its waveform for library music and effects; a sound it can't measure is
  left alone, and a recording with no separate microphone is treated as the voice, since its game sound
  can't be separated.
- **Rebuild one pass (#1101).** Timeline → Rebuild with Edit My VOD's Settings redoes just the zooms, the
  pop-ups, the sound effects, the caption look or the tease of a YouTube edit, with whatever Edit My VOD is
  set to now. Pick another editing style there, then rebuild only the zooms: the cut, your trims, your own
  text and the other passes stay. New items are placed by where they sit in the recording, not on the
  timeline, so an edit you trimmed or reordered by hand still gets them in the right places, and nothing is
  placed on a moment you cut. Zooms and text you made yourself are never removed. One undo step.
- **Trim while it loops (#661).** With the playhead near a cut, the new timeline toolbar button (or
  Timeline → Trim the Nearest Cut While It Loops) plays two seconds either side of that cut over and over.
  J and L move the cut one frame earlier or later, five with Shift; the comma and full-stop keys do the
  same. Picture and sound move together, the edit keeps its length, and the cut stops where a clip or the
  recording runs out. K, Esc or Return stops and says how far the cut moved. All the presses are one undo.

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
- Core tests for the music detector (a track found; talking, steady noise and silence not; other tempos;
  music under talking; a jingle ignored; an edit flagged where it uses the music; silencing only that) and
  the face signal (the four measures follow the face; a reaction stands out from that person's rest; a
  silent reaction lifts its moment and is named) pass on Linux, on synthetic sound and synthetic landmarks.
- Core tests for retention (YouTube Studio's table and other shapes of it read, junk refused; the steepest
  fall found and blamed on what was on screen; the coach's leak advice and a stale graph; a channel profile
  learned across videos, counted once each, tightening only the rule it supports) pass on Linux.
- Core tests for the mix (music and effects brought under the voice; a quiet voice raised and the rest
  following; game sound under a separate mic; nothing guessed; levels from an analysis or a waveform), the
  rebuild (only the zooms change; a new zoom lands on the same instant of the recording after a hand trim;
  each pass on its own; your own text kept) and the looping trim (the nearest cut; a frame a press with
  picture and sound together; stopping where a clip or the recording ends) pass on Linux.
- Not checked: the predicted retention against real audience retention. It is a rule of thumb. The loop
  and the opening lines have run on synthetic clips and the generated sample, not on real shorts. The story
  reading is keyword and position based: it has been tested on scripted transcripts, not on real streams,
  and it reads English only. The generated sample is too short for a tease, so the tease has only run in
  tests. The music detector has never heard a real recording: its thresholds come from synthetic signals.
  The face reader's Vision pass compiles and runs on CI, but the sample's facecam is a drawing, so it has
  not read a real face anywhere yet. The retention importer was written from YouTube Studio's documented
  export (a position column and an absolute-retention column) and tested on tables shaped like it: no real
  export file was available here, so try one and say if it is refused. Trim while it loops has not been played by anyone: the cut
  arithmetic is tested, but how the loop feels while the picture rebuilds after each press is unknown until
  it is tried on a Mac. The mix's target levels are common practice, not measured on your streams.
