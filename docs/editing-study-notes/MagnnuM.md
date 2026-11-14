# CS2 fragmovie tutorial - Beginner — MagnnuM (09:35, views not shown in report) — https://www.youtube.com/watch?v=ByZ6vHSeX5A
Genre this speaks to: montage (CS2 frag movie, Vegas Pro 16)
Usable?: yes. Short, on-screen real workflow: song-drop placement, cut length, brightness-flash and zoom on kills, crossfade length and the song/game mix level, all visible in the timeline. Not much theory and no drop-build advice.
Evidence available: captions yes but only an automatic Arabic track (556 segments; I read the Arabic and paraphrase in English, so wording rests on my reading; I checked numbers on screen where possible); frames 39 listed (all viewed as contact sheets, 24 of them are the intro/outro sample montage) + 14 extra 1024 px frames (at 150, 190, 215, 238, 245, 252, 258, 300, 340, 380, 450, 490, 540 s and timeline crops); downloaded yes (1280x720, source 59.94 fps)

## Rules stated
- Three things before you edit: pick a song you like (it boosts your creativity while placing clips), watch all the clips before editing so you know where they fit best, and put your best clips on the important parts of the song [said 00:00-00:21]. On-screen text shows "1 - Pick a song you like" and "2 - Watch all the clips before editing" [seen 00:07-00:12].
- Open with a great clip (it hooks viewers quicker); put a standout shot at the song's peak/climax [said 00:21].
- Recording: OBS replay buffer set to 120 seconds (last two minutes saved on a key press); editor is Vegas Pro 16 [said 00:43].
- Every clip: right-click, Switches, Disable Resample (keeps it sharp and avoids unwanted extra motion blur); always answer "No" to the project-settings prompt [said 01:04, 05:56].
- Cut with S, delete the excess, drag the clip back; zoom the timeline with the mouse wheel [said 02:05-02:25].
- Cut "a few seconds after the kill" and trim the dead part (his example cuts the "fart" bit) [said 02:45].
- Always overlap neighbouring clips a little so they crossfade ("a nice fade"); on another pair he says "not a lot of fade" [said 02:45-03:06, 04:29].
- Great kills: step frame by frame; once the kill feed appears he cuts on the 2nd or 3rd frame, adds a zoom (he says to protect the sound) and a brightness flash using the BCC Brightness-Contrast plug-in; Brightness set to 11 at the start, 0 later in the clip (length depends on the clip); he used 15 before, 11 now because CS2 is very bright [said 03:06-04:08]. Same recipe repeated at each shot of a multi-kill [said 06:43-07:04].
- Match the clip's loudest hit to the song's drop: "this is the drop we want", place the shot where the beat starts [said 04:50, 06:16]. Time the cut so the next kill lands on the next drop; he tries it and re-aligns until the timing looks right [said 05:11-05:36, 07:24].
- Mix: the clip's audio must not be too quiet next to the song; find a level "somewhere in the middle" [said 04:50].
- Extra polish: a NewBlue MB Zoom transition at the end of a clip (a straight zoom into the next clip), a custom plug-in [said 07:44-08:05].
- Later parts he promises (not shown): slow-motion, a cinematic filter, a motion-blur effect [said 08:46-09:06].

## What the editor's own timeline and effects show
- Project: Vegas Pro 16, preview shows 1920x1080, 29.970 fps; source clips 60 fps (media properties read "60,000 fps"; timeline "Project: 1920x1080x32, 29,970p") [seen 02:30, 03:10].
- Event-length measurement: in the 25 s timeline of about 10 "nice_3k_clutch" events (ruler about 63 px per second in the crop) the event lengths are about 2.3, 2.7, 1.2, 3.7, 1.3, 2.1, 3.0 and 5.6 s: mean about 2.7 s, range 1.2-5.6 s, so about 23 cuts per minute [seen 05:40; estimated by reading pixel positions].
- Crossfade tag reading "0.06" at an event boundary (about 0.06 s, about 2 frames at 29.97 fps) [seen 05:40]; one audio crossfade shape about 0.3 s wide by ruler eye [seen 04:18].
- Song track: "2Pac feat. Snoop Dogg - Streets r Cent Remix" on track 3, volume fader reading -26.9 dB at 05:00, raised to -15.3 dB at 05:40 and 06:20 and 08:10; the video/game-audio tracks stay at 0.0 dB [seen 05:00, 05:40, 06:20, 08:10]. So the game audio sits about 15 dB above the song.
- Brightness-Contrast effect panel: Brightness keyframe lane, value box showing 11; lane ruler 0 to 3 s; the end keyframe (0) is not visible in my frames, so its time is unknown [seen 04:05, 04:12].
- Event markers: small blue ticks at cut points on the audio envelope (fade-in/out at each cut) [seen 05:40].
- The finished timeline at 06:20-08:10 has a "meh_3k_awp_vertigo" second clip group with the zoom transition preset list (NewBlue MB Zoom presets: Straight Zoom, Centered Zoom Blur, Fold Left/Right, Gentle Dissolve) [seen 08:10].
- No titles, no captions, no speed ramps shown.

