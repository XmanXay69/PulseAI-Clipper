# How To Edit Super Smooth Transitions in Premiere Pro! — Finzar (9:56) — https://www.youtube.com/watch?v=eEVxr6lzQSc
Genre this speaks to: gaming video (gaming-channel transitions) with a general/cinematic "smooth" angle
Usable?: partly. Real Premiere settings (frame lengths, shutter angle, velocity easing, where to place the cut), but it is a preset-pack tutorial and about 2 minutes of it is a Hostinger sponsor sketch.
Evidence available: captions yes (auto, en); frames 50 (all viewed) plus 13 zoomed stills from the local video; downloaded yes (1280x720 h264)

## Rules stated
- Build the transition on an adjustment layer set to the same frame rate as the sequence (check Sequence > Sequence Settings). He says most viewers are at 60 fps; at 24 or 25 fps you must stretch the effect out a little because there are fewer frames [said 01:30-01:56].
- Length of the transition: drag the adjustment layer to about 12 frames. At 60 fps that is 0.2 s [said 01:56; the duration readout in the frame says 00:00:00:12, seen 02:05]. To make a transition quicker, shorten the adjustment layer; it is "completely up to you" [said 06:14].
- Stack: two adjustment layers side by side on the lower layer (one over each clip), alt-drag a copy upward and stretch it over both; put the "main preset" on the two bottom layers and any of the style presets on the top layer. If it looks wrong, undo and try another on top [said 02:08-02:33].
- Zoom in / zoom out presets: for zoom in, disable the first main preset (Shift+E); for zoom out, disable the last main preset [said 02:33-02:45].
- Premiere's own whip transition (Video Transitions bin) adds motion blur but, in his words, looks like a slideshow [said 02:58-03:10].
- Main takeaway for any transition: put the cut under the moment the screen is most covered (the white flash filling the frame for a glitch; the smoke/fire plume for a green-screen element). A white-flash one doubles as a "dip to white" [said 06:14-06:39, 07:16-07:28].
- Glitch transitions: use pre-keyed stock or free green-screen assets (Production Crate, YouTube green-screen packs, Cinecom preset pack), drag onto the adjustment-layer position and nothing else needs doing. He says he rarely uses glitch transitions these days [said 05:25-06:02].
- Green-screen element transition: scale it to the project size, apply Ultra Key, eyedropper the green, set key mode to "aggressive" for a cleaner edge, then change speed/duration to 200 percent because it was a little too slow [said 07:04-07:16].
- Transform slide-up transition (the kind he says is all over his channel): clip B on the layer above clip A and pulled out so it covers the top of A; add the Transform effect (Distort); keyframe Position at the start and another "a few frames ahead" (exact number not given); drag the first keyframe down so clip B starts just off-screen; open the keyframe's velocity graph and drag the start handle out to the right so the move eases in; set shutter angle to 360 for motion blur [said 08:04-08:30].
- Staggered variant: alt-drag the clip up four times, stagger each copy, put Color Balance (HLS) on the bottom three with different values for a coloured cascade [said 08:30-08:48]. The same effect can be copy-pasted onto a PNG or JPG [said 08:55-09:08].
- He does not say anything explicit about "smooth" as a principle beyond the title and the preset names; no numbers on zoom speed or on easing amounts [absent].

## What the editor's own timeline and effects show
- Sequence: 60 fps footage (A004 ... .braw), a 60.00 fps clip in the project bin; green-screen assets are 30.00 fps [seen 08:59 project panel]. Timeline ruler labels step by 15 frames, consistent with a 60 fps timebase [seen 08:43, ruler 00:13:46:00, :15, :30, :45].
- Adjustment layers are magenta bars. At 02:09 two adjacent layers sit on one row over the cut; at 02:22 a third, wider one sits above both [seen 02:09, 02:22]. The tooltip reads "Duration: 00:00:00:12" on a layer [seen 02:05]; no ruler is readable in those crops.
- Transform effect panel: Position stopwatch on, Anchor 2048.0 / 1080.0, Position 2048.0 / 1415.0 on a keyframe, Scale 100.0, Rotation 0.0, Opacity 100.0 [seen 08:07-08:19]. "Use Composition's Shutter Angle" is ticked with Shutter Angle 360.00 and Sampling "Bilinear" [seen 08:25]. The velocity graph readout shows 11838.3 at the top, 0.0 at the bottom, with a gently rising curve whose start handle is dragged level to the right: the move begins at zero speed [seen 08:28].
- Staggered clips: four copies of the same clip on four video tracks, each starting a little later, equal-looking steps (steps not readable against the ruler) [seen 08:48].
- Effect list names a "Smooth Whip" set (bottom-left to top-right, top-left to bottom-right, etc.) and "Smooth Zoom IN" / "Smooth Zoom OUT" [seen 02:41]. Keyframe numbers for those presets are not shown.
- A kaleidoscope-like mirrored image appears when only the main preset is applied ("looks weird" until the top layer is added) [seen 02:24].
- Sequence preview shows a 4K-class clip (centre 2048 x 1080) in a smaller program monitor; the sequence resolution itself is not read.

