# How To Edit Your Twitch Streams Into YouTube Videos — Senpai (10:00, 224,410 views) — https://www.youtube.com/watch?v=5RuoLQWvDu8
Genre this speaks to: shorts (Twitch clips -> Shorts/TikTok). The title says "YouTube videos" but the content is about vertical/short clips, NOT long highlight videos. PULSE should treat it as `short` (punchyShort), not `streamHighlights`.
Usable?: partly. About a minute of real craft: a text-reveal technique and a zoom-keyframe demo; the rest is channel-growth advice and a stream-capture tip. Almost no numbers.
Evidence available: captions yes (auto, en, 655 segments); frames 45 read (all) + 5 extra 1024px frames (224, 410, 432, 451, 467 s); downloaded yes (1280x640).

## Rules stated
- Growth on Twitch needs content on more discoverable platforms (YouTube, TikTok, Instagram, Twitter) that you funnel back to the stream [said 00:00].
- "Flashback recording": a capture-card button that retroactively records the last moment, so a good answer or play is saved at full quality without searching a VOD later. His setup: vertical camera into an HD60 Pro, Elgato 4K Capture Utility running behind OBS, camera captured in 1080p the whole stream [said 01:02-01:44]. Avermedia cards do it too; for gameplay use OBS replay buffer or a third-party tool; capture camera and gameplay separately, combine in edit [said 02:06-02:27].
- Claims this approach produced "over a million views a month" on a brand new channel over a couple of months [said 01:02] (his analytics screen, seen at 01:06, reads 1.2 M views, 22.8 K watch hours, +5.4 K subs over 28 days).
- Free editors (iMovie, DaVinci Resolve) are enough; the demo editor, Scott, uses Final Cut Pro [said 03:08].
- Tip 2: watch the whole clip first; it tells you the pacing and what to cut [said 03:28]. Then cut the silent "fluff" at the start of the clip (his example clip opens with dead air) [said 04:09].
- Tip 3, subtitles: use them to hold attention and for comedic effect [said 04:30]. Make a text layer (Ctrl+T in Final Cut), font Avenir Next, red outline, outline width 3 [said 04:50-05:11]. Subtitle exactly what is said (typed by hand, no auto-caption mentioned) [said 05:11].
- Reveal words as they are spoken: crop the text layer so only the first word shows, then drag the crop edge out at the moment the next word is said ("spam" then "buttons") [said 05:52-06:12].
- Tip 4, keyframed zoom to emphasise a reaction or an in-game moment: blade just before the reaction, set position and scale keyframes at the start, move forward, scale in and reposition, set the end keyframes [said 06:32-07:13].
- If the zoom feels long, select the clip and paste/move the two keyframes "a couple frames" earlier so it is faster; he judges the faster version better [said 07:38-07:59]. No frame count or second value is given.
- Tip 5: plan the live stream around what will make good short content; steer conversation toward topics that cut well. Names Ludwig as someone who uploads a YouTube video "like every single day", nearly all planned live content [said 09:01-09:21].

## What the editor's own timeline and effects show
- Final Cut Pro project is 1080p HD 59.94p, Stereo, i.e. landscape 16:9, not vertical [seen 07:12, viewer header]. The example is a PUBG clip with the streamer's circular-corner facecam and minimap baked into the gameplay capture [seen 03:54-04:04].
- Timeline is minimal: one video clip with its audio lane under it, one connected lane of purple title clips above; after the blade there are 2 clips [seen 07:31 frame at 451 s, 1024 px]. Three subtitle blocks on the title lane: "I DONT KNOW HOW TO DO IT", "SPAM B... / SPAM BUTTONS" (two blocks because of the word reveal), "FOUND IT...". By eye the first block is about the width of the first clip, the others about a third of that, so each subtitle is on screen about as long as the line is spoken.
- Zoom keyframes: Position and Scale (All) have diamonds on both. Start value Scale 100 % [seen 07:31 at 451 s], end value Scale (All) 174 %, Scale X/Y 174.0 %, position X about -223 px [seen 07:12, 432 s frame]. I could not read the ruler labels, so I cannot give the zoom's duration in seconds; at the blade it spans the right-hand clip start to roughly where the playhead sits (about 16 frames apart between 8:11 and 8:27 on the viewer timecode, [seen 07:12 and 07:31], which is only the playhead gap, not the ramp).
- Subtitle look: bold uppercase white sans with thick red outline, centred low in the frame (about 80 % down in the playback view at 08:09) [seen 08:09].
- No audio waveform work, no SFX lane, no music lane, no colour work are shown [seen 03:28-08:09].

## How the video itself is edited
- Cut rate [measured]: 30-210 s: 7 hard cuts = 2.3 per minute, mean shot 22.5 s. That stretch is talking head with b-roll inserts (HD60 Pro product shot, YouTube analytics screenshot, a daily-views table) and 2-3 whip/blur transitions that ffmpeg scene > 0.35 only partly counts. 300-480 s: 3 cuts = 1.0 per minute; that stretch is a screen recording of Final Cut with a facecam inset, so the number says nothing about his pacing.
- Hook: cold open on a talking head, no logo; the argument "you have to make content elsewhere" at 0:00, the promise "five tips" at about 0:21-0:42 [heard 00:21-00:42; caption text]. First real content tip (flashback recording) arrives at 01:02.
- Transitions: whip-pan / blur transitions into inserts and into Scott's segment (frames at 01:51-01:56, 02:53, 08:33) [seen]. A second presenter segment (Scott) runs 02:48-08:18 as a screen recording with a facecam inset in a rounded rectangle at the lower right [seen 04:04+].
- Pop-ups: 4-5 b-roll or screenshot inserts in the first 2.5 minutes (estimated, about 1 per 30-40 s). A cut-in clip of a streamer reacting (chocolate fountain, Twitch chat visible) at 09:08 [seen 09:08].
- Captions on the tutorial itself: none that I could see on the talking head frames [seen]; on-screen text only in the demos.
- Music and SFX: I cannot hear the audio; the captions carry no music tags. Not assessed.
- Outro: end-screen layout with the video shrunk onto a white card with a faint logo, from 09:35 [seen 09:35-09:50]. No sponsor segment; the only promo is a joking ask to follow his stream (00:42) and links to two streams at 09:41.

## Against today's playbook
- `short` (punchyShort): his zoom is a 100 % to 174 % punch at a reaction and he wants it quicker; the playbook's zoomScale 1.2 / zoomRamp 0.12 is consistent in spirit (fast) but 174 % is a demo value, far above 1.2 [seen 07:12]. Do not read it as a target.
- `short` captions: playbook says mixed case, positionY 0.68, 2 words on screen. He uses uppercase with a red outline, low in frame (about 0.8), and reveals word by word with a crop [seen 08:09, said 05:52]. One creator's taste; supports "word-by-word reveal", contradicts "mixed case" and the 0.68 position.
- `short` hook: playbook says 2 s hookDeadline. His clip example is shown with silence at the start trimmed [said 04:09], which supports "start where the speech starts".
- `streamHighlights`: nothing here supports a number for long highlight videos; do not use this video for that playbook. His only highlights-adjacent claim is planning the stream for later editing (Ludwig) [said 09:01].

## Caveats
Not about long highlights videos despite the title. The editing demo is a junior editor in Final Cut with manual subtitling; no number for zoom duration, ramp, or caption length is given. The "1 million views a month" and analytics are self-reported. Audio not assessed. Auto-captions only, so product names are approximate.
