# The Secret To Editing Professional Videos in 2026 — Finzar (8:35) — https://www.youtube.com/watch?v=RutTgrCATwk
Genre this speaks to: general (applies to gaming, vlogs, corporate; shown on a gaming-style PNG animation) and the smooth/cinematic style
Usable?: yes. This is a lesson in smoothness itself: the whole video is the thesis that gradual starts and stops (easing and the velocity graph) are what makes an edit look professional. Last ~1.5 minutes are self-promotion of his preset shop.
Evidence available: captions yes (auto, en); frames 46 (all viewed) plus 22 larger stills from the local video; downloaded yes (1280x720, 30 fps)

Is this the "Real Secret to PRO Level Editing" video from the newsletter? Almost certainly this one, or the same lesson under another title. The newsletter title is not in the page data I could see, so I could not check the title text. The content matches the description point for point: the whole video is "the secret is smoothness" [said 00:15-00:42]; transitions with a smooth start and end [said 01:32]; objects arriving with a smooth start, a quick middle and a soft finish [said 01:32-01:46]; a harsh start or ending is what makes viewers unhappy [said 01:08-01:32]; moves shaped on the velocity (speed) graph [said 04:04-04:30]. It does not teach "zooms don't jolt" explicitly: zoom is never mentioned, only that ease in/out applies to scale, rotation, position and blur [said 03:26-03:52].

## Rules stated
- Thesis: it is not effects, not hundreds of cuts and not the software; the secret to good editing is "smoothness" [said 00:00-00:36].
- Car analogy: an edit should start gradually, reach full speed, then come to a gradual stop; a harsh start and a harsh stop (slamming the brake) leave viewers unhappy, so it matters on every edit [said 00:42-01:32]. The same goes for a transition with a smooth start and end, or an object entering with a smooth start, "a little bit of a fast middle" and a smooth slide out [said 01:32-01:46]. Smooth is what makes computer-made motion feel natural and professional [said 01:46, 06:37].
- Keyframes are the starting concept for almost every route to smoothness, in corporate videos as in YouTube [said 01:59-02:25].
- Default keyframe motion is interpolated at a steady pace; his example is a rotation going 0 to 180 over a few frames. He likens it to a car stuck at 20 mph with no smooth take-off or landing [said 02:25-03:02].
- Fix: right-click the first set of keyframes and set Ease Out (adds a smooth start), the second set Ease In (adds a smooth end). "Out then in, not the other way around." Works in Premiere and DaVinci Resolve [said 03:02-03:26].
- Ease out/in applies to any value: rotation, scale, position, even a keyframed gradual blur [said 03:26-03:52].
- Next level, the velocity graph: open the dropdown by the keyframes; grab the handle on the first keyframe and drag it out, in, up or down. Experiment until it looks smooth [said 04:04-04:30].
- His "super smooth" recipe: pull the first keyframe's handle out a little; pull the second keyframe's handle all the way back. The resulting hill sits near the start: most of the speed happens early, then a long, slow deceleration down to the end point [said 04:42-05:09].
- Motion blur: apply the keyframes on the Transform effect and set shutter speed (Shutter Angle) to 180 or 360 [said 05:09-05:23].
- Bounce: shape the velocity graph with the speed concentrated at the end, then keyframe the anchor point to wobble on that spike: left, right, left, then back to the landing point. Works for bouncing up and down, diagonally and in rotation [said 05:23-05:48].
- Presets save hours: do the keyframes once, save as a preset and drag it onto layers; he sells handmade ones focused on smoothness [said 05:48-06:25]. Saving is done by right-clicking the effect, Save Preset [seen 06:18].
- Everyday inspiration: a scroll that coasts to a stop is keyframed by developers, not natural physics [said 06:37-07:03].
- Cuts too: even smooth cuts should be unnoticed. The gold standard is that viewers do not think about the editing [said 07:03-07:31].
- No numbers for ease percentages, influence, zoom scale or ramp length are given. The only numbers are 180 or 360 for shutter angle and the 0-180 rotation demo.

