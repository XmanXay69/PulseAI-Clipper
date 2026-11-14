# How to Edit a Gaming Video (For Beginners) — Finzar (13:54, 1.5M views) — https://www.youtube.com/watch?v=lYj7Mouw-dc
Genre this speaks to: gaming video
Usable?: partly. A comedy-wrapped Premiere Pro mechanics tutorial; roughly 1 in 4 minutes is promotion (a music-licensing site and his own preset pack), but the craft numbers it does give are concrete.
Evidence available: auto-captions yes (3,001 words), 60 frames read (of 586 scene candidates), video downloaded (1280x720 AV1 60 fps), 5 cut-rate stretches measured.

## Rules stated
- Cut every stretch of silence back to the last audible sound: drag the clip end to the end of the waveform, delete the gap, let the timeline ripple closed. Dead space "kills pacing" in gaming videos [said 02:43–03:03].
- Funniness test for every bit: watch it a third time; if it is not funny, remove it and see whether it flows better without it. If better, it stays out [said 03:23].
- Zoom and track in on things that matter to the story: on-screen text, important objects, people [said 04:04]. Tracking is done by hand with scale/position keyframes every few frames, with a centre crosshair of guides (540 px horizontal, 960 px vertical on a 1080p frame) [said 04:24–04:45].
- Zooms look best with motion blur: apply a Transform effect rather than only Scale; his preset pack contains "smoothest zooms" [said 05:06].
- Music goes underneath the gameplay audio, never on top, and is turned down with the gain key to about minus 16 dB; he says this "sounds best" (a taste figure) [said 07:30–07:51].
- Subtitles: Montserrat font, white on black stroke about 12, black shadow; centre them with snapping [said 08:33–08:54].
- Subtitle pop-in animation: three scale keyframes on frames 1, 4 and 7 at 75–80%, then 120%, then 115%; "in my experience the best popping effect" [said 09:14]. At his 60 fps project that is 0.05 s to the overshoot and 0.10 s to settle.
- Transitions: Premiere's built-ins are mostly poor; use preset-based ones. Build from adjustment layers set to the project frame rate (60 fps preferred), each about 12 frames long (0.2 s at 60 fps), stacked so one more layer covers both [said 09:34–10:16]. Only one default transition (Mobius Zoom) is acceptable [said 10:38].
- Sound effects: the biggest mistake is making them too loud; lower with the gain key and keep the level meter out of the red. The first priority for effects is transitions: every transition gets a fitting sound (whoosh, glitch), the same sound under each of the same transition [said 10:59–11:40].
- Voice: Parametric Equalizer set to the "vocal enhancer" preset gives a voiceover sound [said 11:40].
- Export H.264 at a high bitrate, around 20 Mbps [said 12:23].
- Meta-rule: do not over-edit; keep enjoying it [said 12:44].

## What the editor's own timeline and effects show
- Premiere Pro with source monitor, program monitor, project bin and one main timeline at about 1/4 of the screen height; one video track with the gameplay chopped into consecutive clips, 2–3 audio tracks below with visible waveforms [seen 02:19, 03:50]. The 512 px frame is too small to count clips or read their lengths, so no clip-length figure is claimed.
- Transition rig: two short adjustment layers sit side by side on the cut, each about the width of the clip overlap, with a third adjustment layer spanning both above them (3 effect layers per transition) [seen 10:33].
- At 04:20, while he explains tracking, the picture is a tight crop of the timeline header (timecode 00:01:00:19, the capture's file name) rather than a keyframe panel; the keyframe values themselves are only said, not read from a frame.

## How the video itself is edited
- Cut rate (hard scene changes, 320 px, ffmpeg scene>0.35) over five 3-minute stretches [measured]: 10–190 s 24.3 cuts/min (comic skit intro, talking head, graphics); 200–380 s 19.0 (Premiere screen recording interleaved with talking head); 400–580 s 14.0 (screen recording of Premiere); 600–780 s 10.7 (subtitle and transition demos on screen); 700–834 s 24.2 (sound effects, outro with sketch). Mean shot in the busiest stretches about 2.4 s; in the plain screen-recording stretches 4–5.5 s. Note the scene filter also counts a zoom or a graphic landing.
- Speech: about 216 words/min including the comedy skit (3,001 caption words in 13.9 min) [measured from captions].
- Opening: no promise of the video in the first seconds; it opens on a scripted skit (a character "juice" argument, a comic-burst graphic reading "GAMING YOUTUBER!" at 00:38) and only moves to the tutorial at about 01:12–01:21 [seen/heard 00:38, 01:12]. The premise ("I will train you so everyone wants to watch your gaming video") is spoken in the first 37 s [heard 00:20–00:37].
- Burned-in captions on the tutorial itself: yes, used as jokes, parenthetical in lowercase at the bottom ("this actually happened") [seen 02:19]; large white caps with a coloured word for emphasis (BEFORE white, AFTER green) over the timeline at 07:57 [seen 07:57].
- Zooms/punch-ins and effects: constant. Heavy digital zoom and whip blur between beats (motion-blur frame at 08:28, hard crop on a figure at 05:01), black-and-white halftone sunburst graphics, a Storezar sunburst promo card at 09:48 [seen].
- Sponsored/promo segments: Lickd (music licensing) plug with a long sketch about copyright, about 05:47–07:08 (about 80 s); his own preset pack mentioned at 05:06, 09:34–10:16, and again at 11:40 ("promise that's the last time"). Roughly 3.5 of 13.9 minutes are promotion or sketches about it [estimated from captions].
- Music: present under the skit and outro; the in-video demo plays it at the minus 16 dB he recommends [heard 07:51].

## Against today's playbook
- retention: cutsPerMinute 12 / averageShotLength 5. Measured here: 10.7–24.3 cuts/min, mean shot 2.4–5.5 s. The 12 figure matches his plain tutorial stretches; his entertainment stretches run about twice that. Supports keeping 12 as a floor, and 20+ as the "comedy skit" top end.
- retention.zoomRamp 0.16 s (footage). Subtitle pop-in is 0.10 s to settle (3 keyframes: frames 1, 4, 7 at 60 fps) [said 09:14]: consistent with a snappy 0.1–0.16 s for text/pop-up, not for footage zooms.
- retention hookDeadline 8 s: this video does not meet it (skit first for about 75 s), so a very popular gaming tutor does not follow the 8 s promise rule; the premise is stated by 0:37.
- Sound effects: his rule is loudness and placement (transitions first), not a count per minute; no number for effects per minute is given.
- Music: −16 dB gain under gameplay [said 07:51] is a concrete default for the music bed when speech/gameplay audio is present.
- Transition length: about 12 frames (0.2 s at 60 fps) [said 09:55].

## Caveats
- One creator's taste; he calls some figures personal ("sounds best"). Heavy comedy and promotion make this a poor guide to a serious pacing number. Auto-captions mis-hear some words ("Ripple delete for you", "Bandy cam"), so only numbers confirmed by the on-screen values are used. Frames were sampled (60 of 586 candidates); the count of effects per minute is not measurable from this sampling.
