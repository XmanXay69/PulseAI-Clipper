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
  articles they were read from, and a plain sentence saying how they were arrived at.

### What "studied" means here, honestly
- The request was to watch the most popular editing tutorials on YouTube, Finzar's above all. That did
  not happen, and this section says why so nothing here is taken for more than it is.
- The `/watch` skill ([bradautomates/claude-video](https://github.com/bradautomates/claude-video), MIT)
  is installed in the repository at `.claude/skills/watch`. It downloads a video with yt-dlp, pulls
  frames and captions, and hands them over to be looked at. Its checks pass.
- YouTube refuses video pages to the cloud machine this work runs on ("sign in to confirm you're not a
  bot"). Searching worked, so the list of videos exists: Finzar's "How to Edit a Gaming Video", "How
  I'd Edit a Viral Gaming Video in 2026", "How To Edit YouTube Videos in 2026 (Ultimate Guide)" and "I
  made 100+ gaming videos. This is what I learned", plus the most-viewed tutorials for stream
  highlights, gaming, vlogs, cinematic editing and shorts. None of them could be opened from here, and
  no way round YouTube's check was used.
- So the genres were written from **published articles and editors' written breakdowns**: Finzar's
  newsletter (which turned out to be mostly announcements; his teaching is in the videos), a breakdown
  of how Neebs Gaming cuts for comedy, a streamer's guide to turning Twitch streams into YouTube videos,
  two write-ups of an editor's breakdown of Casey Neistat's vlogs, StudioBinder on rhythm and shot
  length, PremiumBeat on the basic cuts, and montage guides. Each genre lists its own.
- The numbers (how often a cut, how fast a zoom arrives, how long a shot may be held) are judgement
  written down from that reading. They have not been measured on real videos and have only run on the
  generated sample.
- **Two ways to get the real thing**, either of which lets the styles be redone from the videos
  themselves: run `/watch` on your own Mac, where YouTube lets you in; or give the skill a free Gemini
  key, and Google's model watches the YouTube link directly without a download.

### Checked
- Core tests for the genres (seven genres, each with its own long-form style and at least two sources;
  the suggested genre per kind of recording; Stream highlights and Vlog cutting the way they describe;
  a project remembering its genre, and older projects and unknown genres reading as "not chosen") pass
  on Linux, with the rest of the suite.