## What the editor's own timeline and effects show
- Premiere keyframe/velocity graph on an Adjustment Layer (a purple bar), Position animated; the value axis spans 0.0 to 3840.0 (a 4K-wide sequence), keyframe pair about 1.9 to 2.0 s apart on a ruler labelled each second (00:03:51:00 to 00:03:55:00) [seen 04:18-04:48, estimated from label spacing about 180 px per second].
- Linear: the velocity graph is a flat-topped rectangle (constant speed, "Velocity: 2110.3 / second"), stepping up and down abruptly at each keyframe [seen 04:18].
- Handle on first keyframe dragged right: speed rises gradually from 0.0 to a peak near the end, then drops sharply at the unsoftened second keyframe [seen 04:32]. Short handle pulled out: speed rises quickly, then plateaus before the drop [seen 04:48].
- Both handles set: a "hill" peaking just after the first keyframe at about 8446.7 (per second) then a long slow slope to 0.0 at the end keyframe; a red arrow overlay marks the hill [seen 04:58].
- Bounce curve: speed climbs slowly through the move and spikes at the very end (readouts 9361.2 and 12326.8), with three anchor-point keyframes bunched at the end [seen 05:30-05:38].
- A garage illustration draws the same velocity curve over a car for the metaphor [seen 05:08].
- Effect Controls: "Transform (Transform (Motion Blur))" with Anchor Point 1920.0 / 1080.0 and Position 6000.0 / 1080.0, Scale 100.0 uniform [seen 05:20, extra frame at 320 s]; a saved preset named "Transform (Smooth Bounce 2 UP)", Position 960.0 / 540.0 [seen 06:18].
- Right-click menu on a keyframe lists Linear, Bezier, Auto Bezier, Continuous Bezier, Hold, Ease In, Ease Out; the interpolation ticks Linear by default; Ease Out is picked on the first keyframes then Ease In on the second ones; eased keyframes show an hourglass icon, linear ones a diamond [seen 03:08, 03:20, 03:22, 03:26, 03:30].
- Rotation graph with readouts 180, 196 and 219 degrees, "Velocity: 167.5 / second" and "145.9 / second", showing two similar-shaped curves for the two properties [seen 03:08-03:30].
- Store page of his preset packs (Ultimate Essentials, Animation, Camera Shake, Transitions, Subtitle, Zoom Presets, Like & Sub CTA) [seen 06:31-06:53]; not craft.
- He never shows the main sequence timeline with clips. Only the keyframe lanes and effect controls.

## How the video itself is edited
- Cut rate, 0-180 s: 26 hard cuts = 8.7 cuts/min, mean shot 6.7 s [measured]. Contents: a sword-fight cold open (0-29 s, 9 cuts in 30 s = 18/min incl. a fast flurry at 00:13-00:14), then the car analogy (pedal, braking, road shots, a thumbs-up from the driver) and the presenter at a desk. 30-180 s alone: 17 cuts = 6.8 cuts/min [measured].
- Cut rate, 200-380 s: 4 hard cuts = 1.3 cuts/min [measured]. Contents: macro screen recording of Premiere keyframes shown with slow eased pans and zooms on a CRT-style monitor, red hand-drawn arrows and circles, and a talking-head interlude. Not a pacing figure: it is one continuous camera move over a recording.
- 380-510 s: 1 hard cut at the 0.35 threshold and 4 soft changes at 0.1 [measured]. Contents: a store page tour then the presenter in a field in long takes (25-65 s) joined by slow dissolves; a double-exposure dissolve is visible at about 07:25 [seen 07:25].
- Hook: sword fight with a knight over a narration beginning at 00:00 ("for hundreds of years editors have searched for the secret"); the question "does it mean fancy effects, hundreds of cuts, the software?" is posed by 00:29 and answered "smoothness" at 00:29-00:36 [heard]. The promise is on screen/voice by about 00:05-00:12 and the answer is at about 00:30.
- Illustration timing: the car metaphor is cut to the narration (foot on accelerator, on the brake, road, driver) with 8 scene-change frames in 13 s at 00:57-01:10 [seen 00:57-01:10, estimated from the frame list].
- Graphics: animated keyframe diamonds (a row of eight with a bracket at 02:52), a large "ROTATION: 180" in grey with the number blurring in green at 02:40, a spinning orange-badge avatar with eased rotation at 03:30, red arrows and a hand-drawn red ellipse on the handle being dragged [seen 02:28-03:30, 04:48-05:30]. New graphic roughly every 5-15 s in the lesson section (estimated, not counted).
- Captions: none for speech (estimated 0 percent captioned). Text appears only as demo graphics.
- Transitions: horizontal motion-blur whip at about 03:57 (two blurred frames in the same second), a streak/glitch transition at about 05:05 [seen 03:57, 05:05]; a slow dissolve in the closing field section [seen 07:25]. Between demo shots he uses hard cuts.
- Music and SFX: caption [Music] markers at about 01:46, 03:38, 03:52, 08:19; level not measured and the audio was not listened to.
- Promo: presets pitch at about 05:48-06:25 (about 40 s) and a "course from beginner to pro" plug at 07:31-07:56 (about 25 s); together about 65 s = 13 percent of the video. No third-party sponsor.

