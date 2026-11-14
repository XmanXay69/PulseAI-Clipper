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
