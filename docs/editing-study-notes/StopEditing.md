# Stop Editing For SO LONG! (it will change your life) — Finzar (10:16, views not shown in report) — https://www.youtube.com/watch?v=QtOumf09MEQ
Genre this speaks to: general (editing workflow and time management; the demo is a green-screen comedy skit, not gameplay)
Usable?: partly. It is mostly about how long to sit at the editor, with a sponsor read for a time-tracking app (Rise); the craft content is three "same clip edited in 10 / 30 / 60 minutes" demos, which show what extra time buys (keyframes, motion blur, letterbox, sound design).
Evidence available: captions yes (auto, en, 568 segments, read in full); frames 50 listed (read as 3x3 contact sheets, 6 sheets) + 6 extra 1024px frames; downloaded yes (1280x720 AV1)

## Rules stated
- Focused editing in short blocks beats long sessions: he claims 30 minutes concentrated gives more than 2 hours unstructured [said 00:00].
- His answer to "how long should you edit at a stretch" is about 45 minutes; step away if you get bored at the 30 or 45 minute mark, then return fresh and often change what you just made [said 08:30, 08:51]. He takes a break every 45 minutes [said 08:51].
- A 10-minute edit is "obviously going to look this bad"; only worth it on a deadline [said 02:02]. What he did in 10 minutes: pictures and PNGs from Google, hand-animated with no keyframes; he would not reuse that effect more than once because it gets old fast [said 02:42, 03:02].
- With 30 minutes he used keyframes on the Motion box (no motion blur, so no extra effect to add), and dragged the bezier handles to give each move "character" instead of constant speed [said 05:47, 06:27]. He adds that no motion blur can be better, especially on text [said 05:47].
- 30-minute result is for "the middle of the video", not the intro; "the intro needs something really polished" [said 06:27]. He scores the 30-minute version 6.9 out of 10 [said 06:27].
- With 30 minutes he also used a lot more "cinematic booms" in the audio [said 06:27].
- With one hour: proper asset sites (Production Crate), the Transform effect with the shutter angle "all the way up to 360" for smooth keyframes with motion blur [said 07:49], a letterbox overlay for "a false sense of being in a cinema" [said 08:09], and "heaps more" audio design [said 08:09].
- Sponsored segment (time tracker, Rise, with code and 14-day trial) [said 03:24-04:45]; treat that stretch as not editing content.

## What the editor's own timeline and effects show
- Premiere project named "10 min vs 30 min vs 60 min"; the timeline has V1-V5+ video tracks and three audio tracks A1-A3 in the 10-minute version, with the still PNGs as pink clips and nested sequences as green clips [seen 06:03, 1024px frame].
- Motion panel for a cut-out PNG ("frog arm.png"): Position 1214.7 / 1413.6, Scale 415.0, Anchor 91.5 / 147.5, Opacity 100% [seen 05:54]. This is a small PNG scaled up, not a zoom recommendation.
- Presets bin he built: "0. Main Tools" with Basic 3D, Crop, Drop Shadow, Green Screen, Transform (Motion Blur); "1. Audio FX"; "2. Video FX" with Basic 3D Pan, Black & White [seen 07:54, 1024px frame]. A "Transform (Motion Blur)" preset is therefore one drag away.
- Letterbox clip "2-75-1 letterbox.png" (a 2.75:1 frame image) on a high video track above an adjustment layer, Blend Mode Darken, Scale 348.0, Position 960 / 540, Anchor 394 / 221.5; clip about 5 s long against a ruler of 00:00:55:00 to 01:05:00 [seen 08:15, estimated from tick spacing].
- 1-hour version audio: six audio tracks packed with dozens of short sound clips, each with an fx badge, many with "Constant Power" crossfade badges; some clips look under about one second wide [seen 08:21 and 09:00, zoomed frames, counted by eye].
- Video side of the 1-hour edit: stacks of adjustment layers, nested sequences, PNG stills and footage clips layered across six or more video tracks inside a few seconds of timeline [seen 08:38-09:00].

## How the video itself is edited
- Cut rate [measured]: 30-210 s = 70 cuts, 23.3 cuts/min, mean shot 2.5 s (green-screen skit with a meme or stock cutaway every few seconds, a 1:31:04 screen-recording clock, no timeline). 330-510 s = 58 cuts, 19.3 cuts/min, mean shot 3.1 s (about half screen recordings of Premiere panels and half green-screen skit). The screen-recording half barely changes, so only the first figure is a fair pacing number, and cutaway-driven.
- Picture type [seen]: Finzar floats in a bean bag over a different background about every 2-3 s (bouncy castle, stand-up stage, castle, sea floor); background plates change with the joke.
- Captions/text [seen 02:08, 04:17]: big title cards in heavy uppercase sans ("10 MINUTES", "BREAK TIME"), white on a plain or full-frame backdrop; no running subtitles in what I read.
- Hook [heard 00:00-00:20, seen 00:07]: opens on a garden shot and a screen clock 1:31:04 within 7 s, the problem ("editing too long") named at 00:00 and the promise (enjoy editing, 30 focused minutes beat 2 hours) at about 00:15.
- Sponsor: 03:24-04:45 (about 80 s, 13% of the video) as a skit in a suit; second thanks at 09:33.
- Sound [captions/said]: [Music] markers at 03:24 and 10:03; he says the 30-minute version added "cinematic booms" and the 1-hour version "heaps more" audio design (see timeline frames). Level and sound-effect counts not measured.
- End card: field background with "sub for more finzar" at 10:01, about 15 s.

## Against today's playbook
- retention.cutsPerMinute 12 / averageShotLength 5: this skit-style video measures 19-23 cuts/min and a 2.5-3.1 s shot in its fair stretch, about double the playbook. Scene changes from keyframed backgrounds count too, so the true edit rate is probably a little lower. [measured 30-210 s]
- retention.zoomRamp 0.16 / glide: no timing number given. He says motion blur and bezier handle shaping are what separate the 30-minute and 60-minute edits [said 06:27, 07:49]. That supports the playbook's "smooth" principle that moves should ease, but gives no seconds.
- Motion blur: shutter angle 360 on the Transform effect for keyframed moves [said 07:49]. PULSE has no shutter-angle field; if the compositor blurs fast moves, 360 degrees is his "maximum smooth" setting. Single source.
- retention.effectsPerMinute 4 / maxEffectsPerMinute 8: the 1-hour edit shows six audio tracks full of short sound clips (my count by eye, several per second at the dense spots) [seen 08:21, 09:00]. That is far above 8 per minute locally, though it is a comedy skit and not gameplay. Treat it as evidence that his top-end "sound design" is dense; no per-minute number is given.
- Letterbox overlay (2.75:1, Darken blend) as a cheap "cinematic" cue [said 08:09, seen 08:15]. Not in any playbook; relevant to `smooth`/`story` only.

## Caveats
- Not a gaming video and not mainly a technique lesson; the sample is a green-screen skit about a chatbot story. Cut rates describe that skit.
- The sponsor stretch (03:24-04:45) and the 45-minute rule are workflow advice, not edit parameters.
- Sound-effect counts and music level not measured; letterbox clip length estimated from a blurry ruler.
- I did not listen to the audio: "heard" tags mean the auto-captions of his speech; music and sound-effect presence comes only from caption [Music] markers and from what he says, and levels were not measured.