## Against today's playbook
- smooth tagline "Every move eases and nothing snaps" and principle "Smoothness is the secret": confirmed in the creator's own words [said 00:29, 01:08-01:32].
- smooth principle "Shape the speed of every move" (a move that starts slow, travels and settles): confirmed, with a more specific shape. His preferred curve is not a symmetric ease-in-out: a short ease-out at the start (quick accelerate), most of the speed early, then a long slow decelerating tail to the endpoint [said 04:42-05:09; seen 04:58]. A symmetric S-curve would read as "starts slow"; he asks for a quick start and a long settle. The playbook sentence "starts slow" is partly at odds with this for element entrances.
- smooth principle "transitions never start abruptly": confirmed, explicitly for transitions and for entering/exiting objects, with exits mirroring entrances [said 01:32-01:46; also video 03 at 08:44].
- Interpolation rule new to the playbook: first keyframes ease out, second ease in; ease on every animated value including blur, scale and rotation [said 03:02-03:52].
- Motion blur: shutter angle 180 or 360 [said 05:09-05:23]; the playbook has no motion-blur setting. Video 02 also sets 360 on the slide-up transition [seen 02 08:25] and video 03 shows 360 on the intro animation [seen 03 07:29].
- smooth.zoomRamp 0.6 s: no zoom or ramp length given. His demonstration move is about 1.9-2.0 s [seen 04:18-04:58, estimated from ruler]; so it does not contradict a 0.6 s punch-in, but his figure is for a bigger slide, not a punch-in. A "snap" ramp is exactly what he says to avoid.
- commentary principle "Hide the join": matched by "cuts should not be noticed; the gold standard is that nobody thinks about the editing" [said 07:03-07:31].
- smooth.maxStaticStretch 20 s and cutsPerMinute 6: his own video's calm closing section holds 25-65 s with only dissolves [measured]; the cold open runs 18 cuts/min, the explanation 7-9 cuts/min, close to the playbook's 6.
- smooth.hookDeadline 12 s: his promise (the "secret") is voiced at 00:00 and the answer comes at about 00:30 [heard]. Consistent for the promise, later for the payoff.
- retention/other styles: nothing here contradicts them; this video is orthogonal (how a move is shaped, not how often).

## Caveats
- Auto captions; "[heard]" tags mean read from caption timing (audio not listened to); the shop name is garbled in captions (a preset store). The newsletter title could not be checked, only the content match. Page metadata (views, description) was not captured.
- The velocity peaks (8446.7, 12326.8) depend on the 4K-wide demo distance and are not rules; only the shapes matter. The frame ruler reading (about 1.9 s) is my estimate from label spacing.
- He sells smoothness presets, so there is a commercial interest in the "smoothness is the secret" framing. The advice is still standard motion-design craft (ease, velocity, motion blur).
- One creator's taste; Premiere/DaVinci specific names (Ease Out/In, Shutter Angle).
