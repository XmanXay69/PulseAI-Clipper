# The Easiest Ways to Edit Hours of Gameplay Footage (DaVinci Resolve) — Patrick Stirling (6:58, 175,579 views, uploaded 2020-05-25) — https://www.youtube.com/watch?v=57azbqwdcqM
Genre this speaks to: stream highlights (the step before the edit: triaging hours of gameplay/VOD into clips). It is workflow, not style; neither a long highlights video's look nor a vertical short.
Usable?: partly. It teaches how a human reviews a multi-hour recording quickly in DaVinci Resolve, which is the job PULSE's AI clip finder replaces. It states no pacing, zoom, caption or hook numbers.
Evidence available: captions yes. The report's default track was Arabic auto-captions, so I fetched the English (Original) auto-caption track of the same video with yt-dlp and read that; frames 50 read (all) + 2 extra 1024 px frames (233, 311 s); downloaded yes (1280x720).

## Rules stated
- Two schools for reviewing long footage: a "messy method" (drop the whole multi-hour recording on the timeline and scrub) and a "clean method" (mark in/out points in the source viewer and send only the keepers to the timeline) [said 00:21, 04:43].
- Messy method, keys: press L to play forward, K to stop, J to play backwards; each extra tap of L doubles the speed: 2x, 4x, and on up to 64x [said 01:01-01:22]. When something looks good press B for the blade and cut it, then move on [said 01:22].
- How fast to scrub depends on the game: a first-person shooter needs a slower speed so highlights are not missed; a MOBA can be viewed faster because team fights and map moves are more obvious [said 01:43].
- Mouse scrub in blade-edit mode: hovering plays the footage in the viewer; if the whole recording still fits in the timeline view it is too fast, so zoom in first [said 02:23]. Two drawbacks: the playhead does not move with you (pressing play jumps back to where you left it) and there is no audio [said 02:43].
- His preferred scrub: grab and drag the playhead directly (audio plays, full playhead control) and press Control B to cut at the playhead whenever you find something, without switching tools [said 03:05-03:26].
- Turn on Timeline > "Selection Follows Playhead" so the clip under the playhead is outlined red; when you scrub back over an already-reviewed bad stretch, release and press Control X to cut that clip out [said 04:09-04:30]. Plain delete leaves a gap; ripple delete (the Delete key) closes it [said 03:47].
- Clean method: start with an empty timeline, open the footage in the source viewer, use J K L at 2x, 4x, 8x ("sit back and watch") because dragging a source-viewer playhead over hours is unusable; at the start of a good moment press I, at the end press O, then F9 to drop that range on the timeline; repeat [said 05:10-05:51].
- He expects people to bounce between the two methods depending on the project [said 06:11].

## What the editor's own timeline and effects show
- Resolve Edit page with one video track and one audio track holding a single long clip "2020-05-16 14-24-18.mov" (a Valorant recording); the timeline starts at 01:00:00:00 and the playhead is shown at 01:23:20, 01:24:47, 01:39:35, 01:40:51, 01:47:49, 01:59:16 across the demo, so the demo footage is at least about 59 minutes long [seen 00:54-04:25]. The clip carries a full waveform lane below it.
- After Control B cuts the clip shows 2-3 segments with the middle one outlined red (Selection Follows Playhead) [seen 03:54, 04:40]. Segments are a few seconds wide against a ruler of roughly 1-3 s per tick (labels unreadable at this size).
- Clean method: source viewer on the left with its own in/out markers and the OBS-style recording of the footage; after I, O, F9 a short clip lands at the start of the empty timeline [seen 05:35-05:57].
- He shows the shortcut as an on-screen card, e.g. "Keyboard shortcut / O - Set Out-Point", dark rounded box, white text, lower centre [seen 05:45].
- No transitions, effects, captions, zooms, colour or audio work are shown anywhere [seen throughout].

## How the video itself is edited
- Cut rate [measured, scene > 0.35]: 0-80 s: 10 cuts = 7.5 per minute, mean 7.3 s; 10-190 s: 20 cuts = 6.7 per minute, mean 8.6 s; 200-380 s: 15 cuts = 5.0 per minute, mean 11.2 s; 330-417 s: 3 cuts = 2.1 per minute, mean 21.8 s. The stretches alternate a locked-off talking head (bedroom, mic arm in frame, grey knit top) with short Resolve screen recordings every 7-11 s, so unlike a plain screen recording the cut rate does reflect his A-roll/B-roll alternation, which slows toward the end.
- Hook: first frame black (a one-frame fade-in), then the talking head is already speaking; the promise, how to quickly review lots of footage in Resolve, is complete by about 00:15 and the two-school framing by 00:21 [said 00:00-00:21].
- Cutaways: a clip from a TV office comedy at 00:19 over the "messy method" joke, and a "deal with it" sunglasses-kid clip in the viewer at 05:56 over "nice and clean" [seen 00:19, 05:56]. Two meme beats in 7 minutes, both at a punchline.
- On-screen text: a huge blurred "SCRUBBING" title across the talking head at about 00:54, with letters moving past the camera (a title card beat as the new term arrives) [seen 00:54]. Keyboard-shortcut cards [seen 05:45]. No captions burned in [seen].
- Music, SFX: not assessed (audio not heard). No sponsor segment; the only promo is a subscribe line at 06:44 [said 06:44]. Ends on a black frame at 06:56 [seen 06:56].

## Against today's playbook
- Nothing here supports or contradicts a number for `streamHighlights` (cutsPerMinute 6, avg shot 10 s, hookDeadline 10 s, etc.). It is about finding the moments, not the look. His own video lands near the playbook: 5-7.5 cuts per minute and 7-11 s mean shot in the first 6 minutes [measured], hook by 15-21 s [said 00:15-00:21] versus hookDeadline 10 s; a tutorial, so not a verdict.
- Supports the principle "Cut whatever drags" (the highlights video starts from a long recording and discards most of it) and the idea that a selection pass should be game-aware: slower review for a first-person shooter, faster for a MOBA [said 01:43]. That is a hint for PULSE's clip finder sampling and candidate-window size by game type, not a style number.
- He keeps playback sound off in one scrub method and uses audio in the preferred one [said 02:43, 03:05]: audio waveform and loudness spikes are what a human uses to find highlights, consistent with PULSE's loudness/laughter signals.

## Caveats
The video is a software-shortcut tutorial recorded in 2020, with no style content, no vertical or long-highlight edit shown, and no output. English captions are auto-generated, so key names (J K L, F9) were checked against the on-screen frames only where visible. Audio and music not assessed.