## How the video itself is edited
- Cut rate [measured, scene > 0.35]: 5-185 s = 5 cuts = 1.7/min (the opening gameplay sample plus Vegas screen recording from 01:04); 300-480 s = 1 cut = 0.3/min (full-screen Vegas screen recording). Not pacing figures; it is a screen recording with his voice.
- Opening sample [measured, scene > 0.3]: scene changes at 5.6, 6.8, 7.1, 9.1, 11.9, 16.6, 17.0 s; i.e. a 5.6 s opening shot, then shots of about 1.2, 0.35, 2.0, 2.8, 4.7 s [first frame at 00:00; measured]. The first 17 s carry on-screen rules text over a blurred clip. Ending sample 542.4, 543.6, 543.9, 545.9, 549.3, 553.4, 553.8 s [measured].
- Hook: gameplay (AWP, circular scope) from the first frame, a spoken promise at 00:00 ("a nice CS2 video without flashy effects, just coordinated clips and simple editing") [heard 00:00].
- No sponsor segment; a Twitch plug at the end (twitch.tv/MagnnuM at 09:20); in-game stream overlays carry gambling-site ads (CSGOFAST, GGDrop) inside his footage [seen 00:00, 09:20].
- No music or SFX under his talking, no captions.

## Against today's playbook
Compared with onTheBeat (cutsPerMinute 22, averageShotLength 2.7 s, zoomsPerMinute 4, zoomScale 1.18, effectsPerMinute 3, fadesPerMinute 0.3, musicBed 1, hookDeadline 3, zoomRamp 0.1, principles about kick/snare, build/drop/breathe).
- averageShotLength 2.7 s and cutsPerMinute 22: his timeline measures a mean event of 2.7 s (about 23 cuts/min), range 1.2-5.6 s [seen 05:40]. Confirms the fingerprint closely, with the caveat that it is 25 s of one tutorial timeline.
- "Cut on the kick and snare": his rule is to land the loudest moment on the drop and to place the best clips at the start and at the climax; he never says to cut every beat [said 00:21, 04:50, 06:16]. Supports drop-level sync, not kick-level cuts; against a literal "every kick" reading.
- "Hold back before the drop / a flash on every beat stops meaning anything": he adds the flash/zoom only on "the great kills", at the 2nd-3rd frame after the kill feed (2-3 frames is about 0.07-0.10 s at 29.97 fps) [said 03:06-03:47]. Supports sparing use and a very short, hard impact.
- zoomRamp 0.1: the kill zoom is a hard cut-in on frame 2-3, with the brightness flash easing from 11 to 0 over the remainder of the clip [said 03:47-04:08]; the 0.1 s order of magnitude fits for the zoom, but the brightness decay length is unseen.
- fadesPerMinute 0.3: his cuts carry very short crossfades (about 0.06 s tag), so they are cuts for practical purposes, with a zoom-blur transition only now and then [seen 05:40; said 07:44].
- musicBed 1: here the song sits at -15.3 dB while game audio stays at 0.0 dB, so the game's own sound stays dominant; he says the clips must not get too quiet against the song [said 04:50; seen 05:40]. This differs from "the music is the script" as a full-level bed.
- hookDeadline 3: best clip first, and the sample opens on a clip in the first frame [said 00:21; seen 00:00]. Confirms.
- No evidence here on time ramps (slow-mo is deferred to part 2), shake frequency, or what is held back before a drop.

## Caveats
Beginner tutorial from one streamer with a small channel; the only timeline shown is about 25 s of an unfinished edit. Captions are an automatic Arabic track and my reading may mislead on nuance (the "zoom to protect the sound" line is unclear). The timeline is 29.97 fps over 59.94 fps sources. Event lengths are read from pixel positions on a 1024 px frame, so +/-0.2 s. Third-party plug-ins (BCC, NewBlue) are paid.
