## PULSE 1.9.0 (in progress)

### Pick the genre, get the edit
- **A genre button in Edit My VOD.** The sheet now opens with "What kind of video is this?" and seven
  buttons: **Stream highlights**, **Gaming video**, **Challenge or story**, **Vlog**, **Commentary or
  podcast**, **Cinematic**, **Montage**. Pick one and PULSE cuts in the style that kind of video is edited
  in: the switches below change to match, the coach judges the result by that genre's rules, and the
  project remembers the choice, so the next edit and the overnight batch use it without asking. A dot
  marks the genre the recording looks like (a game with a facecam is nearly always a stream). The
  "Editing style" menu underneath is still there for choosing a style by name or PULSE's own way.
- **Two new styles**, because two genres had none of their own:
  - **Stream highlights**: the best of the stream in order, with queues, menus and wandering cut, the
    line that sets a moment up kept, and the reactions left in. A light touch: clean cuts, a push-in on
    the reaction, a soft join between moments. No burned-in captions, memes or added music; those are
    for the shorts cut from it. This is deliberately not the same as Gaming video, which is the dense
    edit with zooms and sound on the jokes.
  - **Vlog**: a day told as a story, cut to music. Quicker cuts, a tease for the best later moment, and
    the rule that something new should be on screen within half a minute.
- **The older styles learned a line each** from the same reading: point at the joke instead of burying
  it in effects (Gaming video), hide the join where a pause was cut out of one shot (Commentary), give
  the shot that matters more time than seems necessary (Cinematic), hold back before the drop (Montage).
- **Where each genre's rules come from** is one click away under the buttons: its principles, the
  articles they were read from and the videos that were watched for them (marked "Watched:"), and a plain
  sentence saying what the watching did and did not settle for that genre.

### Study a video with a language model
- **"Ask what it teaches" in Edit Like a Reference.** PULSE already measured a video you like (cut rate,
  zooms, captions, music, sound effects). It now also keeps what was said in it and the text it read off
  the frames, and the language model you set up in Settings can read those and list the editing rules
  the video teaches (a tutorial) or follows (an edited video): each rule with the timecode and words it
  came from. The lessons are saved with the style and shown under its fingerprint.
- **The lessons change edits in two places.** If the model found the video opens on its best moment,
  "open with a hook" is the suggested answer for that style, whatever the cut rate of its first seconds
  said. And **Plan with the model** in Edit My VOD is now given the rules of the style in use: a studied
  video's rules about openings, pacing and story, or a built-in style's principles, which until now the
  planning model was never shown.
- **Videos you studied can be picked in Edit My VOD.** The "Editing style" menu lists them under the
  built-in styles ("Like …"), so a studied video is a style like any other there.
- **What the model can and cannot know.** It reads words and numbers. It does not see the picture or
  hear the sound, and the card says so. Only text is sent, after the same question the edit planner
  asks, and the words stay in PULSE's cache: a style studied before this version has none, and says to
  study the video again.
- It works with a Claude API key, with a model running on this Mac, and in PULSE Dev (below).

### PULSE Dev: a build of your own that uses your Claude account
- **`./scripts/build-dev-app.sh`** builds "PULSE Dev", a copy for the Mac it is built on, that can ask
  the Claude Code installed and signed in there. Titles and captions, caption translation, Plan with the
  model and Ask what it teaches then run on your Claude plan instead of an API key, with
  `claude-opus-5-5` unless you choose another model. Settings → AI Processing → Cloud AI provider →
  **Claude Code (your Claude account)**, with a Test Connection button.
- **It is not in the download and cannot be.** Anthropic does not let other products offer a Claude
  login to their users; a released app uses an API key, which is what the public PULSE has. The bridge
  is compiled only when the dev script asks for it, the public build script refuses a binary that
  contains it, and CI checks both on every push. [docs/DEV-BUILD.md](../../docs/DEV-BUILD.md) has the
  steps, what is sent, what it costs against your plan's limits, and what to do when it stops working.
- **What was tested.** Real requests through Claude Code 2.1.325 on a Linux machine: a connection test,
  titles, a translation, an edit plan and a study, all answered by `claude-opus-5-5`. Not yet run on a
  Mac under a Claude Max sign-in; the build script ends by asking Claude Code for one word and prints
  what happened, so the first build is that test.

