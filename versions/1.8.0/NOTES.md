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

### First clips sooner, posts planned, notes back
- **Three clips from your own recording while the rest is analyzed (#1061).** Drop in a recording of twenty
  minutes or more and PULSE copies out its first ten minutes (no re-encoding) and analyzes that on its own
  first: the sound, the words and the facecam, without the slower banner, reaction and speaker passes. Its
  best three moments appear as clip cards while the full analysis carries on, and a toast says how many
  seconds in they arrived. A short can be built from one straight away, captions and layout included,
  from what is known of those ten minutes. They are marked as first looks: when the full analysis lands,
  it replaces any you haven't opened or favourited. Shorter recordings are analyzed in one go, as before,
  and if the copy or the quick pass fails nothing is shown and the full pass carries on.
- **Posting plan (#906).** Exports → Posting plan lays a week of posts out from what is in the project:
  every edit (a wide one is a video for YouTube, a tall or square one a short) and, if you leave it
  ticked, the favourite and 70-plus clip cards that aren't shorts yet, marked "Build first". The rules are the plain ones. The strongest short goes first. One short
  a day, or two or three if you ask, each on every short-form platform you tick, at that platform's time.
  Fewer shorts than days are spread across the week. Two clips of the same moment are never both posted:
  the weaker one is listed under "Not this week" with the reason. With a long video in the plan, the best
  short goes out the day before it as its trailer, and shorts from the same recording after it are noted
  to link back to it. Copy the plan as text, or save a calendar file with one event per post. The default
  times are starting points, not a study of your audience: set your own, and they are remembered. PULSE
  doesn't post anything from here.
- **Review comments onto the timeline (#1181).** Timeline → Export Watch-and-Comment Page makes one HTML
  file next to an exported video. Send both. The reviewer plays the video in a browser and types what
  should change; the video pauses while they type and the comment is stamped with that moment. Their
  comments stay in their browser until they press Copy comments (text to paste into a message) or Save
  comments file. Back in PULSE, Timeline → Import Review Comments or Paste Review Comments puts each one on
  the timeline as an orange marker at its timecode, with who said it in the name and the whole comment in
  the note. Notes that never saw the page work too: any text whose lines start with a time ("0:42 the music
  is too loud", "[1:05] cut this", "0:40-0:46 this drags") is read the same way. Importing the same
  comments twice adds nothing. If the edit has changed length since it was sent, or the comments were
  written on another edit, PULSE says so and places them by time anyway. This is a file you send, not a
  hosted link: PULSE runs no server, nothing is uploaded, and the page loads nothing from the internet.

### A model that plans, a viewer that is checked, a release that can be signed
- **A language model plans the edit (#1281).** In Edit My VOD's storyboard, **Plan with a Language Model**
  sends the recording's transcript to the model you set up in Settings → AI Processing (Claude, or any
  OpenAI-compatible server, including one running on this Mac) and gets back a structure: the line the
  video opens on, the stretches it keeps and in what order, what is dropped inside them, and one sentence
  of reasoning for each. PULSE's own picker hears loudness, laughter and pace; it cannot know that a quiet
  sentence at minute four is what makes minute forty funny. A model that reads the words can. Its plan
  replaces the list in the storyboard, with its reason under each stretch, and you approve, untick, trim
  or reorder it like any other. The same editor then builds it. **Back to PULSE's Plan** discards it.
  - Only text is sent: the words with timecodes, an energy mark per line and the scores of the moments
    PULSE found. Video and audio never leave the Mac. A hosted provider is asked about first, with the
    word count, unless Settings says cloud providers may be used without asking; with Always Local it is
    refused. The request is billed by your provider to your own key.
  - The model answers in line numbers, and nothing it says is trusted as it stands. Line numbers outside
    the transcript are pulled in, a stretch kept twice is kept once, a stretch cut down to nothing is
    dropped, a plan far over the length you asked for loses its asides, and an opening line that isn't in
    the plan is replaced. Every one of those changes is listed above the storyboard in words.
  - A transcript too long for one request is never cut silently: the quietest talk away from every picked
    moment is left out, the gaps are marked in what the model reads, and you are told how much before it
    is sent and again with the plan.
  - With Claude the reply is streamed and bound to a schema, with adaptive thinking at high effort and the
    server-side refusal fallback. Without a model set up, nothing changes: PULSE's own plan is what you get.
- **The viewer's real frame, judged in CI (#1021).** The screenshots CI takes are drawn by the views, and
  the viewer's picture is drawn by the player, so in every capture the viewer was a black box: a release
  could have shipped a viewer that rendered nothing and no screenshot would have shown it. The
  walk-through now renders the frame itself, with the composition the viewer and the export use. A frame
  that is black, one flat colour or the wrong shape fails the run. Each frame is also reduced to a 16 by
  16 grid of colours and compared with a kept reference: a small difference (a caption gone) is a warning
  on the run, a large one (the facecam gone, the layout moved, colours swapped) fails it. And the frame
  is drawn into the window's screenshot where the player shows it, so the captures look like the app.
  [docs/VIEWER-FRAMES.md](../../docs/VIEWER-FRAMES.md) says how to accept a picture that changed on purpose.
- **Signing and notarization, ready for your Apple account (#866).** The first-launch warning goes away
  only with an Apple Developer account (US$99 a year) and five secrets that only its owner can create, so
  this one cannot be finished from here. What is done is everything around it:
  [docs/SIGNING.md](../../docs/SIGNING.md) is the step-by-step; **Actions → Check signing setup** tries the
  secrets in about a minute without building or publishing anything, and says in plain words what is
  wrong (a missing secret, a wrong password, the wrong kind of certificate, an expired one, another
  team's, a sign-in Apple refuses); a release runs the same check first, so a half-finished setup stops
  it in its first minute instead of after half an hour. With the secrets in place the app and the disk
  image are both notarized and stapled (the app too, so it opens offline after being dragged out),
  Apple's reasons are printed if it says no, the release stops unless Gatekeeper accepts the result on
  the build machine, and the release notes drop the first-launch steps. Before this, a signed but
  un-notarized build would have published notes saying it opened with no warning.

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
- Core tests for the head start (only long recordings; the best three moments of the head as clips of the
  recording, none running off its end, no two of one moment; a head-start clip replacing a sound-only first
  look of the same moment), the posting plan (strongest first on every platform; spread over the week; the
  trailer the day before the video and links back after it; one post per moment; a full week saying what
  waits; your own times; text and calendar-file export) and review comments (timecodes however they were
  typed; what isn't a timecode left alone; the page's own file; markers added once; a changed or different
  edit said; a page that an edit's name cannot break and that loads nothing) pass on Linux.
- Core tests for the edit planner (the brief as numbered lines with times, energy and the picker's
  moments; a transcript too long to send marking every second it leaves out; a good answer becoming
  sections in the model's order with its cuts and its opening; a bad answer repaired with every repair
  said; a plan far over length losing its asides; sloppy JSON read and an empty plan refused; the request
  asking Claude for a streamed, schema-bound plan at high effort with nothing the newest models reject; a
  streamed reply collected, a mid-reply fallback handled, a refusal and a cut-off reply reported) and the
  frame check (black and flat frames fail; the wrong shape fails; a change graded by its size; the
  reference file read back) pass on Linux. The signing check's tests of the five values' shapes were run
  by hand here: none set, some set, wrong shapes, not a .p12, right shapes.
- On CI (Apple silicon), the walk-through rendered five viewer frames, judged all five as real pictures of
  the right shape, drew four into their window captures, and wrote the reference now kept in
  `.github/viewer-frames.json`; the posting plan laid the sample's pieces out and its sheet was captured;
  three review comments went onto a copy of the sample edit as markers, one of them past its end.
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
  it is tried on a Mac. The mix's target levels are common practice, not measured on your streams. The
  head start needs a recording of twenty minutes or more, and the sample is seconds long, so the copy of
  the first ten minutes and the quick analysis have compiled on CI but never run: the "inside two minutes"
  figure is the aim, not a measurement, and depends on the Mac and on transcription speed. The review page
  has been checked as text (it is well formed, escapes the edit's name and loads nothing) but has not been
  opened in a browser here: playing, pausing on typing, copying and saving are untested until someone
  tries them, and a browser that blocks local files from playing will show the "choose the video" box
  instead. The posting plan's default times of day are conventions, not data. **The edit planner has never
  talked to a model.** There is no API key here, so no request has been sent: what is tested is the brief,
  the request's shape against the provider's documentation, the reading of replies written by hand in the
  documented format, and the checks on the answer. Whether a model's plans are better than PULSE's own is
  exactly what has not been measured; try it on a stream you know well and judge. The streaming code runs
  only on macOS and has compiled there, no more. Signing, notarizing, stapling and the Gatekeeper checks
  have not run with real credentials (there are none): expect the first signed release to need a look at
  its log. The frame check sees one frame per capture on Apple silicon only; the Intel runner has no GPU
  and stops before the editor.
