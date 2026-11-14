# How to EDIT Gaming Montages in 2024! (DaVinci Resolve Beginner's Guide) — Joshyy (09:01, views not shown in report) — https://www.youtube.com/watch?v=WYqTvyXRZ-c
Genre this speaks to: montage (Fortnite kill montage, beginner level, DaVinci Resolve)
Usable?: yes, partly. A real beat-marker workflow with the timeline on screen (03:05-06:26), plus about 40 s of ad for his own preset pack (01:05-01:45, 07:06-07:49, 08:49-09:01). Beginner depth only; no cut-rate or drop-build advice.
Evidence available: captions yes but only an automatic Bengali track (1600 segments; I read the Bengali and paraphrase in English, so wording and numbers rest on my reading and are cross-checked against the screen where I could); frames 50 listed (all viewed; 40 of them are a 26 s promo montage, so the editor itself is covered by 17 extra 1024 px frames at 130, 205, 215, 235, 255, 290, 305, 320, 345, 355, 365, 372, 385, 395, 430, 440, 470, 495 s); downloaded yes (1280x720 60 fps)

## Rules stated
- A montage needs two things: clips and a song [said 02:25].
- Project settings: 1920x1080 (some use 1440p; use 1080p if new) and timeline frame rate 60 because that is the best for montages, "trust me, use 60" if you are new [said 02:05-02:25]. (Resolve's default of 24 is visible on screen before he changes it [seen 02:10].)
- Songs for Fortnite/Call of Duty/Valorant montages always have beat drops; sync the big moment of each clip to a beat drop of the song [said 03:05].
- Method: drop the song on the timeline, find the first beat drop (the spike in the waveform), press M to add a marker; find the next drop and add the second marker [said 03:25-03:46].
- Then take the next clip into the source viewer, find its key moment (Fortnite: the shotgun shot/kill; Valorant, CS:GO, CoD: the kill/elimination; football: the ball crossing the line), press M on it, and drag the clip so the clip marker sits on the timeline marker; "that's all there is to it" [said 04:06-04:46].
- Repeat for every clip and every drop in the song; extend the head of the clip to fill the space back to the previous clip [said 05:06-05:26].
- Slow-motion: unlink video and audio, razor (B) the clip at the kill marker so the part after the kill is its own piece, right-click Change Clip Speed and set about 60% [said 05:26-06:06]. His own range: 45% to 60% depending on the clip; 40% is "a bit slower" [said 06:06].
- Make the slow-motion smooth: Inspector, Retime Process, Optical Flow [said 06:26]. Seen set to Optical Flow on the slowed piece [seen 06:35].
- Glow effect on a clip: search "glow" in Effects, adjust shine threshold and blend (1 or 0.5) [said 06:46].
- Impact effect: drop an adjustment clip over the moment, apply his "impact" preset and link it to a shake, then adjust the keyframes [said 07:06-07:26] (preset pack, not shown in detail).
- Transitions he mentions: cross dissolve, blur dissolve, zoom in/out/left/right, a 90 degree rotate [said 08:09]. Export from the Deliver tab [said 08:29].

## What the editor's own timeline and effects show
- Song track "Eric Reprid: Pay Me Official Video.mp3" with manual markers on its waveform. Marker positions read off the ruler at two zoom levels (about 16 px/s and 32 px/s): about 8.2 s, 11.9 s and 15.7 s from the song start, so one marker about every 3.7 s (3.66-3.75 s) [seen 04:15, 05:05]. I did not hear the track, so I cannot say what that is in beats; it fits every 8 beats only if the song is about 130 BPM, unverified.
- Resulting video track (about 7 minutes into the video): source clip 1 ends on marker 1 (8.3 s); a short retime-icon piece follows it (about 54 px at 64 px/s = about 0.85 s); source clip 2 runs from about 9.1 s to marker 2 at 12.0 s (about 2.9 s); another retime-icon piece follows (about 0.9 s) [seen 07:10, frame at 430 s]. So per beat cycle (about 3.7 s): about 2.9 s of lead-up, the kill on the marker, about 0.85 s of slow-motion, then the next clip. The actual source-clip change comes about 0.85 s after the marker, not on it; the markers are where the kill lands.
- Cross Dissolve inspector reads Duration 0.4 seconds = 24 frames (at 60 fps) [seen 08:15, frame at 495 s]. Adjustment clip on V2 about 78 px = 1.2 s wide laid over the slowed piece [seen 07:50, frame at 470 s].
- Four clips on V1 and one audio track pair, plus the song; no zoom keyframes, no captions; Transform zoom reads 1.000 on the clips shown [seen 06:25].
- Timeline start timecode 01:00:00:00 (Resolve default); first marker tooltip read "Marker 1" [seen 03:35].

## How the video itself is edited
- Cut rate [measured]: 10-190 s = 57 scene changes = 19.0/min, mean 3.1 s, but this stretch is the "JOSHYY" intro, desktop screen recording and a 26 s promo of his preset pack made of fast Fortnite cuts with 3D-tilt text transitions; 250-430 s = 0 cuts (DaVinci screen recording with a face-cam in the corner). Not a pacing figure for the tutorial.
- The promo montage (01:13-01:39) shows text slamming in ("EFFECTS & PRESETS", "COOL EFFECTS", "100+ FORTNITE PRESETS", "50+ PRACTICE CLIPS", "30+ LUTS & CCS") over fast cuts with whip blurs, tilts and flashes. Scene-change timestamps in 85-99 s cluster at roughly 0.5-1.2 s apart (e.g. 86.2, 86.9, 87.3, 88.5, 89.6, 90.2, 91.3, 92.5, 94.1, 94.6, 95.3, 96.5, 97.3, 98.1, 98.5, 99.7) [measured, threshold 0.25, includes transition flashes, so it is an upper bound]. I did not analyse the audio, so I cannot say if those cuts fall on the beat.
- Hook: first 10 s is Fortnite gameplay with a cut-out-letter "JOSHYY" title and a blur whip; the promise ("how to edit your own montage... free") is made by about 00:25 in the audio [seen 00:00; said 00:05-00:25]. Face-cam in the bottom-left corner of the screen recording throughout.
- Ad: his own "2024 Ultimate Editing Pack" ($5 and $10 packs) 01:05-01:45, plus asides at 07:06-07:49 and 08:49 [said]. He asks for likes/subscribes at 00:25 and 08:29.
- No music bed under his talking; no sound effects; no captions on his own video.

## Against today's playbook
Compared with onTheBeat (cutsPerMinute 22, averageShotLength 2.7 s, zoomRamp 0.1, fadesPerMinute 0.3).
- "Cut on the kick and the snare": he aligns the key moment of each clip (the kill) to marked big beat-drops, one about every 3.7 s, not to every kick [said 03:05; seen 04:15, 05:05]. This is bar-level or drop-level sync, not beat-level.
- averageShotLength 2.7 / cutsPerMinute 22: his source-clip rhythm is about 3.7 s per clip (about 16/min), or about 32 cuts/min if the post-kill slow-mo piece is counted as a second piece [seen 07:10, measured from the 430 s frame]. Somewhat slower than 2.7 s/22 per min for the clip rhythm.
- "Slow down for the best one: time ramp into the play": his method is a step to 45-60% speed on the piece after the kill (about 0.85 s long), with Optical Flow, not a ramp into the kill [said 05:46-06:26]. The slow-mo is after the beat, not before.
- fadesPerMinute 0.3 / transitions: his example dissolve is 0.4 s [seen 08:15].
- "No talking, no captions": consistent for the montage product; he adds text only in the promo.
- Nothing here on building to a drop or holding effects back; no zoom/shake frequency numbers beyond "impact + shake on an adjustment clip".
- A 60 fps timeline is the stated default for montages [said 02:25].

## Caveats
Beginner tutorial for one game; one creator's taste. The caption track is automatic Bengali, so my English is a paraphrase of my reading; I could confirm 60 fps, Optical Flow, 0.4 s/24 frames and the marker spacing on screen but the 45/50/60% speeds are from the captions only (the speed dialog itself was not captured in my frames). The BPM of the song is unknown. The promo section is an advert for his own paid pack.