### What "studied" means here, honestly
- The genres were first written from published articles and editors' written breakdowns (Finzar's
  newsletter, a breakdown of how Neebs Gaming cuts for comedy, a streamer's guide to Twitch-to-YouTube,
  two write-ups of Casey Neistat's vlogs, StudioBinder on rhythm, PremiumBeat on the basic cuts, montage
  guides). The numbers in that first version were judgement written down from that reading.
- **On 14 November 2026 the videos were watched.** The `/watch` skill
  ([bradautomates/claude-video](https://github.com/bradautomates/claude-video), MIT, installed at
  `.claude/skills/watch`) was run on a Mac, where YouTube lets the download through, with the local engine
  (yt-dlp, ffmpeg frames, captions). 45 videos were watched: 14 of Finzar's (the beginner gaming guide, the
  2026 viral-gaming video, the smoothness video, sound effects, memes, music, transitions and the rest),
  and 31 more across gaming, stream clips, vlogs and story, cinematic, commentary and podcast, shorts and
  montage. 29 of the 45 were on the list in [docs/EDITING-STUDY.md](../../docs/EDITING-STUDY.md) and 16
  were found by search where the list had gaps (more Finzar, two stream tutorials, six on commentary,
  podcast and video essays, three on montage).
  [docs/EDITING-STUDY-FINDINGS.md](../../docs/EDITING-STUDY-FINDINGS.md) has every claim with its video
  and the time it was said or shown.
- **What "watched" does not mean.** Frames and captions were read; nobody listened to the audio, so every
  sound level here is a number a tutor said or a fader value on screen, never a listening judgement. Cut
  rates were counted with ffmpeg's scene filter and are floors: it misses jump cuts on one camera and
  counts transition flashes. Two montage videos had only auto-translated captions (Bengali, Arabic).
- **What moved** (a number moved only where two or more independent videos disagreed with it):
  - Gaming video: punch-in ramp 0.16 s to 0.12 s (text pops settle in about 0.1 s; zoom keyframes are
    "a couple of frames" apart); caption words at once 4 to 3.
  - Challenge or story: the promise by 20 s instead of 15 s; a new section every 120 s instead of 150 s.
  - Vlog: 10 cuts a minute and 6 s shots to 6 and 9 s (Neistat's own edit runs 4 to 6 cuts a minute,
    Dovey's 4 to 7), promise by 20 s, a new section every 120 s. This also drops the vlog's pace from
    "fast" to "steady", so it no longer punches in on every sentence (that starts at 8 cuts a minute).
    It is the most judgement-heavy change.
  - Cinematic: the opening may be a fast run of shots (a label only).
  - Principles were rewritten for the Gaming video, Story, Vlog, Cinematic, Montage, Short and Commentary
    styles from what the videos said outright: a transition is about 12 frames and the cut sits under
    the moment it covers most; effect levels by role; a scream is cut just after it starts; cut on every
    second or fourth beat, not every beat; the shape of an eased move is a fast start and a long soft
    landing; change the pace on purpose.
- **What did not move, and why.** The gaming tutors disagree on cut rate and effects per minute (Finzar's
  2019 videos run at twice the playbook rate, his 2026 one at 9 to 11 cuts a minute, a gaming guide at
  about 5), and nobody states an effects rate, so those stay as they were. Commentary's pace stays calm:
  finished YouTube talking heads cut faster, but one calm essay and the podcast-clip video match it.
  **Stream highlights did not get its videos**: five stream tutorials were watched, but four were about
  vertical clips or software and none showed how a long highlights video should look, so the genre's
  note says its rules are still from written guides. No editor of a large streamer was found in four
  searches.
- **Still open**: a long-highlights editor to watch; what to hold back before a drop; "leave mid-thought"
  (no video said it); and the audio itself, which a free Gemini key would let the skill hear (add it
  through the form the skill opens, not in a chat).
- **A tool quirk worth knowing**: for six videos `/watch` picked an auto-translated caption track by
  default; passing `--sub-lang en` should avoid that.

### Checked
- Core tests for the genres (seven genres, each with its own long-form style and at least two sources;
  the suggested genre per kind of recording; Stream highlights and Vlog cutting the way they describe;
  a project remembering its genre, and older projects and unknown genres reading as "not chosen") pass
  with the rest of the suite. New: each genre's note says what was watched and no more (Stream highlights
  says it was not learned from the videos), every watched source is a video link listed once, and the
  moved numbers are pinned so they change only on purpose.
- The vlog test that expected rhythm zooms at 10 cuts a minute now expects none at 6.