## How the video itself is edited
- Cut rate, 0-180 s: 46 cuts = 15.3 cuts/min, mean shot 3.8 s [measured]. Contents: black "this video is sponsored by" card, a teaser montage of transitions (13 cuts in the first 40 s = 19.5/min), talking head, then Premiere screen recording with zoomed-in crops of the UI.
- Cut rate, 200-380 s: 71 cuts = 23.7 cuts/min, mean shot 2.5 s [measured]. Contents: the live-action Hostinger sponsor sketch (dialogue cutting) followed by the start of the glitch section. This is a comedy sketch's cut rate, not a tutorial pacing figure.
- Cut rate, 340-520 s: 34 cuts = 11.3 cuts/min [measured]. Almost all Premiere screen recording; the "cuts" are mostly crops and transition demos, so it says little about his pacing.
- Hook: no real cold open. A black card "this video is sponsored by:" is the first frame; at 00:10-00:13 a teaser of three transitions plays (smoke explosion, two green glitch blocks), and the promise ("do you want to do transitions like this") is spoken in the first 17 s [seen 00:10-00:13, heard 00:00-00:17]. Hook about 10-17 s.
- Sponsor: Hostinger, announced at 00:00 and again at 09:20; the sketch runs about 03:23-05:25 (about 2 min, 20 percent of the video), with a "HOSTINGER" logo burned top-left at 05:02-05:09 [seen/heard].
- Captions: only in talking-head parts; white, bold, mixed case, 1-3 words ("you're gonna") low centre of frame with a soft shadow [seen 00:27]. The tutorial parts are uncaptioned (estimated: captioned for under 10 percent of speech).
- Zooms: the screen recording is punched in on the part of the interface he is talking about, then back out (many frames are 2-3x crops); whether the zoom is eased or snapped cannot be told from stills [seen 01:56, 02:05].
- Pop-up text: a "BONUS TIP!" card with a spinning body-cam shot at 02:55 and "DURATION THINGY" quote text over the zoomed timeline at 02:05 [seen]. One graphic every minute or so, not dense.
- Transitions used between his own scenes: glitch blocks and smoke wipe on the same effects he teaches (the video eats its own examples) [seen 00:12, 02:56, 05:37-05:57].
- Music and SFX: caption [Music] markers across the teaser (00:03-00:17), sketch gaps (03:10-03:23, 05:12-05:25) and outro (09:32+); levels not measured and SFX under the transition demos not checked.
- Outro: end card "sub for more finzar" on a night-field background, ~9:43 [seen].

## Against today's playbook
- smooth.zoomRamp 0.6 s and "glidingRamp 0.4 s": his transitions are 12 frames = 0.2 s at 60 fps [said 01:56], and he shortens them further if wanted [said 06:14]. So his "smooth" is not slow; it is eased velocity (zero start speed, handle dragged out) plus motion blur at shutter angle 360. Transitions and punch-ins differ in the playbook; the ramp number for punch-ins is unsupported here either way.
- smooth principle "Shape the speed of every move": confirmed with a concrete method (velocity handle dragged out to start at zero speed, shutter angle 360) [said 08:17-08:30, seen 08:28].
- smooth principle "transitions never start abruptly" and "nothing snaps": not stated as such, but his rule that the cut sits under the peak of coverage is the mechanism that keeps a transition from showing a seam [said 06:14-06:39].
- Premiere's default whip is called a slideshow even though it has motion blur: blur alone is not smoothness; the curve is [said 02:58].
- retention.fadesPerMinute / popups: no support or disagreement; this is a transition demo, so the transitions in his own cut are not a fingerprint.
- "Dip to white" as a join: a white-flash transition is cited as good for blending [said 06:27-06:39]. The playbook only lists fades; candidate addition for the retention/smooth transitions.

## Caveats
- Auto captions only; "[heard]" tags mean read from caption timing (audio not listened to). The preset pack is a free download he links, so the exact keyframe values inside "Smooth Whip" and "Smooth Zoom" presets are not shown.
- The "a few frames ahead" keyframe distance is not a number. 12 frames is the only transition length he states, and it is for adjustment-layer presets at 60 fps.
- Sponsored (Hostinger); the sketch has no editing craft.
- Premiere, 60 fps, gaming-channel taste; the 24-30 fps advice is only "stretch it a little".
