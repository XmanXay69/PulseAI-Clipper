# Storezar: How to Edit The BEST Sound Effects For Beginners — Storezar (Finzar's shop) (3:07, views not shown) — https://www.youtube.com/watch?v=L4da128D6Xc
Genre this speaks to: general (motion-graphic and tutorial videos; he says his videos usually have voiceover, so it carries over to voiced gaming commentary)
Usable?: yes, with a discount. It is the best numeric source of the four (dB offsets per effect role), but the whole demo is built on his own "Whooshes and Risers" pack and ends with a shop pitch.
Evidence available: captions yes (the report's own track was an Arabic auto-translation; I fetched the English auto-caption track `en-orig` with yt-dlp and read that in full; dB figures agree in both); frames 10 (all viewed) plus 6 extra 1280px frames, all read closely; downloaded yes.

## Rules stated
- Sync rule: drag the whoosh so the spike of its waveform sits on the moment of most motion in the animation; "that's where the sound naturally wants to be spiking" [said 00:28 to 00:42].
- Volume for a fast whoosh from his pack: lower by "-16 decibels", "that seems to sound best". In Premiere select the clip and press G (Audio Gain); in DaVinci Resolve drag the volume line down on the clip [said 00:44 to 00:58, 01:00].
- Transition whooshes: centre the spike "right in the middle of that transition" (the cut or dissolve point), and set them to "-12 decibels". Reason: he likes transitions "a little bit louder than the other whooshes", i.e. transition whooshes sit 4 dB hotter than the motion ones [said 01:03 to 01:25].
- Deep whoosh under a background change: set it about "-16" before even playing it back, because there is usually voiceover and the effects must not get in the way of it. Reducing volume is "second nature" [said 01:29 to 01:48].
- Longer animations: use Speed/Duration to slow the same sound so it spans more of the motion (he gives the 'box spin' as the example); slower means a longer clip [said 01:50 to 02:04].
- To shorten an effect, drag a cross dissolve onto its end to get a "clean end" to the sound [said 02:07 to 02:12].
- Text that slides up, pops and stretches: use a different effect for each word or line that appears; "variation sounds better" [said 02:16 to 02:27].
- Align each text effect's waveform peak with the fastest point of that piece of motion [said 02:27 to 02:32].
- Set gain on all the text effects at once: select every clip under the text and adjust together [said 02:33 to 02:37].
- Shortcuts he names: G for gain in Premiere (said 00:44), drag-handle volume line in Resolve (00:55).
- Not stated: no effects-per-minute figure, no meme rule, no music level or ducking, no "never" rule; the only rule that comes close is "keep effects out of the voiceover's way" [said 01:41].

## What the editor's own timeline and effects show
- Premiere layout: source monitor with the green waveform of the effect, program monitor, project panel listing "S2 Whooshes & Risers Pack" with sub-folders 1 High Chops, 2 High Whoosh, 3 Fast Whoosh, 4 Standard Whoosh, 5 Medium Whoosh, and the readout "1 of 69 items selected" [seen 02:22, 02:12].
- Effect clip lengths in the project panel: the Media Duration column prints High Chop files as 00;00;00;13 to 00;00;01;14 (13 frames to 1 s 14 f) and Medium Whoosh files as roughly 00;00;01;29 to 00;00;04;29 (about 2 to 5 s), so hits are about half a second to 1.5 s and whooshes 2 to 5 s [seen 02:22, 02:12; read at 1280 px].
- The demo timeline is tiny: 2 visual layers (a "hand pointing up" PNG plus "blank wall background" at the start, "SFX V2.mov", "Matrix Raining Code.mp4" and "sunny blue sky.jpg" later) and SFX on A1 to A3. In the 02:38 frame there are about 4 to 5 effect clips across roughly 3 s of the sequence, on separate tracks, which is a dense moment (estimate from clip widths) [seen 00:29, 00:52, 02:38].
- The whoosh at 00:52 is a clip about 1 s wide centred under the fin bounce; the audio overlays the start of the animation rather than trailing it [seen 00:52].
- Right-click menu on a clip lists Speed/Duration, Audio Gain, "Show Clip Keyframes" [seen 01:52]. The Audio Gain dialog is open at "Adjust Gain by" (relative gain, not set/normalize) [seen 02:38]; the numeric value typed is not legible.
- Audio meter on the right of the program panel is empty in nearly every frame; there is no level reading on screen.

## How the video itself is edited
- Cut rate [measured]: this is a 3-minute screen recording of Premiere/DaVinci with voice-over, so the picture is almost a single shot. 0:00 to 1:30 = 3 cuts (2.0/min); 1:30 to 3:06 = 1 cut (0.6/min). These numbers describe screen recording, not pacing.
- Loudness [measured, ffmpeg ebur128]: integrated -21.9 LUFS, loudness range 3.2 LU (voice only, effects played back briefly).
- Hook: no hook. Plain "welcome to this tutorial" at 0:00 over a grey Storezar-logo tile pattern, promise ("most efficient and effective way") by 0:06; first demo at 0:14 [seen 00:00, heard 00:00 to 00:13].
- Captions: none burned into the video; text on screen is only what is inside the demo animation ("...ever!" over a boxed pack, 02:13 to 02:38).
- Promotion: heavy. The pack is used for every sound he demonstrates, the demo motion graphic itself is an advert for the "Whooshes & Risers" pack box (sun and sky background, "ever!" text) at about 02:13 to 02:38, and the voice-over pitches storezar.com (presets, courses, "sound effects") at 02:41 to 03:02; the site page (Video Editing Presets bundles, prices) is on screen at about 02:48. That is about 21 s of 186 s (11 percent) explicit pitch, and the whole tutorial is by construction a demo of the product.
- Music: none audible under the voiceover from caption evidence; a closing demo of the animation with its effects plays at 02:40 to 02:46 ("this is what it all sounds like").

## Against today's playbook
- retention "Sound sells the hit" and sound design: this gives the first real levels: motion whooshes about -16 dB, transition whooshes about -12 dB, deep whooshes about -16 dB relative to the pack's own full-scale loudness. The auto-editor should place transition whooshes about 4 dB louder than other whooshes, and keep all of them well under voice [said 00:44, 01:19, 01:40].
- Alignment: his sync rule is peak-on-the-fastest-motion, which means effect start = event time minus the whoosh's lead-in (the sound's waveform peak, not its first sample) [said 00:28 to 00:42; seen 00:52].
- Variation: different effect for each repeated text pop; the playbook has no "do not repeat the same sound back to back" rule and should [said 02:19].
- Effect ends: a short dissolve at the tail (cross dissolve) is the clean-end method; this supports a short audio fade-out on every effect [said 02:07].
- effectsPerMinute 4 / maxEffectsPerMinute 8: unconfirmed. His 2:38 frame shows about 4 to 5 sound clips within roughly 3 s of a motion-graphic piece, an effects-dense pattern for animations; this is a showcase, not a gaming timeline.

## Caveats
- Product demo. The -16 / -12 dB values are "for this pack in particular" and depend on how hot the pack is mastered; they are offsets from that file, not absolute loudness.
- English captions are YouTube auto captions; I read them via a separate caption track because the pre-selected one was Arabic.
- The final level of any clip depends on the voiceover, which is not shown.
- Audio gain value typed at 02:38 not legible; no meter readings.
- Single creator, not a gaming edit: the project is motion-graphic animations, so per-minute density cannot be inferred.
