# Editing study: what 45 editing videos say

Written 14 November 2026 from a session on the Mac, as the job in [EDITING-STUDY.md](EDITING-STUDY.md) asked. Every claim below carries the short name of its video and the time it was said or shown (the short names are listed in the source index at the end). Tags: **said** (the tutor says it, read from captions), **seen** (visible in a frame), **measured** (a tool measured it), **heard** (caption text only; nobody could listen to the audio). Where a number is a guess by eye the line says "estimated".

## How it was done

- The `/watch` skill on its local engine (frames and captions on this Mac, no key): yt-dlp downloads the video, ffmpeg picks scene-aware frames (50–60 per video, plus full-size frames wherever a timeline or a value had to be read), and captions are the transcript. 45 videos were watched in nine groups, one helper per group, each writing an evidence note per video; the pilot video was done in the main session. The per-video notes were kept outside the repository; this page is their synthesis.
- For every video two 3-minute stretches had their hard cuts counted with ffmpeg's scene filter at 0.35, as the study asked, and what each stretch contained was written down. **Cut rates in this page are floors, not pacing figures:** the filter misses jump cuts made on one camera (re-measured on two talking heads, Viral2026 and Olufemii, 0.35 gave 4.3 and 4.7 cuts/min where 0.15–0.2 gave 12–15), and it counts transition flashes and borrowed film clips as cuts. A screen recording of a timeline barely changes between cuts, so its number says nothing about the editor's pacing.
- Nobody listened to the audio. Anything "heard" is a caption. Music and effect levels come from numbers the tutor says or fader values on screen, never from listening, and loudness figures that were measured (ffmpeg) are called out.
- For six videos the skill's default caption track was an auto-translation (Arabic or Bengali) rather than the English original. For four of them (Storezar-SFX, Music, Stirling, MidnightMan) the helper fetched the English track with yt-dlp and used that. For the other two (Joshyy, MagnnuM) the helper reported only a translated track, so it read the translation and checked numbers against the screen where it could; figures that rest only on a translation are marked. Passing `--sub-lang en` to the skill would likely avoid this.
- Caption timestamps drift: a claim can sit up to about 15 s from the time given. Of the claims, five of the Finzar helper's were re-checked against the captions and one dB reading (ThinkMedia −33 dB) against its frames; they matched. The rest were not independently re-verified. Where a helper's closing summary disagreed with its own per-video note (it swapped which stream videos carried a sponsor read), the note was taken as primary and the transcript checked.
- Sponsor reads and promotions (music libraries, preset packs, courses, tools) were noted and are not used as evidence. No video was dropped as a pure advert, but Cpaws (a tour of Twitch's built-in highlighter) and Huang (a method for learning any style, with a sponsor read) turned out to say almost nothing about editing craft, and MidnightMan and Hermans read as product demos.

## What the watching did and did not settle

- **Numbers are rare.** Tutors teach by kind of cut and by taste. Most claims below are qualitative; the numbers that exist are mostly frame counts (transitions, pop-ins, zoom keyframes), fader levels in dB, and what a tutor's own timeline shows.
- **Settled enough to move a number:** zoom and pop-in ramps are about 0.1 s for a snap (several tutors); transitions about 12 frames (four Finzar videos); the spoken promise comes around 20 s in the story and vlog videos; sections turn over about every two minutes; a vlog or story edit runs about 4–7 hard cuts a minute, not 10.
- **Not settled:** the hook deadline for gaming videos, effects per minute, the music bed for gaming videos, the pace of commentary, and everything about long stream-highlight videos (see Stream highlights: nothing watched covers them).

Start with **What moved in PULSE, and what was left alone** (after the genre sections) for the outcome; the genre sections hold the evidence.

## Gaming video (playbook `retention`; genre Gaming video)

### Finzar (14 videos)

**Watched:** Gaming101 (the 1.5M-view beginner video), Beginner, StopEditing, Funny, Viral2026, 8Hours, 100Videos, Transitions, YT2026, Secret (the closest match on his channel to the newsletter's "The Real Secret to PRO Level Editing"; the helper could not confirm the exact title), SFX, Storezar-SFX (his shop's channel), Memes, Music. StopEditing and 8Hours are mostly about workflow and promote his time-tracker sponsor and his course; Gaming101, Memes, Music, Transitions and 100Videos each carry a sponsor or preset-pack segment of 10–25% of their length, which is not editing evidence and is ignored here. `Music` has almost nothing about music mixing despite its title.

**Pacing and density (his own videos, scene threshold 0.35 [measured])**
- 2019–20 comedy tutorials cut fast: Funny 22–33 cuts/min with 1.8–2.6 s shots; StopEditing 19–23 (2.5–3.1 s); Gaming101 10.7–24.3 across five stretches; Beginner 13.7–14.0 (4.2 s); 8Hours 19–24 (2.5–3.2 s). A meme or stock cutaway lands every 2–4 s in the opening of Beginner [00:00–01:00, seen, estimated] and he says to put one on every "unmemed" moment in Funny [04:28–04:39, said].
- His 2026 story-style gaming video is calmer: the talking head reads about 9–11 cuts/min, with pieces of 1–7 s, from its timeline [Viral2026 03:53, seen, estimated]; he says viewers no longer like relentless cut rates, to leave room to talk, and not to cut every bit of dead space so personality shows [Viral2026 07:52–08:08, said; the caption reads "cup per minute", the unit is taken to be cuts]. He also says not to overdo memes and uses none in that video [Viral2026 06:18, said].
- The cut-rate tool undercounts same-camera jump cuts: Viral2026's talking head reads 4.3/min at 0.35 and 15/min at 0.2, so his timeline pieces were used instead.

**Rules**
- Intro: say what you will do, how and why, in the first part; no inside jokes a stranger cannot follow; no logo-on-blur "intro"; never ask for likes or subscribes in the intro; lots of sound effects in the intro, lighter later [100Videos 01:24–04:30, said; YT2026 05:16–05:59, said].
- Cut dead space back to the last audible sound; watch a bit three times and remove what is not funny [Gaming101 03:03 and 03:23, said]. Cut a scream just after it starts so the cut is the joke [Funny 02:05–02:20, said]. Find the moments by audio spikes [Funny 01:24, said]. Keep wide shots and do not over-zoom [Funny 03:47, said].
- Zooms and tracking go on text, people and things that matter to the story [Gaming101 04:04, said]. The gap between zoom keyframes is "a couple of frames" with motion blur on [Beginner 03:54 and 04:14, said], about 0.03–0.07 s at 60 fps. Text pops in as three scale keyframes on frames 1, 4 and 7 at 75–80%, 120%, 115% [Gaming101 09:14, said], 0.10 s to settle at 60 fps, which another editor credits to him as 70% to 110% over 7 frames and 100% over 5 more, 0.117 s [Isaac 13:28–13:49, said]. A 122% scale is visible on a punch-in keyframe [Memes 07:01, seen; the layer could not be confirmed]. A speed ramp eases in about 8 frames, 0.13 s [Music 05:25, seen, estimated].
- Transitions are built on adjustment layers about 12 frames long, 0.2 s at 60 fps [Gaming101 09:55; Beginner 08:02; 8Hours 04:46; Transitions 01:56, said; 02:05, seen]. Measured on the 2026 video: a whip about 0.1 s and a light-leak or glitch about 0.3 s [Viral2026 06:47 and 05:30, measured]. Put the cut under the moment the transition covers most of the screen (a white flash filling the frame, a plume of smoke) [Transitions 06:14–06:39 and 07:16–07:28, said]. Premiere's built-in transitions are mostly weak; a motion-blur whip alone, he says, still looks like a slideshow [Gaming101 09:34; Transitions 02:58, said].
- Sound by role: a fast motion whoosh about −16 dB, a transition whoosh about −12 dB (4 dB hotter), a deep whoosh about −16 dB because there is voice over it (levels on the clip fader, relative to his own pack) [Storezar-SFX 00:44, 01:03, 01:29, said]; meme audio brought down about 6 dB from where an imported clip hits the red [Memes 02:09, said]; music under gameplay about −16 dB [Gaming101 07:51, said]; effects in 6 dB gain steps, never in the red [YT2026 10:33; Gaming101 11:19, said]. Put the spike of a whoosh on the fastest point of the motion; use a different effect for each repeated text pop [Storezar-SFX 00:28 and 02:16, said].
- Layering is normal: a reversed boom or a long riser ending on the payoff, with a short sting on top; one moment, three layers [SFX 04:08–05:50, said and seen]. The only cap stated is "three or four" loud blasts in a run before the viewer tires [SFX 05:29, said]. A harsh start gets a short fade-in [SFX 05:49, said]. Transitions are the first priority for effects, and the same sound goes under every transition of one kind [Gaming101 11:19–11:40, said]. Around an animated graphic he shows about four sound clips in about 3.5 s under a graphic about 1.8 s long [YT2026 10:28, seen, estimated]; no tutor gives a per-minute figure.
- Memes: a quick meme is about 1.1 s and a flash meme about 0.9 s, each on a punchy ending, covering one shot [Memes 01:48, said; 03:15 and 06:52, seen]. The flash is an 8-frame white matte (opacity 0, 100, 0, Overlay), an 8-frame shake with a keyframe every 3–4 frames, and a Gaussian blur of about 5 on the gameplay behind [Memes 07:19–08:22, said]; a speed-ramp peak gets a flash of about 5 frames, 6 measured [Music 05:43, said; 06:09, seen]. A DIY meme with your own text is used about once per video, "if that" [Memes 03:53, said].
- Music: pick a track with a steady beat [100Videos 06:15–06:35, said]; cut on the loud notes (snare or kick), and any beat is better than none but chosen on purpose [Music 03:25; YT2026 17:26–18:15, said]; "probably the most important" part, one similar track throughout [Viral2026 06:50 and 07:12, said].
- Subtitles: a bold geometric sans, white with a black stroke of 12–14 and a black shadow, text at about 0.79–0.91 of frame height, one or two words, a different colour per speaker [Gaming101 08:33–08:54; Beginner 06:00 seen; Viral2026 06:12 seen; 8Hours 07:33 and 09:06, seen].

**Smoothness (feeds the `smooth` style)**
- His thesis is that smoothness, not effects or cut count, is what makes an edit look professional [Secret 00:00–00:36, said]. Keyframes are interpolated at a steady speed by default; set the first keyframes to Ease Out and the second to Ease In, "out then in", on rotation, scale, position and blur alike [Secret 02:25–03:52, said]. The preferred velocity curve is not a symmetric slow start: pull the first handle out a little and the second all the way back, so most of the speed comes early and a long soft tail lands the move [Secret 04:42–05:09, said; 04:58, seen]. Entrances get that fast-start, soft-landing shape and exits mirror them; position and rotation curves should look alike [YT2026 07:42–08:44, said; 07:56, seen]. Motion blur on, shutter angle 180 or 360 [Secret 05:09–05:23; StopEditing 07:49; Transitions 08:28, said and seen]. Leave space after something big is said; overlap dialogue with J-cuts in an intense scene [YT2026 12:14–13:14, said]. A letterbox is a Crop of about 15 with eased keyframes [YT2026 13:35–14:16, said]; his own ending measures bars of about 18.75% each (2.84:1) [YT2026 20:30, measured].

**Hook timing in his own videos [heard]:** the promise comes at 0:01 (SFX), 0:06 (Storezar-SFX), about 0:10–0:15 (Funny, Beginner), 0:20–0:40 (Viral2026), 0:30 (Music), 1:07 (Memes), 1:27 (YT2026), and after a skit of about 75 s (Gaming101). A very popular gaming tutor does not meet an 8 s promise in most of his own videos, though most open on motion or a joke from frame one.

**Against today's playbook (`retention` unless noted)**
- 12 cuts/min, 5 s shots: sits between his 2019–20 rate (13–33) and his 2026 rate (about 9–11); unchanged.
- `zoomRamp` 0.16 s: his snappy numbers are shorter (a couple of frames, 0.10 s text pop, 0.13 s ramp); moved to 0.12 s. `zoomScale` 1.22 is matched by the one scale value seen (122%).
- `pauseRatio` 0.04: he says not to cut every bit of dead space in his 2026 style.
- `popupsPerMinute` 1.0 and `effectsPerMinute` 4 / cap 8: no per-minute number is given by any of the 14; the comedy videos are far denser, the 2026 video far sparser. Left unchanged; the effect-burst pattern is recorded in the principles instead.
- `hookDeadline` 8 s: see the hook timing above.
- "Cut the breath, keep the reaction": refined by cutting a scream just after it starts.
- "Open on the moment, no greeting, no logo": confirmed for the logo; adds what-how-why and no like/subscribe ask.
- `smooth` "starts slow, travels and settles": partly contradicted; his curve leaves quickly and lands softly. `smooth.zoomRamp` 0.6 s is for punch-ins, which he does not time; his own transitions are 0.2 s and his demo slide about 2 s.

### Leo, MidnightMan, MortarMarv, ItsProger (4 videos)

**Watched:** all four. Leo (about 6M views) is a general retention explainer, not about games; MidnightMan is a CapCut feature tour for a Fortnite guide that reads like a product pitch; MortarMarv and ItsProger are Premiere beginner guides. All four are partly promotional (about 10–17% in the three that say how much), and none gives a sound-effects-per-minute figure, a hook deadline, or a re-hook interval in seconds.

**What they say**
- Editing density is an audience choice: a 26-minute car-vlog video with 17 cuts (about one cut every 90 s) holds "hang out" viewers, while the rapid-fire style cuts about every 2 s; do not shorten shots for their own sake, the same clip can stay up for 10 s if it is interesting for 10 s [Leo 00:41–01:44 and 05:31–05:52, said; 01:34–01:40, seen]. Change what is on screen between A-roll, B-roll and other footage "every few seconds" [Leo 03:04, said]. Stripping every pause is the biggest entertainment lever but costs authenticity, so it is a dial, not a default [Leo 01:44, said].
- B-roll: use three to four times as much as A-roll [ItsProger 00:41, said]; use it as much as possible, with motion graphics for dull but necessary explanation [Leo 03:25–04:26, said].
- Captions: only where the viewer should focus on particular words, three words or fewer at a time [Leo 06:53–07:13, said]; on the intro and important moments, not every line [ItsProger 03:05, said]. Their own captions are one to four words, uppercase and centred in ItsProger, sentence case with orange keywords at about 0.80–0.85 of frame height in MortarMarv [seen].
- Zooms: two keyframes five frames apart plus a whoosh (0.17 s at 30 fps, 0.08 s at 60 fps; the timeline rate is not shown) [MortarMarv 06:11, said]; "a few frames" for a zoom and a couple more to settle [ItsProger 02:45 and 09:34, said]; the one punch-in depth readable on screen is Scale 135 to 300 on a small detail [MortarMarv 06:21, seen]; a pop-up text overshoots by only 3% (82, 103, 100) [ItsProger 03:04–03:10, seen]. A facecam enlargement from 122% to 144% over about 36 frames (1.2 s at 30 fps) is a glide, and the 122% there is a facecam size, not a punch-in [MidnightMan 07:25–07:46, seen]. Slow zooms for stills, faster for emphasis [ItsProger 09:34–09:55, said].
- Nothing should just pop onto the screen: it moves in, or a shutter or pop sound explains it [Leo 08:58–09:19, said]. The eye should land in the next shot where the last shot's eye was; break continuity on purpose now and then for the jolt [Leo 09:19–09:59, said]. A whoosh for motion, a highlight sound for a highlight; risers only before something that matters, hits to release, drones for mystery; stop the music abruptly to spotlight a moment, fade it slowly to close a segment [Leo 10:41–11:42 and 13:06–13:27, said].
- Transitions: do not overdo them, a plain cut can be all you need; good places are topic, music and chapter changes [MortarMarv 06:52; ItsProger 03:26–03:47; MidnightMan 10:07, said]. A short audio fade-in (a couple of frames) on almost every effect and music cut [MortarMarv 06:52–07:33, said].
- Music: MidnightMan plays one track under the intro only, at −23 dB, and drops it for the gameplay so it "stands on its own" [11:07–11:47, said], and has three sound effects in a seven-minute project (a whoosh on the speed ramp, a glitch sound on the transition, a subscribe bell) [12:07–12:47, said]. The intro teaser clips sit between the 4 s and 8 s mark [MidnightMan 08:06, said; 13:52, seen].

**What the edits show**
- Hard-cut rates of the tutorials [measured, 0.35]: Leo 4.0–6.0 cuts/min (18 and 12 per minute at 0.15, because the talking head is jump-cut on one framing and graphics are layered); MidnightMan 10.3 in the tutorial and about 4.7 picture boundaries per minute (mean about 12.8 s) in his project timeline [12:45, seen, estimated]; MortarMarv 10.0–11.3; ItsProger 9.3 and 4.0, with a chapter card every 92, 133, 240 and 92 s (mean about 139 s) [01:47, 04:00, 08:00, 09:32, seen]. The screen-recording stretches say nothing about pacing.

**Against today's playbook (`retention`)**
- 12 cuts/min, 5 s: a real gaming timeline here (MidnightMan) is slower, about 4.7 boundaries/min; the tutors' own talking videos run 4–11. Leo says there is no single right figure. Unchanged, since the Finzar videos sit above and these below.
- `zoomRamp` 0.16 s: five frames and "a few frames" are 0.08–0.17 s depending on the frame rate; with Finzar's numbers this supports a snappier 0.12 s (moved).
- `zoomScale` 1.22: not confirmed; the only readable depth is a 2.2× zoom on a small detail, and 122% appears only as a facecam size. Left unchanged.
- `musicBed` 0.75: MidnightMan uses none under gameplay, Leo and Finzar use a continuous bed; unchanged.
- `maxCaptionWords` 4: Leo's limit is three, Finzar's captions are one or two words (moved to 3).
- `rehookInterval` 120 s: ItsProger's chapter cards average about 139 s and Finzar's step cards run every 60–100 s; unchanged.

## Stream highlights (playbook `streamHighlights`; genre Stream highlights)

**Watched:** Senpai, GaelLEVEL, StreamScheme, Stirling, Cpaws (all five, in full). Four searches for an editor of a large streamer explaining their process found nothing usable (queries: "I'm the video editor for a streamer how I edit", "editor for a million subscriber streamer my workflow", "I edit YouTube videos for a big Twitch streamer behind the scenes", "how I edit for a top streamer editor day in the life"; results were generic editing channels, a Kai Cenat behind-the-scenes, Finzar, and a clip with 61 views).

**The main finding is a gap.** None of the five teaches how a long highlights video should look. Three of them are about vertical clips: Senpai's title says "YouTube videos" but it teaches Shorts and TikTok cutting; GaelLEVEL and StreamScheme are vertical-clip tutorials. Cpaws is the only one about long highlights and it is a button-by-button tour of Twitch's built-in Highlighter with a paid OWN3D segment, saying nothing about pacing, zooms, captions or music. Stirling is about triaging hours of footage. So the `streamHighlights` numbers (6 cuts/min, 10 s shots, 1.5 zooms/min, 0.1 music bed, 0.7 effects/min and the rest) are **neither confirmed nor refuted** by what was watched, and they were left unchanged.

**What the videos do say about what gets cut**
- One creator's long-highlight example keeps 29:32 of a 2:25:22 stream (about 20%), dropping the "just chatting" start, a break and a different game; each highlight is one game, titled and categorised by it [Cpaws 03:04, 03:47, 05:08, said; 09:06, seen].
- Review speed depends on the game: slower for a first-person shooter so nothing is missed, faster for a MOBA where team fights are obvious [Stirling 01:43, said]. People find the moments by scrubbing with audio on (the preferred method) [Stirling 03:05–03:26, said], consistent with the loudness and laughter signals PULSE's clip finder uses.
- Watch the whole clip before cutting; it shows the pace and what to trim; cut dead air at the head [Senpai 03:28 and 04:09, said].
- Plan the stream around what will cut well; treat a stream as a recording session [StreamScheme 02:55–04:39; Senpai 09:01, said].

**Evidence for the vertical clips (feeds the `short` playbook, see Shorts)**
- Length: five clips trimmed to 5–8 s each got 300 views or less; 17 s and 33 s clips with a spoken hook did best (a 33 s clip reached 28,600 views in a day), one creator on one game, so cut a clip no shorter than about 15 s just to be short and keep the walk-through after the hook [StreamScheme 06:56–09:09, said].
- Layout: three layers (blurred fill, gameplay at about 140%, circle-masked facecam), cam in the top third, 15 px drop shadow [GaelLEVEL 11:36–12:16, said; StreamScheme 14:10 and 14:22–14:45, seen and said]. It matches PULSE's existing layouts.
- Captions: always burned in, a couple of words at once (the auto-caption setting gave one word per caption held 4–8 frames at about 30 fps), moved to the middle of the frame [GaelLEVEL 13:19–14:44, said; 14:22–14:34, seen]. Mixed-case running subtitle at about 0.76 of frame height with uppercase hook cards mid-frame [StreamScheme 19:29–19:34, seen]; uppercase with a red outline, revealed a word at a time [Senpai 05:52 said, 08:09 seen].
- Extras: keep sounds and extras "as simple as possible" [StreamScheme 18:26, said].

**The tutors' own pacing [measured, scene threshold 0.35]:** Senpai 2.3 cuts/min (22.5 s shots, talking head with whip-blur inserts); GaelLEVEL 3.7–6.0 (15 at threshold 0.2, jump cuts in one shot); StreamScheme 4.5–5.3 (18.7 at 0.2); Stirling 5.0–7.5 (7–11 s shots, a talking head alternating with short screen recordings); Cpaws 2.2–3.0 then no cuts at all (screen recording). A talking-head explainer, not a highlights video.

## Vlog and story (playbooks `vlog` and `story`; genres Vlog and Challenge or story)

**Watched:** Neistat, Dovey, Runia7, Runia5, Huang (all five, in full). Huang turned out not to be about story or vlogs (a method for learning any editing style, with a 71 s sponsor read), so it is used only for the "learn the genre's baseline" idea and for his own graphic-heavy pacing.

**What the editors say**
- Story shape: setup, conflict, resolution, and he looks for that shape in every day he films [Neistat 04:57–05:59, said]. Dovey gives five beats (setup, challenge, complications, payoff, change) and says on YouTube they must arrive faster than in film: setup, context and challenge inside the first 30 s, which he says the big challenge channels do [Dovey 04:23–08:29 and 09:11, said].
- Time is an easy challenge to build on (24 or 48 hour challenges, his own three-day trip as a through-line) [Dovey 05:03–06:26, said]; a time challenge can be shown with an on-screen countdown (the example counts from 68 hours left to 39) [Dovey 06:13, seen].
- Shot mix: equal parts handheld, locked-off and establishing wides; non-stop handheld is tiring [Neistat 06:00–06:41, said]. Wide, then medium, then close gives a scene structure, with two reversals (straight to close for impact, or open close and reveal the wide late) [Runia7 04:55–05:57, said].
- Time-lapse and drone shots only earn their place as a transition between scenes or to give context; pretty footage with no tie to the story gets boring fast [Neistat 08:05–09:26, said].
- Pace: the common mistake is holding one pace; vary shot length, camera motion and sound, and time the changes. Fast phases use shots of about 0.3–1.7 s and calm phases about 2–3.5 s in his own 30 s hook, which runs silence and a rising effect, a pause, fast cuts with music, a short break, a second build, then a release with no music [Runia5 02:43–04:51, said; scene cuts at 5.7–12.4 s, measured]. A burst of about nine shots in three seconds sits against a 13 s hold to show the contrast [Runia7 07:22–08:05, said; about 0.35 s per shot, measured].
- Smash cut works best when the sound drops out with it, and should be rare [Runia7 01:45–02:50, said]. Jump cuts landed on the beat show progress or speed something up [Runia7 03:11–03:54, said]. Cut during an action so the movement carries across [Runia7 03:54–04:55, said]. Instead of cutting on every beat, land an action on the beat and let a sound effect span two shots [Runia5 07:38–09:16, said].
- Audio first: lay voiceover, music and effects before cutting shots; the track then shows where the build-up is too long (his example: seven seconds of set-up was too slow) [Runia5 01:21–02:43, said]. Assembly edit before polish: he once spent two days on the first 30 s [Runia5 06:15–07:38, said].
- A surprise should be rare and part of the story: a freeze frame with text in the first three seconds, a cut to silence [Runia5 10:16–10:58, said].

**What the edits show**
- Hard-cut rate (scene threshold 0.35) of the tutors' own videos [measured]: Neistat 2–4 cuts/min, 4–6 once jump cuts are counted (threshold 0.12 on 05:00–08:00 gave 5.7/min, mean shot 10 s; the handheld vlog tail 11:00–14:00 gave 4.0/min); Dovey 4–7/min blended, 2–3/min for the plain talking head (a new framing every 20–30 s), 11–12/min in the b-roll story passage 00:00–04:00; Runia7 9–17/min and Runia5 6–14/min, both talking head plus example clips, with Runia5's 30 s hook at 42/min (mean shot 1.4 s); Huang 9–17/min with graphics.
- Opening: Neistat opens on atmosphere, states his want (summer, against the rain) at 0:23 and the video's promise at 2:07 [Neistat, heard]; Dovey claims at 0:00 and promises at about 0:20 [Dovey 00:20, heard]; Runia7 and Runia5 promise at about 0:20 and 0:20–0:41 [heard], but all three put something moving on screen from the first frame and a text or sound hook inside the first three seconds [Runia5 00:00–00:05, seen].
- Section length: Neistat's tutorial parts run about 40–90 s [Neistat, heard]; Dovey's beats 20–80 s [Dovey 04:23–07:48, heard]; Runia5's topics start every 83–158 s, about 120 s on average without the sponsor read [Runia5, heard].
- Dovey's talking head is cut between a wide and a tight crop about 1.4 times closer as a hard cut with no ramp (one frame pair, 00:10 against 00:35, estimated by eye) [Dovey, seen]. Neistat and Runia use no punch-ins [seen].
- No speech captions anywhere in the five; Runia7 uses chapter cards (about four) and Dovey a few callouts on borrowed clips [seen].
- Music: Neistat has no music tags in his talking stretch 2:07–8:46 and music under the story and b-roll parts [Neistat, caption tags only]. Audio-floor measurements for Dovey and Runia (about −24 to −33 dB, dropping to −45 dB or lower at section changes, for example Runia7 02:20 and Runia5 03:50, 06:00, 07:40) are consistent with a bed that drops at turns, but cannot tell music from room tone [measured, weak].

**Against today's playbook**
- `vlog` 10 cuts/min, 6 s shots: not supported. The one real vlog (Neistat) is 4–6 cuts/min with 10–13 s hard-cut shots, and Dovey's blended talking-head-plus-inserts story is 4–7. `story` 7 cuts/min, 8.5 s is consistent with Dovey.
- `rehookInterval` 150 s (`story`, `vlog`): three tutors change section every 20–158 s, about 120 s on average; 150 is at the long end.
- `hookDeadline` 15 s (`story`) and 12 s (`vlog`): the spoken promise comes at about 20 s in three of the four story/vlog tutors and at 2:07 in Neistat's, while something is moving from frame one in every one. Supports a promise by about 20 s with a taste in the first seconds.
- `zoomScale` 1.12 and `zoomRamp` 0.3 s: one frame pair (Dovey) shows a 1.4× snap; not enough to move the numbers. Two tutors use no zooms at all.
- "Leave mid-thought" (`vlog` principle): nobody states it. The nearest watched idea is cutting during an action so it finishes in the next shot [Runia7 03:54–04:55], which is about movement, not speech. It was taken from an article and is neither confirmed nor refuted by what was watched.
- Not in the playbooks and stated more than once: vary the pace on purpose (fast bursts against held shots, with sound dropping at the turn); a time-lapse or drone shot must serve a transition or context; build the edit from the audio (voiceover, music, effects) first.

## Cinematic (playbook `smooth`; genre Cinematic)

**Watched:** StudioBinder, lacapture, Duncan, Andrew, Hermans (all five). Hermans is the only one that shows a real timeline; the other four teach by kind of cut and give almost no numbers. No tutor states a shot length or an ease time in seconds, so the playbook's 10 s average shot and 0.6 s zoom ramp are neither confirmed nor refuted by any of them.

**What the editors say**
- Pace serves feeling: a contemplative scene holds shots longer, a frantic one cuts fast [StudioBinder 01:45, said]. Fades and dissolves mark time passing and the start or end of a piece; white only for a death or a dream; a smash cut is the deliberate exception and rare [Duncan 03:16–03:37 and 04:58, said].
- Audio leads or trails the picture (J and L cuts) so a conversation never stops dead on a hard cut and a speaker's words can play over what they describe [StudioBinder 10:36–12:47; Duncan 02:53, said]. No size for the lead is given; Duncan's graphic suggests a visible margin but has no ruler [Duncan 02:05, seen].
- Cut on action, with the out-point of one shot matching the in-point of the next [StudioBinder 15:49–16:10; Duncan 03:57, said]. Keep the subject at the same place in frame across a cut so the eye does not hunt; the quoted figure, 1.8 s per shot, is for fast action and is not a cinematic pace [StudioBinder 09:16, said].
- Pick the music first and cut scenes at dips in the track rather than chopping the track [Andrew 01:48–02:30, said]. Sound effects are layered by role (riser, step, ambience, air) [Andrew 01:20, seen].
- A fast opening sequence of shots about 0.5–1.5 s long, each cut landing during a hand action, doubles as the hook; the video then settles to about 10 s shots [Andrew 00:00–00:40, measured and seen].
- Cut on the beat, but not every beat: every second or fourth beat, because every beat feels robotic [Hermans 04:07–04:57, said]. In his finished 30 s sequence the music's beat markers are about 0.6 s apart (about 100 BPM) and cuts recur at about 1.2 s and 2.4 s (2 and 4 beats), about 13 clips at 2.3 s average, 26 cuts/min [Hermans 04:48 and 05:06, seen; 10–38 s, measured].
- Speed ramp built on a custom curve to fit the music: normal speed, S-shaped rise to the top of the curve (10× on the axis), a hold, an eased fall back to normal; the 13 s clip ran 8 s afterwards, with a whoosh on the ramp and an ocean ambience under the whole sequence [Hermans 02:09–03:43 said; 03:46 and 05:45 seen]. Ease times are not given in seconds.

**What the edits show**
- Cut rates of the tutorials themselves [measured, scene threshold 0.35]: StudioBinder 12.7 and 19.3 cuts/min (mostly borrowed film clips); lacapture 9.7 in the skit opening (shots of about 2 s) and 6.7 cuts/min, 8.6 s shots, in the lesson body; Duncan 7.8 and 9.3; Andrew 5.6 (10.0 s) over the first three minutes, whose fast opening and slow body average out; Hermans 7.0 (talking head plus the 30 s sequence) and 2.3 (screen recording, says nothing about pacing).
- Openings are busy: picture in motion from the first frame in all five; the promise comes at about 0:15–0:22 (Andrew 0:15–0:20, lacapture 0:22, Duncan 0:21 for his first cut, Hermans about 0:40 after the sequence) [heard].
- Mix loudness varies from −23.6 to −14.4 LUFS across the five, so none is a model for a music-bed level [measured].
- Not heard: nobody could listen to the music, so music-bed levels are unverified.

**Against today's playbook**
- `smooth` 6 cuts/min, 10 s shots: consistent for talking-and-b-roll bodies (lacapture lesson 6.7/min and 8.6 s; Andrew body about 10 s) but about four times too slow for a music-led montage (Hermans 26 cuts/min, 2.3 s). The numbers describe a style of body section, not a beat-led sequence.
- `opensFast: false`: contradicted by Andrew (a 40 s fast shot sequence as the hook) and by the busy openings of all five; fast openings are normal even for slow-paced cinematic content.
- `zoomRamp` 0.6 s, `zoomScale` 1.1: neither tutor states a figure; unchanged.
- "Let the music carry it" and "whooshes on motion, risers into reveals": supported, in kind, by Andrew, Hermans and Duncan; with a concrete rule added (cut on every second or fourth beat, not every beat).
- Not in the playbook: speed ramps (eased shoulders, matched to the music); J and L cuts (audio leads or trails the picture); cut on action; fades for time passing only.

## Commentary, podcast and video essay (playbook `commentary`; genre Commentary or podcast)

**Watched:** vidIQ, ThinkMedia, Sbiti, ContentCreators, plus two found by search: indietrix (a working video-essay editor walking through a Premiere timeline) and Olufemii (talking head only, sponsored). Four searches for "video essay editing" turned up these two and nothing better. Sbiti and ContentCreators sell their own courses; ThinkMedia and Olufemii carry a sponsor read; vidIQ is a comedy sketch with no timeline. Only indietrix is a calm, voice-led essay.

**What the editors say**
- Music under a voice-led video: about −33 dB on the clip fader (a stated range of −32 to −36), which gives "a subtle ambiance" [ThinkMedia 11:39–12:02, said; fader reads −26.1 dB mid-drag and −33.2 dB set, 12:02–12:07, seen and re-checked]; about −20 dB, with a new song for each chapter [ContentCreators 33:46–34:28, said; 34:10, seen]; −11 dB for short podcast clips with the meter held between −12 and 0 [Sbiti 13:06–13:46, said; 13:46, seen]. All are clip-fader values, not measured loudness differences.
- Sound effects on every visual cue (a whoosh with each zoom, a soft beep with each text pop) [Olufemii 03:48, said]; "at every opportunity", with a glitch effect around −11.8 dB, whooshes pulled down and cut to the length of the text pop, a short fade-in so they are not harsh [ContentCreators 30:59–33:05, said; 32:40, seen].
- Hide cuts with b-roll on the layer above the talking head, so the A-roll stays untouched [ThinkMedia 06:29 and 09:15; ContentCreators 14:59–15:21, said]. In ThinkMedia's demo the talking head runs in pieces of 2–10 s and b-roll pieces of 2–4 s lie end to end above it, about one cover every 3 s [ThinkMedia 08:05 and 13:50, seen]. B-roll shot at 60 fps can be slowed to 40% on a 24 fps timeline [ThinkMedia 08:13–08:54, said].
- Pauses are cut out, not shortened: the example removes a 12.42 s pause by deleting it in the transcript [ContentCreators 10:55–11:35, said; 11:12, seen]. The voice-over essay does the opposite on purpose: voice clips are spaced by ear, longer after a key point, and the overview shows gaps of about 7, 12 and 10 s in 4.6 minutes [indietrix 01:24–01:48, said; 05:11, seen].
- Cut a talking head between angles on a motion (a head turn) [Olufemii 02:06–02:26, said]. A slow keyframed zoom on a static shot makes a boring five seconds feel shorter [Olufemii 01:03–01:45, said, perception claim]; a quick zoom is a hook at the start of an idea [Olufemii 01:45–02:06, said].
- The first picture must work with the sound off, since YouTube autoplays a muted hover preview [vidIQ 01:23, said]. A cut-in (tighter framing of the same take) and a cut-back keep a talking head fresh, with push-ins added in post to a locked-off shot [vidIQ 03:09–04:32, said]. No counts.
- Podcast clips for social: scale 16:9 clips to 198% in a 9:16 frame leaving about half the height as black; one line of small captions, never two, under the chin and above the chest, the same place on every clip; best clip first; an end card with a logo and a quote of 5–6 s for platform-policy reasons [Sbiti 05:29–06:12, 10:21–12:25, 15:08–17:52, said; 08:43 and 11:33, seen].
- Essays: titles and graphics "sparingly" so each lands; always keep the sound of an actual scene shown and mute the rest of the film's audio; music not necessarily the whole way [indietrix 00:42, 05:06–06:42, said].

**What the edits show**
- Cut rates [measured, scene threshold 0.35]: vidIQ 14.0–14.3/min (sketch with effects); ThinkMedia 8.0 and 13.0; Sbiti's sample short has 4 clips of about 10, 31, 12 and 15 s in 1:24, about 3 cuts/min, with no zoom, no sound effect and no transition [Sbiti 08:43, 13:46, 17:32, seen]; ContentCreators 11.7 and 10.0; indietrix 4.7 and 5.3; Olufemii 4.7 and 3.0 at the standard threshold.
- The standard threshold under-counts same-camera jump cuts: re-measured on Olufemii, 4.7 cuts/min at 0.35 became 12.3 at 0.15 and 22.7 at 0.08; the true shot rate is about 10–12 a minute (about 5 s). Any talking-head cut rate at 0.35 is a floor [Olufemii, measured].
- Framing steps between a looser and a tighter crop of the same take: about 1.2–1.35× in Olufemii [00:00–02:21, seen, estimated by eye] and about 2× in indietrix (head about 95 px wide against about 190 px), each held for a whole thought [indietrix 00:00–00:35, seen, estimated].
- Captions: none on any of the long-form speech; text is large glowing one- or two-word pop-ups (Olufemii, at least three in 4:54) or short key-phrase boxes (ContentCreators) [seen].

**Against today's playbook**
- `commentary` 3 cuts/min, 20 s shots: matches the raw talking portions (ContentCreators A-roll pieces of 7–25 s at 15:05, seen) and the calm essay's long holds, but every finished YouTube talking-head edit watched runs 5–14 cuts/min, about 5–12 s per shot. The 20 s figure describes the A-roll between covers, not the finished pace.
- `zoomScale` 1.08 and 0.6 zooms/min: Olufemii and indietrix use reframes of 1.2–2× at nearly every shot change. A slow push (about 5 s) is endorsed; the 0.4 s ramp is not tested.
- `musicBed` 0.25 and "far under the talking or none": the levels stated (−20 to −33 dB) support "far under"; "or none" is contradicted for YouTube talking heads (Olufemii says to hear a lot of it, ContentCreators puts a new song under every chapter) but fits the calm essay (indietrix: not the whole way).
- `effectsPerMinute` 0.2 and cap 1.5: contradicted for retention-style YouTube commentary (an effect on every cue) [Olufemii 03:48; ContentCreators 32:44]; possibly right for a calm essay (indietrix keeps film sound only where there is no dialogue).
- Supported: hide the join (b-roll over the cut, the A-roll untouched), cut pauses outright, a slow push on a long answer, captions kept to a single small line for podcast clips.
- `short` principle "No intro, no outro": contradicted by Sbiti's 5–6 s end card, which he adds for platform-policy reasons rather than craft [Sbiti 15:29–15:50, said].

## Shorts (playbook `punchyShort`; a format, not one of the seven genres)

**Watched:** Smith (3M views), Isaac, Hals, plus the vertical-clip tutorials from the stream group (Senpai, GaelLEVEL, StreamScheme) and the podcast-clip video from the commentary group (Sbiti). Isaac turned out to be a long-form voice-over essay in Premiere rather than a Shorts tutorial, and Hals is faceless commentary shorts in CapCut; Smith is mostly channel strategy.

**What the editors say**
- The hook is the first five seconds; it names the topic and leaves open questions, with no pauses, quick music and captions already on screen; the answer must be held to the end, because revealing the secret about five seconds in leaves nothing to wait for [Smith 03:11–03:53, 04:55, 05:16, said].
- The opening of a commentary short: a whoosh at frame zero, a zoom-in on the first clip, a rising suspense sound, then a shutter-click with a glare transition as it cuts into the main video at about 3 s [Hals 07:33–07:53 and 11:02–11:23, said; 11:20, seen].
- Clip length: no clip longer than 5 s; he changes the clip every 2–5 s because viewers will not watch one thing for more than about 10 s [Hals 14:25–14:46, said]. Clip labels on his timeline read 1.2–2.8 s, about 33 cuts/min by eye, from a few timeline frames [Hals 18:43, seen, estimated].
- Text pop: scale 70% to 110% over 7 frames, then to 100% over 5 more frames, at 60 fps (0.117 s up, 0.083 s settle), the recipe credited to Finzar [Isaac 13:28–13:49, said; timecodes 13:56:43–13:56:55 consistent, seen]. His zoom on a picture is an eased Bezier move because the raw version "is not smooth" [Isaac 12:00–12:24, said]. Hals keyframes a slow push on stills instead of using a preset zoom [Hals 15:28–16:51, said].
- Captions: one word at a time, all caps, at about 0.70 of frame height in Hals's preview (Montserrat, bold, white, "Color bounce" template) [Hals 17:32–18:13 and 20:17, said; 10:37–12:04, seen]; short mixed-case chunks with a coloured word in other creators' shorts [Smith 01:01, seen]. Isaac captions only important lines in long form [12:44–13:05, said].
- Sound: whoosh, riser and impact; lower the volume so they are not annoying; build them with the other tracks muted; "literally half of the video" [Isaac 16:05–16:52, said]. Match each sound to its effect precisely or the edit looks cheap [Vaultcar 09:52–10:14, said].
- End the short immediately; a clip hanging for five seconds at the end hurts engagement [Hals 16:51–17:12, said]. The platform-policy end card in Sbiti is covered under Commentary.
- Podcast clips for social are calm: about 3 cuts/min, no zooms, no effects, one small line of captions (see Commentary).

**Against today's playbook**
- 18 cuts/min and 3.3 s shots: matches the vertical clip-and-voice-over style only loosely. Hals is faster (1.2–2.8 s, about 33/min by eye); a podcast clip is far slower (3/min). The number sits between two real sub-styles.
- Captions: mixed case is supported by some examples, but the two creators watched who teach captions in detail use all caps one word at a time (Hals, Senpai); position 0.68 is close to Hals's 0.70, whereas split layouts with a top cam put the caption nearer the middle (GaelLEVEL about 0.48).
- `zoomRamp` 0.12 s: the one stated number is 0.117 s for a pop-in with a 110% overshoot (Isaac); a zoom on footage is eased (Isaac, Hals).
- "Win the first three seconds / lead with the most interesting moment": nuanced by Smith: lead with the tension and the question, not the answer.
- "No intro, no outro / end on the upswing": confirmed by Hals; contradicted by Sbiti's end card.
- Effects per minute: Hals about 7/min by eye; StreamScheme says keep extras simple. No clear single number.

## Montage (playbook `onTheBeat`; genre Montage)

**Watched:** Joshyy (Fortnite, DaVinci Resolve), MagnnuM (CS2 frag movie, Vegas Pro 16), Vaultcar (vertical car speed-ramp edits, Resolve), plus Hermans's beat-grid and speed-ramp from the cinematic group. Two of the three had only auto-translated caption tracks (Bengali, Arabic), so those helpers read a translation and checked numbers against the screen where they could; the speeds in Joshyy that are not read off a frame are marked below.

**What the editors say**
- Songs for kill montages always have drops; place a marker on each drop in the waveform and a marker on each clip's key moment (the kill), then line them up [Joshyy 03:05–04:46, said; markers about 3.7 s apart, 04:15 and 05:05, seen].
- Open with a great clip and put the standout shot at the song's peak; put the best clips on the important parts of the song [MagnnuM 00:00–00:21, said].
- On a great kill: step frame by frame, cut on the 2nd or 3rd frame after the kill feed appears (about 0.07–0.10 s at 29.97 fps), add a zoom and a brightness flash that eases from 11 to 0 over the clip; use it only on the great kills [MagnnuM 03:06–04:08, said].
- Slow motion goes after the kill, not into it: about 0.85 s at 45–60% speed with Optical Flow [Joshyy 05:26–06:26, said; Optical Flow, 06:35, seen; the exact speed percentages rest on a translated caption and are unverified].
- Cut on every second to fourth beat, never every beat, while speed-ramp keyframes land on every beat; gaps of 0.85–1.7 s on a grid of about 0.42 s [Vaultcar 04:31, said; cut gaps at 157.75–166.68 s and 739.1–748.1 s, measured; the BPM is inferred from cut spacing, not measured]. The same rule appears in a cinematic montage: cut on every 2nd or 4th beat, since every beat feels robotic [Hermans 04:07–04:57, said].
- Impact timing: a shake with a 7-frame attack (0.12 s) decaying over 29 frames (0.48 s total); a falling transition of 21 frames (0.35 s) [Vaultcar 08:28–09:31, said; 09:00 and 06:35, seen]. A white flash of about 5 frames on a speed-ramp peak [Music 05:43, said; 06:09, seen].
- Mix: the song fader sits at −15.3 dB while the game audio stays at 0.0 dB, so the game's sound stays dominant [MagnnuM 04:50, said; 05:40, seen].
- Timeline at 60 fps is the default for montages [Joshyy 02:05–02:25, said].

**What the edits show**
- MagnnuM's sample timeline has a mean event length of 2.7 s, about 23 cuts/min, range 1.2–5.6 s [05:40, seen]. Vaultcar's finished speed-ramp edit has gaps of 0.85–1.7 s, mean about 1.3 s, about 45 cuts/min, and about six effect clips in its first 6.5 s [measured at 143–167 s and 718–758 s; seen 08:40 and 10:00, estimated].

**Against today's playbook**
- 22 cuts/min, 2.7 s: confirmed for frag movies (MagnnuM); the car speed-ramp style is a faster sub-style (about 1.3 s and 45 cuts/min).
- "Cut on the kick and the snare": refined, not confirmed as written. The editors align the key moment to the drop, or cut every 2–4 beats, and keep per-beat movement (ramp, shake) for the beat itself.
- "Slow down for the best one: a time ramp into the play": partly contradicted: the slow-motion piece follows the kill (Joshyy), and the ramp-style edits ramp every clip (Vaultcar).
- `musicBed` 1: contradicted in level by MagnnuM (song 15 dB under the game's own sound).
- "Hold back before the drop": nothing was said or reliably seen about it.
- `effectsPerMinute` 3: Vaultcar's style uses several times that, tied to beats, not on every beat.

## What moved in PULSE, and what was left alone

A number moved only where two or more independent videos disagreed with it and moving it did not change how the style cuts on thin evidence. Principles (the words) were rewritten more freely, because they describe craft the videos stated outright.

| Style (genre) | Number | Was → now | Evidence |
|---|---|---|---|
| `retention` (Gaming video) | `zoomRamp` | 0.16 s → 0.12 s | text pop settles in 0.10 s [Gaming101 09:14]; zoom keyframes "a couple of frames" apart [Beginner 03:54]; speed-ramp ease about 0.13 s [Music 05:25]; 0.117 s pop [Isaac 13:28]; five frames and "a few frames" [MortarMarv 06:11, ItsProger 02:45] |
| `retention` | `maxCaptionWords` | 4 → 3 | three words or fewer [Leo 07:13]; Finzar's captions are one or two words [Beginner 06:00, Viral2026 06:12] |
| `story` (Challenge or story) | `hookDeadline` | 15 s → 20 s | promise spoken at about 0:20 [Dovey 00:20, Runia7 00:20, Runia5 00:20–00:41]; setup, context and challenge inside 30 s [Dovey 09:11] |
| `story` | `rehookInterval` | 150 s → 120 s | topics every 83–158 s, about 120 s on average [Runia5]; beats every 20–80 s [Dovey]; parts of 40–90 s [Neistat] |
| `vlog` | `cutsPerMinute`, `averageShotLength` | 10 → 6 cuts/min, 6 s → 9 s | 4–6 cuts/min with 10–13 s shots, none of them zooms [Neistat]; 4–7 cuts/min blended, 2–3 for the plain talking head [Dovey] |
| `vlog` | `hookDeadline`, `rehookInterval` | 12 s → 20 s, 150 s → 120 s | as for `story` |
| `smooth` (Cinematic) | `opensFast` | false → true | a 40 s run of shots about 0.5–1.5 s long is the hook [Andrew 00:00–00:40]; the finished sequence is shown inside the first 40 s [Hermans] |

Two of these change how the style cuts, not just what it says: lowering `vlog` to 6 cuts/min makes its pace "steady" instead of "fast", so the edit is balanced rather than energetic and no longer punches in on every sentence (rhythm zooms start at 8 cuts/min); and `opensFast` is only a label (every long style already opens on its best moment). The vlog change is the most judgement-heavy: it rests on two real vlog-style edits, and no vlog tutor stated a figure. The others only change coach advice (`hookDeadline`, `rehookInterval`, `maxCaptionWords`) or the speed of a punch-in.

**Principles rewritten or added** (each is traced to its videos in the genre sections above): `retention` (no like or subscribe ask and what/how/why in the opening; cut a scream just after it starts; effect levels and the "three or four" loud-blast cap; layer a moment and count it once; hide the cut under the transition; keep a little air), `story` (a taste at once and the promise by about twenty seconds; change the pace on purpose; silence at the turn), `vlog` (setup, conflict, resolution; time-lapse and drone only for transition or context; mix handheld, locked-off and wides; let the music drop where someone explains), `smooth` (the shape of an eased move; cut on every second or fourth beat; sound leads or trails the picture; open on motion; cut on action), `beat` (land the kill on the drop and cut every second to fourth beat; a quick hit and then a short slow-motion tail), `short` (lead with the question and keep the payoff to the end), `commentary` (music about 20–33 dB down on its fader with a new track per chapter; a cutaway of two to four seconds on the layer above).

**Left alone, and why**
- `retention` 12 cuts/min and 5 s shots: Finzar's 2019–20 videos run at about twice that or more (13–33 a minute) and his 2026 one at about 9–11; the gaming guides watched run lower (MidnightMan about 4.7 boundaries/min); Leo says density is an audience choice. `popupsPerMinute` 1.0 and `effectsPerMinute` 4 (cap 8): nobody states a rate; the comedy videos are far denser, the 2026 one sparser. `zoomScale` 1.22: not confirmed (the only readable punch-in depth is a 2.2× zoom on a small detail; 122% appears only as a facecam size). `musicBed` 0.75: split (MidnightMan none under gameplay; Finzar and Leo a continuous bed). `pauseRatio` 0.04: Leo calls removing every pause a dial, and Finzar's 2026 advice is to keep some air, so it was softened in words only. `hookDeadline` 8 s: the best moment is on screen early in most of them, but the spoken promise comes later (Finzar's own videos at 0:01–1:27).
- `commentary` 3 cuts/min and 20 s shots: contradicted for retention-style YouTube talking heads (5–14 cuts/min, shots of 5–12 s, with b-roll covers and graphics counted), but right for raw A-roll between covers and for podcast clips (about 3 cuts/min [Sbiti]). Changing it would turn a calm style into a steady one on the evidence of one calm essay (about 5 cuts/min [indietrix]); effects per minute (0.2) and `zoomScale` (1.08) are contradicted the same way and left for the same reason.
- `smooth` 6 cuts/min, 10 s shots and `zoomRamp` 0.6 s: consistent for talking-and-b-roll bodies (lacapture 6.7/min and 8.6 s, Andrew about 10 s) and not tested for ramp time by anyone; a beat-led montage is far faster (Hermans 26 cuts/min).
- `beat` 22 cuts/min and 2.7 s: confirmed by one frag-movie timeline (MagnnuM, 2.7 s mean, about 23/min); the car speed-ramp style is a faster sub-style (about 1.3 s, about 45/min) and was not given a style of its own.
- `punchyShort` captions (mixed case, 0.68 down) and 18 cuts/min: the creators watched split on case (all caps in Hals and Senpai, mixed case with a coloured word in other examples), and position agrees (0.70 in Hals).
- `streamHighlights`: nothing watched covers it (see that section); the style is exactly as written.

## Patterns across genres

- **The tutors' own videos are busier than the styles they teach.** Cinematic tutorials open on shots of 1–2 s; the calm-commentary and story videos intercut b-roll, graphics and transitions at 5–14 cuts/min; Finzar's comedy tutorials cut at 20–30 per minute. A tutorial is an entertainment product, so its own cut rate is a poor guide to the style it describes.
- **Style drifts.** Finzar's 2019–20 videos are the dense meme-and-cut style the `retention` numbers describe; in 2026 he says viewers no longer like relentless cutting, asks for room to talk, and uses no memes [Viral2026 06:18, 07:52–08:08].
- **Timing lives at three scales.** A hit or a pop-in is about 0.1 s (a few frames); a transition is about 12 frames, 0.2 s at 60 fps; a slide or a facecam enlargement is one to two seconds (MidnightMan 1.2 s [07:25–07:46]; Finzar's demo slide about 1.9–2 s [Secret 04:18–04:58, seen, estimated]). A single `zoomRamp` number cannot describe all three, and "smooth" in Finzar's sense is the shape of the curve, not slowness.
- **Pace is contrast.** Two tutors say outright that the mistake is holding one pace: fast bursts against calm holds, with the sound dropping at the turn [Runia5 03:05–04:51, Runia7 07:22–08:05]. Two more say the same thing in kind: pace should follow the feeling [StudioBinder 01:45], and stopping the music abruptly spotlights a moment [Leo 13:06–13:27].
- **Sound is taught as roles and levels, not counts.** Whoosh, riser, hit and drone each have a job; effects sit well under the voice; nobody gives an effects-per-minute figure, and layering means one moment can hold three sounds.
- **Beats are cut every second or fourth, not every one** (Hermans, Vaultcar, Runia5 for the same reason: constant cutting on the beat feels robotic and repetitive).

## What is still not known

- **Long stream highlights.** No video watched shows how an edited highlights video should look, and four searches found no editor of a large streamer explaining their process. The next step is to find one (or a few highlight videos from large channels and measure them directly).
- **What to hold back before a drop** (montage): nobody said anything and no frame showed it reliably.
- **"Leave mid-thought"** (vlog): nobody said it; the nearest idea watched is cutting during an action.
- **Hook deadline and music bed for gaming videos; effects per minute for any genre.** The videos give no rate.
- **Anything about sound that needs listening.** Nobody listened. The `/watch` skill can ask Google's video model to watch with sound given a free Gemini key; that would settle music-bed levels and what the effects are.
- **Pace of commentary.** The calm voice-led essay and the YouTube talking head are two styles; PULSE has one.

## Source index

Short name, title, channel, length. All were watched in full (long ones with focus windows for the frames, whole transcript read). "Sponsor" means a sponsor or promotional segment was present and ignored.

| Short name | Video | Length | Notes |
|---|---|---|---|
| Gaming101 | [How to Edit a Gaming Video (For Beginners)](https://www.youtube.com/watch?v=lYj7Mouw-dc), Finzar | 13:54 | 1.5M views; sponsor |
| Beginner | [How To Edit: Ultimate Beginner's Guide](https://www.youtube.com/watch?v=lODhwmdCudM), Finzar | 12:55 | |
| StopEditing | [Stop Editing For SO LONG!](https://www.youtube.com/watch?v=QtOumf09MEQ), Finzar | 10:16 | mostly workflow; sponsor |
| Funny | [How to Edit a Funny Gaming Video](https://www.youtube.com/watch?v=D5H6wdrB7e0), Finzar | 8:09 | |
| Viral2026 | [How I'd Edit a Viral Gaming Video in 2026](https://www.youtube.com/watch?v=_laioiIuvtw), Finzar | 10:03 | |
| 8Hours | [I Took a New Editor from Beginner to PRO in 8 Hours](https://www.youtube.com/watch?v=Cqkgst1mRo0), Finzar | 11:57 | mostly a course promo |
| 100Videos | [I made 100+ gaming videos. This is what I learned...](https://www.youtube.com/watch?v=i72rQaXJ91k), Finzar | 9:37 | intros only; sponsor |
| Transitions | [How To Edit Super Smooth Transitions in Premiere Pro!](https://www.youtube.com/watch?v=eEVxr6lzQSc), Finzar | 9:56 | sponsor |
| YT2026 | [How To Edit YouTube Videos in 2026 (Ultimate Guide)](https://www.youtube.com/watch?v=xmfSCKV7qUE), Finzar | 22:11 | |
| Secret | [The Secret To Editing Professional Videos in 2026](https://www.youtube.com/watch?v=RutTgrCATwk), Finzar | 8:35 | the closest match found for "The Real Secret to PRO Level Editing"; title unconfirmed |
| SFX | [How To Edit Sound Effects (Premiere Pro)](https://www.youtube.com/watch?v=dfOffqhCiwo), Finzar | 9:24 | the sound-effects video the newsletter named |
| Storezar-SFX | [How to Edit The BEST Sound Effects For Beginners](https://www.youtube.com/watch?v=L4da128D6Xc), Storezar | 3:07 | demo of his own pack |
| Memes | [How To Edit Memes in Your Gaming Videos (3 EASY WAYS)](https://www.youtube.com/watch?v=Ormb3Z0QJVs), Finzar | 11:28 | sponsor |
| Music | [How To Edit Gaming Videos With Music (Premiere Pro)](https://www.youtube.com/watch?v=Xsdq23-cfT4), Finzar | 9:01 | no music-mixing advice; sponsor |
| Leo | [How to edit SO good your viewers get addicted to your videos](https://www.youtube.com/watch?v=sLgHqZSe2o0), Learn By Leo | 14:32 | about 6M views; not gaming-specific |
| MidnightMan | [How To Edit Gaming Videos Like a Pro Using CapCut Desktop](https://www.youtube.com/watch?v=jYqH0P4BwvI), MidnightMan | 15:37 | reads as a product pitch |
| MortarMarv | [How To Edit Gaming Videos For Beginners](https://www.youtube.com/watch?v=9Pn7uGmIU9E), MortarMarv | 8:40 | sponsor |
| ItsProger | [How To Edit VIRAL Minecraft Videos](https://www.youtube.com/watch?v=RmMpeXWP3I8), ItsProger | 11:19 | promotion |
| Senpai | [How To Edit Your Twitch Streams Into YouTube Videos](https://www.youtube.com/watch?v=5RuoLQWvDu8), Senpai | 10:00 | about vertical clips |
| GaelLEVEL | [6 ways to Turn Twitch Clips into YouTube Shorts, Reels & TikToks](https://www.youtube.com/watch?v=HbJkFDvVlLs), Gael LEVEL | 20:46 | sponsor |
| StreamScheme | [How To Use Twitch Clips To Get 2.5 Million Views On TikTok](https://www.youtube.com/watch?v=3WX25xdYnMo), Stream Scheme | 20:34 | sponsor |
| Stirling | [The Easiest Ways to Edit Hours of Gameplay Footage](https://www.youtube.com/watch?v=57azbqwdcqM), Patrick Stirling | 6:58 | found by search |
| Cpaws | [How To EDIT Your Twitch Streams 2026 (For Beginners)](https://www.youtube.com/watch?v=x5frer5MoKk), Cpaws Music | 9:57 | found by search; no craft; sponsor |
| Neistat | [How to vlog like Casey Neistat](https://www.youtube.com/watch?v=Q980C74SdYQ), Casey Neistat | 14:09 | 6M views |
| Dovey | [How To Vlog and Be a Better Storyteller](https://www.youtube.com/watch?v=KdsWzPMCv7w), Jeven Dovey | 15:51 | |
| Runia7 | [The ONLY 7 Cuts You Need To Tell Any Story](https://www.youtube.com/watch?v=J0ydlAqg6_8), Tim Runia | 9:23 | promotion |
| Runia5 | [The ONLY 5 Editing Secrets You Need to Tell Any Story](https://www.youtube.com/watch?v=dhpazqW_OaU), Tim Runia | 12:35 | sponsor |
| Huang | [How to Edit ANY Video Like You've Done it 1,000 Times](https://www.youtube.com/watch?v=Zm7J3KqqXPk), Herman Huang | 8:23 | not about story; sponsor |
| StudioBinder | [6 Ways to Edit Any Scene](https://www.youtube.com/watch?v=FVR8zz8ci2k), StudioBinder | 18:48 | |
| lacapture | [How to make ANY video CINEMATIC](https://www.youtube.com/watch?v=D-cKmLBdTL8), lacapturevisuals | 11:33 | shooting craft |
| Duncan | [10 Editing Cuts Every Video Editor Should Know](https://www.youtube.com/watch?v=YtULPT1aBWM), Jonny Duncan | 5:43 | |
| Andrew | [The Power of SIMPLE Editing](https://www.youtube.com/watch?v=pdLEHfkwgV8), Andrew | 5:14 | about a quarter promotion |
| Hermans | [How to Edit a Cinematic Video in CapCut](https://www.youtube.com/watch?v=5QUSuMPD95k), Joris Hermans | 10:00 | product-led |
| vidIQ | [4 Editing Secrets Small Channels Learn Too Late](https://www.youtube.com/watch?v=hY4pybwOUq0), vidIQ | 6:51 | a comedy sketch |
| ThinkMedia | [How to Edit a YouTube Video in 2026 (Start to Finish)](https://www.youtube.com/watch?v=AV4UnrHznR8), Think Media | 18:20 | sponsor |
| Sbiti | [How To Make VIRAL Podcast Clip Videos](https://www.youtube.com/watch?v=uTNnpkpYr0A), Joe Sbiti | 28:58 | course promo |
| ContentCreators | [Edit PRO Youtube Videos in Capcut](https://www.youtube.com/watch?v=Ex1R3rsdlms), Content Creators | 35:47 | course promo |
| indietrix | [How To Make A Video Essay: Editing](https://www.youtube.com/watch?v=Z2z514tcwpc), indietrix | 8:20 | found by search |
| Olufemii | [Cutting Talking Head Footage is a Science](https://www.youtube.com/watch?v=y7GoUICupVM), Olufemii | 4:55 | found by search; sponsor |
| Smith | [How to make shorts that go viral every time](https://www.youtube.com/watch?v=gEQ0BLyVJhY), Logan Smith | 9:41 | 3M views; mostly strategy |
| Isaac | [How I Actually Edit Viral Videos](https://www.youtube.com/watch?v=ciAywjey0cY), Isaac | 22:07 | a long-form essay in Premiere, not Shorts |
| Hals | [How I Edit YouTube Shorts That Go Viral Everytime](https://www.youtube.com/watch?v=tIHBCPINP2k), Hals | 23:06 | faceless commentary shorts; sponsor |
| Joshyy | [How to EDIT Gaming Montages in 2024](https://www.youtube.com/watch?v=WYqTvyXRZ-c), Joshyy | 9:01 | found by search; promo; translated captions |
| MagnnuM | [CS2 fragmovie tutorial - Beginner](https://www.youtube.com/watch?v=ByZ6vHSeX5A), MagnnuM | 9:35 | found by search; translated captions |
| Vaultcar | [How To Actually Make GOOD EDITS - DaVinci Resolve](https://www.youtube.com/watch?v=UDgKrsb1X7A), Vaultcar | 12:38 | found by search; car footage, not gameplay |
