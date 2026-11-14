# PULSE: 800 more ways to make it better

A second working list, written against what the app does at 1.7.0. Items are numbered 501 to 1300 so they
continue [the first 500](ROADMAP-500.md) and can be referred to the same way ("do 541, 626, 905").
Nothing here repeats an item from the first list or a feature that has shipped. Grouped by area; inside each
group, roughly in the order a streamer would feel them. ★ marks the ones most likely to change results
for the least work.

## Where to start

If only twenty get built, these are the ones. Built so far (see the [1.8.0 notes](../versions/1.8.0/NOTES.md)): 626, 627, 541, 542, 721, 581, 582, 521, 501, 936, 937, 761, 1101, 661, 1061, 906, 1181, 1281, 1021 and 866 (866 as far as it can go without an Apple Developer account: see [SIGNING.md](SIGNING.md)). That is all twenty.

| # | What | Why first |
|---|---|---|
| 626 | A built-in editing style as the default for each kind of recording | The styles exist; one switch makes every edit use them |
| 627 | Build one VOD in two styles and compare | Shows which style suits a channel instead of guessing |
| 541 | Loop builder for shorts | Replays are the cheapest watch time there is |
| 542 | Hook rewriter with five on-screen openers | The first two seconds decide most of a short's reach |
| 581 | Narrative arc builder | Turns a highlight reel into a video people finish |
| 582 | Open loops that point at a real later moment | The strongest mid-video retention device, and checkable |
| 501 | Facecam emotion as a signal | Finds reactions the microphone misses |
| 521 | Copyrighted-music detection before export | One claim can cost a video its revenue |
| 936 | YouTube retention graph import per video | Lets the coach learn from what actually happened |
| 937 | Coach calibration from the retention graph, per second | Replaces rules of thumb with this channel's audience |
| 866 | Developer ID signing and notarization | Removes the first-launch warning every new user hits |
| 1021 | A real frame in CI screenshots | Catches viewer regressions the screenshots cannot see today |
| 761 | Dialogue-first mix assistant | Bad audio loses more viewers than bad cuts |
| 721 | Caption pages split at reading speed | Readable captions without hand-fixing |
| 661 | Trim while it loops | The single biggest speed-up for hand editing |
| 1101 | A command to rebuild only what changed | Makes "try it another way" cost seconds |
| 1181 | Review link with timecoded comments back into the timeline | Closes the loop with an editor or a friend |
| 1061 | First-run on your own footage in under two minutes | The sample project proves the app, not the user's stream |
| 906 | Posting plan across platforms | Editing is half the job; shipping on schedule is the other half |
| 1281 | A language model that plans the edit | The editors follow rules today; a planner that reads the whole transcript can find the story |

## A. Finding the moments (501–540)

501. ★ Read emotion from the facecam (smile, wide eyes, open mouth from Vision landmarks) and use it as a reaction signal beside the audio.
502. Clutch detection for shooters: low health on the HUD followed by a win within 30 s.
503. Multi-kill grouping: kills within 10 s join into one moment with a count the pop-up can use ("TRIPLE").
504. Funny-fail versus sad-fail: a death screen followed by laughter scores as comedy, by silence as a low point.
505. Jump-scare signature for horror: a brightness jump, an audio spike and a scream inside 400 ms.
506. Comeback detection from scoreboard text: a deficit that flips.
507. Chat mood, not only chat volume: tell "LMAO" bursts from "???" confusion and "F" sympathy, and tag the moment with it.
508. An emote map per channel: which 7TV, BTTV and channel emotes mean funny, hype or sad.
509. Sub, raid and donation alerts found by their sound or overlay, as event markers you can include or skip.
510. Text-to-speech donation messages detected and tagged; they are often the funniest thirty seconds of a stream.
511. Detect the streamer reading chat aloud and link the line to the chat message that prompted it.
512. Topic segmentation of the transcript, so sections get names without a cloud model.
513. Names, games and places mentioned are indexed, searchable and offered as tags.
514. Question and answer pairing on Q&A streams, so each answer becomes a self-contained clip with its question.
515. Storytime detection: one voice for a minute or more with past-tense narration.
516. Running-joke detection: a phrase said three or more times across the stream, offered as an "every time" supercut.
517. Catchphrase learning: the words this streamer says at big moments are weighted for this channel.
518. Tension then release: a quiet second or two before a spike scores above the spike alone.
519. Laughter length and spread: several voices laughing, or a long wheeze, outranks a chuckle.
520. Squad chaos counted as energy: everyone shouting at once is a highlight, not crosstalk to cut.
521. ★ Copyrighted-music detection (steady spectrum, no game audio underneath) with the stretches flagged before export.
522. A copyright-risk score per clip with mute, replace or cut offered for each flagged stretch.
523. Game-state classifier (lobby, queue, match, results, menu) from cheap frame features, so lobby talk is cut by different rules.
524. Round boundaries for round-based games from the buy-phase timer, so a clip can start at the round's start.
525. Teach a win screen with three screenshots: "this is what Victory looks like in my game".
526. Sudden large on-screen text (achievement, level up) as a signal, from the rate of text change.
527. Camera-motion intensity for IRL streams as an action signal.
528. A change in the number of faces (a guest walks in) starts a new section.
529. Turn-taking rate: fast back-and-forth is banter for shorts, long turns are a story for long-form.
530. Build-up detection from the voice: rising pitch and pace before a peak set where the clip should start.
531. Whispering detected as tension (stealth sections, secrets) and not treated as silence.
532. Discovery moments: "I've never", "first time", "what is that" mark first reactions.
533. Rage-quit detection: a slam or clipped mic, then silence, then the desktop.
534. Moments already clipped from an earlier stream are recognised, so the same joke is not posted twice.
535. Moment types that performed for this channel (from imported analytics) are weighted up per game automatically.
536. Show how sure the score is (a range, not one number) and what would make it surer (no chat log, weak transcript).
537. Per-signal switches for the scorer: turn chat off when chat was botted.
538. Bot and spam filtering of the chat log before spikes are counted.
539. A lane per signal on the timeline (laughter, chat, loudness, faces), each one toggled on its own.
540. A test bench: mark twenty moments by hand on one VOD and PULSE reports what it found and missed, then tunes itself.

## B. AI Clips and shorts (541–580)

541. ★ Loop builder: find an ending that cuts cleanly back to the opening and preview the loop three times round.
542. ★ Hook rewriter: five on-screen opening lines for the first two seconds (a question, a claim, the stakes) to choose from.
543. First-frame score: rate the opening frame for a visible face, motion and text, and offer better starts within a second.
544. Start on the stressed word of the sentence, not on its first word.
545. A context card of about a second ("He had 1 HP") written from the transcript for clips that need setup.
546. Payoff first, then rewind ("how did we get here") as a template with a rewind sound.
547. Three variants with different first three seconds, named for posting on different days.
548. One short, three platforms: TikTok, Shorts and Reels versions with each platform's caption position and cover in one click.
549. A three-panel vertical layout (game, facecam, chat) for chat-reaction clips.
550. Render the real chat beside the clip, in sync, from the imported replay.
551. The chat's most-used emote rains during the spike (opt-in).
552. A one-second zoom on the kill feed or scoreboard when the HUD event is the punchline.
553. A crop that widens when two players or two faces matter.
554. Keep-regions per game: the crosshair and minimap are never cropped out.
555. Freeze frame and a label ("this guy") as an intro, with the name from the speaker labels.
556. Punchline hold: six to ten frozen frames on the reaction face before the cut.
557. Reaction inset: the facecam grows for the reaction when the funny thing is in the game, then shrinks back.
558. A "why it works" checklist on each card: hook, payoff, loop, captions.
559. Show the length band that performs for this channel on the length filter.
560. Number the parts on screen and end each part on a tease of the next.
561. Find the continuation: when a clip's payoff comes later, offer it as a linked second short.
562. A posting plan: one short a day for the next days, with variety built in.
563. Variety guard: one day's exports are not three fails in a row.
564. A sensitive-content check before export: slurs, addresses or handles read aloud, private messages on screen.
565. Blur suggestions for on-screen personal details (emails, IP addresses, account names) found by text recognition.
566. Teammates named in voice chat are credited ("ft. @name") in the description.
567. Cover text for Shorts: the best frame plus three words.
568. Active-speaker crop for podcast shorts with several faces in frame.
569. A stacked two-speaker layout that gives the top half to whoever is talking.
570. The loudest syllable gets the biggest word: caption emphasis from the voice, not the dictionary.
571. Sponsor-safe mode: no emoji, no swearing, no meme sounds, for brand deals.
572. The clips that just missed the cut, with the reason each one missed, so a good one can be rescued.
573. "More like this" from any stretch you select on the timeline.
574. A clip you select by hand in the transcript gets the same polish an AI clip gets.
575. A marker you hit while live becomes a clip with the context extended automatically.
576. Countdown builder: rank moments into a "Top 5 this week" with number stings.
577. Compilations by tag ("every fail", "every clutch") from one VOD or several.
578. Bleep packs for shorts (cartoon, quack, horn) with a matching caption mask.
579. Cycle one choice on a card without opening the editor: next layout, next caption look, next music.
580. A second-by-second retention guess for each short, with the weakest second named and a fix offered.

## C. Edit My VOD and storytelling (581–625)

581. ★ Narrative arc builder: pick the throughline (goal, obstacle, attempt, result), order the moments to fit, and name what is missing.
582. ★ Open loops: plant a tease in the first half minute that points at a real later moment, and check that it is paid off.
583. A stakes line at the start ("Can we win with no armor?") written from the transcript, as on-screen text.
584. Recap cards after a long jump in the source ("Earlier: three losses in a row").
585. A re-hook proposed at each two-to-three-minute mark (a question, a tease, a change of scene), applied when chosen.
586. Every chapter ends on a peak or a tease; flat endings are flagged.
587. The tenth of the edit that contributes least to predicted retention, removable in one click.
588. A transition chosen by mood at each chapter change (whoosh and zoom, hard cut, fade) instead of one style throughout.
589. Time-skip labels ("2 hours later") when a cut jumps far in the recording.
590. A progress overlay for long challenges (level 3 of 10) that tracks through the video.
591. Running counters on screen (deaths, wins, attempts) driven by detected events.
592. A timer overlay for speedruns and timed challenges, locked to source time.
593. "Meanwhile" picture-in-picture from a teammate's recording when both exist.
594. Cutaways from the same recording: earlier or later gameplay under a story being told.
595. Zoom language by moment: a slow push for tension, a snap for a punchline, a pull-out for a reveal.
596. Sound recipes by moment: riser into hit for a reveal, record scratch for a fail, bass drop for a clutch.
597. A silence beat: under a second of near-quiet before the biggest reveal, music and ambience both ducked.
598. Two-second music stings on chapter cards, in the bed's key.
599. An outro that sells the next video with a five-second tease from the next project.
600. An intro governor: no more than a set number of seconds before the first real moment.
601. A "viewer knows nothing" check: references to things the edit never showed get context or get cut.
602. Chapter names in a chosen voice (plain, funny, searchable) with a regenerate button.
603. Split a six-hour VOD into episodes that each end on a cliffhanger.
604. Series consistency: the same sting, end card and numbered titles across episodes.
605. Best-of montage or chronological story: two selection modes for the same recording.
606. A sponsor slot reserved at a natural lull after the first payoff, with a marker and a length.
607. Mid-roll positions suggested at lulls right after payoffs on videos over eight minutes.
608. Director's notes: a plain-English account of the structure PULSE chose, so you can disagree with it.
609. Rebuild one chapter and keep the rest.
610. Lock a section so a re-run never touches it.
611. Eight, twelve and twenty minute cuts built together, with their predicted retention side by side.
612. Audience presets: fans tolerate in-jokes, new viewers need context.
613. Slow talkers sped up 5 to 15 percent with pitch kept, per speaker.
614. Breaths trimmed and pauses kept natural: 120 to 180 ms between sentences instead of a butt cut.
615. J-cuts and L-cuts at section changes: the next sound leads the picture by a few frames.
616. Reaction cutaways timed to the first syllable of the laugh.
617. After each punch-in the frame settles somewhere slightly different, so zooms never feel like a metronome.
618. The same meme or sound effect is not used twice within a set number of minutes, or in back-to-back videos.
619. An emotional contour: highs and lows plotted, and three highs in a row without a breather flagged.
620. Open on the best moment and close on the second best, as a rule you can turn on.
621. Cold-open variants: a quote, an action or a question.
622. A promise check: the first fifteen seconds must show what the title and thumbnail promise.
623. "Previously on" for a series, built from the last episode's edit report.
624. No-commentary gameplay: long quiet stretches become a sped-up montage under music instead of being cut.
625. With no facecam, gameplay zooms and HUD call-outs stand in for face punch-ins.

## D. Editing styles and the coach (626–660)

626. ★ Make a built-in editing style the default for each kind of recording (gameplay: Retention cut, podcast: Clean commentary) with one switch in Settings.
627. ★ Style A/B: build the same VOD in two styles and compare the predicted retention and the coach's score side by side.
628. A style editor: duplicate a built-in style, move its numbers with sliders (cut rate, zoom rate, caption words), save it as your own.
629. Styles as small files you can send to an editor or post for a community.
630. A style per channel: main channel, clips channel and shorts each remember their own.
631. Styles that learn: nudge a style's numbers toward what held viewers in your last twenty uploads.
632. Blend a built-in style with a studied reference, the way two references blend today.
633. Preview one moment of your footage in each style for thirty seconds before choosing.
634. The stretches with no cut, zoom or pop-up drawn as a lane on the ruler; click one to jump there.
635. A choice of fix for a held shot: punch-in, cutaway, caption beat, or leave it.
636. "Add a chapter card here" as the one-click fix for the coach's new-section advice.
637. An early-reset check: on long videos, something must change between 25 and 35 seconds, with a one-click fix.
638. A score per chapter, not only for the whole edit.
639. Compare with your own best video: "your top video cut every 6 s; this one every 14".
640. A trend across your last ten edits: is the hook, the pacing or the polish improving?
641. Coach strictness: gentle, standard or ruthless.
642. Mute one kind of advice for good ("stop telling me about music").
643. Each piece of advice says where it comes from (subtitling standards, this channel's analytics, a style's rules).
644. A smoothness check on moves you made by hand: linear or snapping keyframes are flagged, with ease offered.
645. Ease presets on any move in one click: smooth, snappy, overshoot, settle.
646. A speed graph for a pair of keyframes, so a move can start slow, travel and settle.
647. Zooms at different speeds on either side of a cut are flagged as a seam.
648. Cut-on-action helper: nudge a cut up to three frames to land on the peak of the motion.
649. Zoom starts and pop-ups can snap to the music's beat grid.
650. Too much at once: a zoom, a pop-up, a sound and a caption emphasis inside half a second are staggered.
651. A sound-fit check: a whoosh with nothing moving, a hit with nothing happening.
652. A music-fit check: the bed's energy against the section's energy.
653. An emphasis budget: no more than a set number of highlighted words per sentence.
654. Facecam colour drift through a long video is flagged and evened out.
655. Loudness checked per section, not only across the whole program.
656. A framing check after each punch-in: eyes on the upper third, no cropped chin.
657. A teaching mode: when you make a cut, the coach asks what it serves (the feeling, the story, the rhythm).
658. Lessons: the sample project edited step by step in a chosen style, each choice explained.
659. A weekly review of what you changed after the AI, folded into a personal style.
660. A style's principles pinned beside the timeline while you edit in it.

## E. Timeline (661–705)

661. ★ Trim while it loops: the edit plays around the cut and J, K and L move the cut point.
662. Sub-frame audio trims for clean word edges.
663. Several timelines open as tabs, with drag between them.
664. Two timelines stacked, one above the other, for comparing versions.
665. Source patching: choose which tracks an insert lands on.
666. Sync lock per track, so a ripple keeps everything in step.
667. A track-select-forward tool: everything to the right of the click.
668. Clips coloured by source file automatically.
669. A badge on a clip whose source range is used elsewhere in the edit.
670. Through-edit marks on cuts that changed nothing, and "join through edits".
671. A sync-drift badge between linked picture and sound with one-click resync.
672. Adjustment layers: an effect or grade applied to everything beneath.
673. Smooth slow motion by frame blending or optical flow.
674. A speed painter: draw faster and slower stretches across a clip in one stroke.
675. Auto-sequence: select items in the media panel and lay them out in order.
676. Reordering in the storyboard reorders the built timeline.
677. A ghost playhead at the previous cut for comparing two points.
678. Skim a clip by moving the pointer across it.
679. Skimming with pitch-corrected sound.
680. Sticky notes on clips.
681. Review comments from the shared page anchored on the timeline at their timecodes.
682. Each track's height remembered per project.
683. Vertical zoom for waveforms.
684. Waveforms coloured by speaker.
685. A spectrogram view on audio clips.
686. Silences shaded on a clip before anything is cut.
687. Filler words as chips on the waveform; click one to remove it.
688. Tighten only the selected clips, with a count of what would go.
689. Hold a key to place a clip freely on the magnetic timeline.
690. Swap a clip with its neighbour by dragging.
691. Extend the edit to the playhead, and trim the start or end to the playhead, each on one key.
692. Top and tail from the keyboard while it plays.
693. A marker palette: your own marker types (funny, fix audio, thumbnail frame) on the number keys.
694. Range markers, and the marker list exported as a spreadsheet file.
695. Markers placed automatically at detected laughter and applause.
696. One switch to show or hide every AI zoom, pop-up and sound.
697. Solo or mute the AI's layer to compare with and without.
698. Pin a clip in place so ripples flow around it.
699. Excitement and predicted retention drawn on the minimap.
700. Undo as a tree: go back, try another way, and return to the first branch.
701. Rename clips in bulk by pattern.
702. A playback HUD on the timeline: frames per second, dropped frames, cache hits.
703. Nest and un-nest by dragging one timeline into another.
704. Paste insert at the playhead across all tracks with their offsets kept.
705. A ripple preview: before a big delete, the timeline shows where everything will land.

## F. Viewer and playback (706–720)

706. Two-up viewer: source on the left, program on the right.
707. A filmstrip of the next and previous cuts under the viewer.
708. Onion-skin overlay of the previous shot for match cuts.
709. A focus-peaking style overlay that shows where the frame is sharp.
710. False colour and zebra stripes for exposure on the facecam.
711. A caption-safe check in the viewer: a warning when a pop-up, logo or facecam covers the captions.
712. Phone preview: the viewer mirrored to an iPhone on the same network at real size.
713. A mute-preview button: watch as a muted viewer would, captions on.
714. A small-screen preview at the size a phone actually shows it.
715. Play every cut point in turn, two seconds around each, to check them all quickly.
716. Play only the AI's changes: jump from zoom to pop-up to sound.
717. A/B two versions of an edit on one key while playing.
718. Frame export to the clipboard and to the project as a still.
719. Draw on the frame (arrow, circle) for notes that travel with the review page.
720. Colour-blind simulation in the viewer for checking caption and overlay contrast.

## G. Captions and text (721–760)

721. ★ Caption pages split by reading speed: a page that would need more than about twenty characters a second is split automatically.
722. A minimum time on screen for every page, borrowed from the next page's lead-in when a line is short.
723. Line breaks that never strand a short word ("a", "the", "to") at the end of a line.
724. Names and numbers kept on one line.
725. Captions that move out of the way of faces, the HUD and other text on screen.
726. Background-aware captions: the outline thickens on busy or bright footage and thins on dark.
727. Caption colour sampled from the frame so it never matches what is behind it.
728. A caption style per section of one video (bigger in the hook, quieter in the story).
729. Emphasis styles beyond colour: scale, shake, underline, a box, a glow, each previewed live.
730. Words that grow with volume: loud words bigger, whispers smaller.
731. Sound captions ("[laughs]", "[explosion]") added from the audio analysis for viewers who are deaf or watch muted.
732. Speaker identification by position: a caption sits under whoever is talking.
733. Sing-along timing for music sections: syllable-level highlighting.
734. A profanity style per platform (masked on TikTok, as said on YouTube).
735. Every caption style previewed on a bright frame and a dark frame of your own footage at once.
736. A hold on the punchline: the last caption page of a joke stays up through the laugh.
737. Capitalisation rules per brand ("iPhone", "VALORANT", your handle).
738. Numbers and money formatted consistently ("1,000", "$5").
739. A caption voice per speaker: the font and case that suit each person, chosen once.
740. Animated emoji and stickers timed to a word.
741. Two caption tracks on screen for bilingual audiences, one above the other.
742. Translated captions checked by back-translation, with unsure lines flagged.
743. Translation memory: a phrase you corrected once is translated your way every time.
744. Right-to-left and vertical scripts laid out correctly.
745. A font fallback chain per language so no character shows as a box.
746. Variable-font weight animated with the emphasis.
747. Title designer: animated titles built from lines, shapes and text with keyframes, saved as templates.
748. Lower thirds that size themselves to the name they hold.
749. Callout arrows that follow a tracked point.
750. Text along a path, and text that wraps around a face.
751. A quote card generator: the best line of the stream as a still for social posts.
752. On-screen chat messages pulled from the replay as styled bubbles at the moment they were sent.
753. Poll and prediction results from the stream shown as an animated bar.
754. A typing animation with key sounds for chat-style storytelling.
755. Text presets that follow the Brand Kit's colours when the kit changes.
756. Paste a script: text is aligned to the audio by forced alignment, word by word.
757. Subtitle export checked against a platform's rules (line length, duration) before it is written.
758. Chapters and captions exported as a readable transcript with timestamps, for a blog post or show notes.
759. A caption diff: what changed between the transcript and what is on screen.
760. Caption confidence heat: low-confidence words tinted on the viewer so you can fix them where you see them.

## H. Audio and mixing (761–800)

761. ★ A dialogue-first mix assistant: sets voice, game and music levels so speech always wins, and shows what it changed.
762. Intelligibility score: how understandable the speech is over the game and music, per section.
763. Game audio ducked under speech by frequency, so footsteps and gunfire survive but the voice range clears.
764. Automatic de-clip for a mic that peaked on a scream.
765. Breath control: breaths lowered, not removed.
766. Mouth-click removal.
767. Keyboard and mouse click reduction under speech.
768. Room echo reduction for untreated rooms.
769. Wind and handling noise reduction for IRL streams.
770. A voice profile per speaker: the EQ and compression that suit this voice, saved and reused.
771. Match the sound of two mics (a guest on a headset beside a studio mic).
772. Phase and polarity check between mic and camera audio in multicam.
773. A discord-voice clean-up preset for compressed guest audio.
774. One mix exported at each platform's loudness target in a single job.
775. A phone-speaker check: hear the mix as a phone would play it.
776. A mono-compatibility check.
777. Bass management: game rumble kept out of small speakers.
778. Stereo width for music beds under a mono voice.
779. Spatial placement: the voice leans to the side its facecam sits on, by a set amount.
780. A dynamic range choice (tight for phones, open for headphones).
781. Automation modes for volume: write a fader move while it plays.
782. Clip gain normalised across a selection to a target.
783. A mixer panel: faders, pan, sends and meters for every track.
784. Buses: a dialogue bus, a game bus and a music bus with their own processing.
785. A reverb send for moments that want space (a dramatic line, a victory).
786. A telephone or radio effect for quoted messages and voice-chat lines.
787. Pitch and formant shift for comedy.
788. A "slow-mo voice" effect tied to speed ramps.
789. Reverse reverb risers into a line, generated from the line itself.
790. Sound that follows a zoom: the voice comes slightly forward on a punch-in.
791. An audio spectrum that shows where voice and music collide.
792. Stem export: dialogue, game, music and effects as separate files.
793. An AAF or OMF export for a sound mixer.
794. Round-trip to an audio editor and back for one clip.
795. A lyrics detector that marks where a song's words fight the voice.
796. A teleprompter for voice-over lines written by the title generator.
797. Auto-pauses in voice-over tightened to the picture.
798. A scratch voice-over spoken by the system voice to time a section before you record it.
799. Laughter and applause preserved at their natural tail when a cut would clip them.
800. An audio fingerprint per export so a re-upload of your own clip can be recognised later.

## I. Music and sound design (801–830)

801. Music that follows the edit: the bed is recomposed so its build lands on the section's payoff.
802. Hit points: mark three moments and the bed's accents land on them.
803. An ending for every bed: a composed final bar instead of a fade.
804. Intros and outros cut from the same bed so a video sounds like one piece.
805. Key and tempo matching between neighbouring beds.
806. A musical transition (drum fill, riser) composed between two beds.
807. Mood changes inside one bed: the same theme, calm then driving.
808. A motif per channel: a short theme the composer weaves into every video.
809. Genre packs for the composer (lo-fi, trap, orchestral, chiptune, synthwave).
810. Instrument choices per bed (no drums under dialogue, drums on action).
811. A sound-effect layer builder: combine a whoosh, a sub hit and a shimmer into one designed sound.
812. Risers generated to an exact length that end on the cut.
813. Impacts with a tail length matched to the shot.
814. Foley from the picture: a click for a UI press, a thud for a fall, chosen from what the frame shows.
815. Ambience beds (room, crowd, wind) for stills and title cards.
816. A comedy pack and a drama pack of effects with different defaults.
817. Sound effects by description ("short wet splat") searched across the library and plug-in packs.
818. The same effect never plays twice in a row: variants rotate automatically.
819. Effect loudness set by the moment's size, not one level for all.
820. A swear-jar sound per channel.
821. Signature sounds: your own recorded stingers used wherever the editor would place a library one.
822. Voice memes: your own catchphrase clips placed as effects on matching moments.
823. A licence ledger: every track and effect in an export listed with its licence and source.
824. A "safe for monetisation" badge on every library item.
825. Tempo, key and mood read from the files in your own music folder, so they search like the built-in library.
826. Tempo-synced delays and stutters on a word.
827. A beat-repeat effect for the last word before a drop.
828. Sidechain pump on the bed for montage sections.
829. Vinyl stop and tape rewind effects tied to rewinds and freezes.
830. A sound map of the edit: where effects cluster and where there are none.

## J. Inspector, effects and motion (831–865)

831. Motion tracking: a point, a face or a box followed through a clip, with text, blur or a sticker attached to it.
832. Blur or pixelate a moving region (a face in the crowd, a name on screen) that stays on its target.
833. Background removal for the facecam without a green screen, as an effect with edge controls.
834. Background replacement and blur for the facecam.
835. A drop shadow and outline on the cut-out facecam so it sits on the gameplay.
836. Stabilisation for handheld IRL footage.
837. Lens-distortion correction for wide webcams and action cameras.
838. Rolling-shutter repair.
839. Upscaling for low-resolution sources at export.
840. Frame interpolation from 30 to 60 fps for gameplay.
841. Deinterlacing and noise reduction for old captures.
842. A "shake" effect driven by the audio's loudness.
843. Glitch, RGB split and scan-line effects with intensity, for transitions and stings.
844. Speed lines and impact frames for comedy hits.
845. Light leaks, flares and film burns as overlays with blend modes.
846. Blend modes on every layer.
847. Masks with shapes, bezier paths and feathering, animated with keyframes.
848. Track mattes: one layer shows through the shape of another.
849. A spotlight effect that dims everything but a chosen region.
850. A magnifier for small HUD details, with a line to what it enlarges.
851. Split-screen builder with animated dividers.
852. Picture-in-picture presets with animated entrances.
853. A transition designer: build a transition from moves, blurs and wipes and save it.
854. Whip-pan, zoom-blur and spin transitions with motion blur.
855. Match-cut helper: align two shots on a face or an object.
856. Motion blur on animated moves.
857. Expressions for linking properties (this layer's scale follows the audio level).
858. Effect presets that carry their keyframes.
859. Favourite effects on a shelf at the top of the panel.
860. A before and after toggle per effect while playing.
861. GPU cost shown per effect so a heavy stack is no surprise.
862. Effects applied to a range of the timeline, not a clip.
863. A LUT or look applied only inside a mask.
864. Parameter randomiser: twenty variations of a look to pick from.
865. A history of the last values for every property, to step back one change without undo.

## K. Export, delivery and the app's own distribution (866–905)

866. ★ Developer ID signing and notarization in the release workflow, so the first launch shows no warning.
867. Delta updates: download only what changed between versions.
868. A Homebrew cask and a direct download page with checksums.
869. A portable build that keeps settings beside the app, for a shared edit machine.
870. An App Store build with the sandbox entitlements it needs.
871. Rollback to the previous version from the update sheet.
872. Release notes inside the app for every version, searchable.
873. A status page of known issues for the installed version, fetched when online.
874. Export presets per platform kept current from a small file the app can update.
875. Smart re-render: only the changed sections are rendered again.
876. Resume an interrupted export from the last finished segment.
877. Segment-parallel export across performance cores.
878. A background export service that keeps running when the window closes.
879. Export on another Mac on the network (send the job, get the file back).
880. A render farm of your own Macs for overnight batches.
881. AV1 export where the hardware supports it.
882. HDR export (HLG, PQ) with tone-mapped SDR alongside.
883. A GIF and animated WebP export for short reactions.
884. An image-sequence export.
885. Vertical, square and landscape versions of one edit in one job.
886. Per-platform bitrate ladders with the reason for each.
887. A deeper check after export: black frames, frozen frames, silent stretches and clipped audio, each with its timecode.
888. A side-by-side of source and export at a chosen frame, zoomed.
889. File-size prediction before export within ten percent.
890. An upload-time estimate from a measured connection speed.
891. Watermark variants: none, corner logo, moving handle.
892. A burned-in timecode and name for review copies.
893. A password-protected review file.
894. Chapters, captions and a thumbnail embedded in the file where the format allows.
895. Export a project as a self-contained folder with relinked media for another editor.
896. A DaVinci Resolve and Premiere project export with effects mapped where they exist.
897. An EDL export for finishing houses.
898. Import an XML or OTIO edit made elsewhere.
899. Export presets shared as files.
900. A destination per preset (this preset always lands in this folder).
901. Post-export actions: run a script, move a file, send a notification.
902. An "archive master" exported with every delivery for safekeeping.
903. Exports named from the title chosen for upload.
904. A delivery checklist per platform, ticked automatically where PULSE can verify.
905. A receipts log: what was exported, when, with which settings, and its checksum.

## L. Publishing and growth (906–960)

906. ★ A posting plan across platforms: what goes where and when for the week, from the clips you have.
907. Best-time suggestions from your own analytics, per platform.
908. Upload presets per platform (visibility, category, audience, comments) applied in one click.
909. Direct upload to Instagram Reels.
910. Direct upload to X and to Facebook.
911. A draft uploaded privately for a last look on the phone before it goes public.
912. Scheduled posts shown on a calendar you can drag.
913. A queue that posts through the week without the app open (using each platform's scheduling).
914. Titles, descriptions and tags tailored per platform from one source.
915. Hashtag sets per game with a rotation so the same set is not posted every day.
916. A pinned-comment draft for each upload.
917. Playlists chosen at upload from the project's game.
918. End screens and cards set at upload.
919. Chapters written to the description at upload and checked against YouTube's rules.
920. Captions uploaded as a track, in each language you have.
921. A premiere option with a countdown.
922. Shorts linked to their long video ("watch the full video").
923. Community-post drafts with the best still and a line.
924. A cross-post tracker: which clip went where, with links.
925. Views, likes and retention pulled back per upload.
926. A dashboard per project: what was made, what was posted, how it did.
927. Which clips from one stream did best, and what they had in common.
928. Hook performance: the share of viewers still watching at three seconds, per short.
929. A/B results gathered from variants posted on different days.
930. A leaderboard of your own shorts with the editing choices beside the numbers.
931. A monthly report: hours streamed, clips made, views earned, time saved.
932. Goals (three shorts a day, one video a week) with a streak.
933. A reminder when a stream has not been clipped after a day.
934. A "post while it's fresh" alert for moments tied to an event or a patch.
935. Trend watch per game: which formats are rising, from public data you choose to fetch.
936. ★ Import a video's retention graph from YouTube Studio and draw it on that project's timeline.
937. ★ Coach calibration from retention, second by second: what the audience left during, learned per channel.
938. Drop-off autopsy: for each dip in the graph, what the edit was doing in the ten seconds before.
939. Rewatch spikes found in the graph become clip candidates.
940. Click-through and retention shown together per title and thumbnail pair.
941. Title tests tracked: which wording won.
942. Comment mining: timestamps and quotes viewers mention most become markers.
943. Questions from comments collected as ideas for the next stream.
944. A sentiment summary of comments per video.
945. Sponsor reporting: the slot's retention and the clicks you report, on one page.
946. An earnings estimate from views and a rate you set.
947. A content calendar that knows your stream schedule.
948. A backlog view: every unposted clip across projects, ranked.
949. Evergreen picks: old clips worth reposting, with the last post date.
950. A clip bank searchable by game, tag and words.
951. Collections you can share as a page (a best-of for a sponsor or a team).
952. A press kit page: stats, top clips, contact.
953. A link-in-bio page generated from recent uploads.
954. Clip requests: viewers submit a timestamp through a form and it arrives as a marker.
955. A moderators' queue: trusted viewers mark moments during the stream.
956. A Discord bot that posts finished clips to a channel.
957. A Twitch clip importer: clips your viewers made become candidates with their view counts.
958. Twitch markers and highlights imported with the VOD.
959. Stream metadata (title, game changes) imported and used as chapters.
960. A yearly rewind built from the best-performing clips.

## M. Thumbnails and titles (961–985)

961. Thumbnail scoring: face size, contrast, text legibility at phone size, clutter.
962. A phone-size preview of the thumbnail beside real thumbnails from your niche.
963. Light and dark background previews, as YouTube shows them.
964. Three layouts per pick (face left, face right, no face) generated together.
965. Search a stream's frames by description ("holding the trophy") to find the thumbnail moment.
966. Eye-line arrows and circles placed toward the subject.
967. Background blur and brightness set so the subject stands off it.
968. An outline around the cut-out subject in a Brand Kit colour.
969. A colour-pop pass: saturation and contrast tuned for small sizes.
970. Game logo or character art placed from a per-game asset folder.
971. Before and after split thumbnails for challenge videos.
972. Number badges ("#1", "100 days") as a style.
973. Text limited to four words, with a warning past that.
974. Title and thumbnail checked together: the thumbnail should not repeat the title.
975. Title scoring: length, front-loaded keywords, curiosity without lying.
976. Title styles: plain, question, challenge, "I tried", with one of each offered.
977. A clickbait honesty check: does the video show what the title says, and when?
978. Search-friendly descriptions with the first two lines written to be read.
979. Tag suggestions from the transcript and the game.
980. A title history per channel, so a new title is not a near copy of a recent one.
981. Titles translated for each caption language.
982. A thumbnail library with the click-through each one earned.
983. A reminder to refresh the thumbnail of a video whose click-through has fallen.
984. A frame-grab burst: ten sharp frames around a moment to choose from.
985. A stills contact sheet for a whole stream at one frame per moment.

## N. Brand Kit and templates (986–1005)

986. A Brand Kit built from your channel: colours and fonts suggested from your banner and thumbnails.
987. Several kits (per channel, per sponsor) switched per project.
988. Animated logo stings generated from a still logo.
989. A subscribe animation in the kit's colours.
990. Transition and sound choices as part of the kit.
991. A kit preview on your own clip, not the sample.
992. Lock a kit so a collaborator cannot drift from it.
993. A seasonal variant (holiday colours) that reverts on a date.
994. Templates with placeholders ("drop your clip here") for recurring formats.
995. A format builder: intro, three moments, outro, saved as a template any VOD can fill.
996. Templates for weekly shows (top plays, patch notes, Q&A).
997. A template gallery with a preview of each on your footage.
998. Templates shared as files, with their sounds and fonts inside.
999. Template versions, so an old video can still be opened as it was.
1000. Per-game templates chosen automatically from the detected game.
1001. A lower-third and a name tag for recurring guests, remembered by voice.
1002. Sponsor templates: a tag, a card and a required disclosure line.
1003. A watermark schedule (on for clips, off for the long video).
1004. End-card variants that rotate so regular viewers do not tune out.
1005. A style guide page generated from the kit, to hand to an editor.

## O. Colour (1006–1020)

1006. Shot-by-shot auto balance for the facecam through a long stream as the room light changes.
1007. A skin-tone line on the vectorscope with a one-click correction toward it.
1008. Game footage and facecam graded separately by default, each with its own look.
1009. HDR game capture tone-mapped on import with a choice of rendering.
1010. Colour wheels (lift, gamma, gain) and curves.
1011. A qualifier: pick a colour range and change only that.
1012. Power windows that follow a face.
1013. Looks that adapt to the game's palette instead of one LUT for everything.
1014. A legal-range check and a gamut warning.
1015. A reference still pinned in the viewer while grading.
1016. Grades copied across every clip from the same camera.
1017. A look intensity keyframed over time (colour drains before a sad moment).
1018. Black-and-white with one colour kept, for stings.
1019. A night-mode correction for dark facecams (noise-aware lift).
1020. Display calibration notes: what your screen cannot show.

## P. Performance and reliability (1021–1060)

1021. ★ A real rendered frame in CI's screenshots, so viewer regressions show up before a release.
1022. Screenshot diffs in CI: a page that changed by more than a few percent fails the run until approved.
1023. A light-theme screenshot of every page in CI.
1024. A long-timeline benchmark in CI with a budget for scrolling and scrubbing.
1025. Memory and energy budgets checked per release on a reference recording.
1026. A real-footage test set (with permission) beside the generated sample, for the scorer and the editors.
1027. Golden edits: the auto-editor's output on fixed inputs compared release to release.
1028. Fuzzing for project files: damaged or truncated projects must open or fail cleanly.
1029. A canary channel: a few opted-in users get each build a day before everyone else, and it is pulled if they hit a crash.
1030. A project doctor: checks a project for broken links, orphaned media and impossible timings, and repairs them.
1031. Autosave to a second disk or a cloud folder as well.
1032. A media-offline mode that keeps editing with proxies when the source disk is unplugged.
1033. Proxy-only projects for laptops, relinked to full quality at export.
1034. Analysis on one Mac, editing on another: the analysis travels with the project.
1035. Analysis that uses the Neural Engine where a model allows.
1036. Whisper large models split across chunks in parallel on performance cores.
1037. Transcription that starts with the parts most likely to hold moments (loudest first).
1038. Incremental analysis when a recording is extended or replaced.
1039. A pause-everything switch for when you start streaming.
1040. Thermal awareness: slow the batch before the Mac throttles.
1041. A disk-speed test on the media drive with advice (too slow for 4K scrubbing).
1042. Cache placement per drive (thumbnails here, proxies there).
1043. A startup that restores the last project lazily, track by track.
1044. Timeline drawing moved to Metal for thousands of clips.
1045. Waveforms at multiple resolutions so zooming never recomputes.
1046. Thumbnails decoded on demand with a hard cap per second.
1047. A watchdog that reports the action which froze the interface, with timings.
1048. Crash-free sessions tracked locally and shown on the Diagnostics page.
1049. A "what changed" list after an automatic recovery.
1050. Undo that survives a crash.
1051. A compatibility check on launch after a macOS update.
1052. A fallback encoder path tested on every release.
1053. Corrupt-frame tolerance: a damaged source frame is skipped and reported, not fatal.
1054. Variable-frame-rate sources handled without conforming, with exact timestamps.
1055. Very long recordings (twelve hours and more) tested for memory and index size.
1056. Network drives and removable disks handled with clear messages when they vanish.
1057. A low-disk mode that trims caches before it runs out.
1058. Background jobs that survive quitting, with a helper that finishes them.
1059. A reproducible build with a published checksum for each release.
1060. A public test plan and a short list of what each release verified.

## Q. Onboarding, help and learning (1061–1080)

1061. ★ First run on your own footage in under two minutes: drop a VOD, see three clips from its first ten minutes while the rest analyses.
1062. A goal picker on first launch (shorts, YouTube videos, both) that arranges the app around it.
1063. Checklists that track real progress (first clip made, first export, first upload).
1064. A "show me" button beside features that plays a ten-second demonstration on the sample.
1065. Tooltips that link to a short clip of the feature in use.
1066. A searchable help panel inside the app, written from the docs folder.
1067. An "ask how" box: plain-English questions answered from the help, on the Mac.
1068. Undo explanations: after a big AI change, a card says what happened and how to reverse it.
1069. A glossary for editing terms (ripple, J-cut, LUFS) on hover.
1070. Editing lessons from the built-in styles, each ending in an exercise on your footage.
1071. A weekly tip chosen from features you have not used.
1072. A "what's new for you" page after an update, filtered to what you use.
1073. Keyboard training: a game that teaches ten shortcuts in five minutes.
1074. A sandbox project that resets itself, for trying things without fear.
1075. Guided fixes: when an export fails, the steps to resolve it, with buttons.
1076. A requirements check with plain advice (free disk space, macOS version, microphone permission).
1077. Permission prompts explained before macOS asks.
1078. A migration guide from CapCut, Premiere and Resolve: where each thing is here.
1079. Importing shortcuts from another editor's layout.
1080. A feedback button on every AI result ("this was wrong because…") that tunes the settings it can.

## R. Design and interface (1081–1100)

1081. A density setting (comfortable, compact) for pages and for the editor separately.
1082. The dashboard on Home shows today's numbers the way BulkBoard does: clips ready, minutes edited this week, exports waiting.
1083. A project page: one project's recordings, clips, edits and exports as cards, before the editor opens.
1084. Stat tiles on the Projects page (in progress, due soon, exported this week).
1085. Empty states that show a small picture of the result, not only an icon.
1086. A consistent "detail panel" on the right for every page that selects things (Media, AI Clips, Exports).
1087. Sheets resized to their content with a footer that never scrolls away.
1088. A unified filter bar component (segments, search, sort, view) used by Projects, Media and AI Clips.
1089. Drag handles and hover affordances that show what can be dragged before you try.
1090. Skeleton placeholders while thumbnails and waveforms load.
1091. Progress that names its stage ("reading faces, 3 of 5") everywhere, with time left.
1092. One notifications tray for finished jobs, warnings and updates.
1093. Charts in the BulkBoard manner: one accent for the series, quiet axes, a hover readout.
1094. A weekly activity chart on Home.
1095. Window tabs and full-screen split view support.
1096. Touch Bar replaced by a customisable toolbar strip under the viewer.
1097. Per-page keyboard hints shown while a modifier is held.
1098. A "focus mode" that hides everything but the viewer and timeline.
1099. A light theme tuned for bright rooms and a high-contrast variant of both themes.
1100. An accent that can follow the game detected in the project.

## S. Automation and integrations (1101–1135)

1101. ★ Rebuild only what changed: after a setting change, re-run the one pass it affects instead of the whole edit.
1102. A recipe builder: chain steps (import, analyse, clips, edit, export, upload) and run them on any VOD.
1103. Recipes triggered by a new file in a folder, a finished stream, or a time of day.
1104. A command-line tool for every recipe step, for scripts and servers.
1105. A local HTTP API with a token, for Stream Deck, Raycast and home automation.
1106. A Raycast and an Alfred extension: search clips, start a batch, open a project.
1107. MIDI and game-controller mapping for marking, cutting and scrubbing.
1108. An OBS script: mark a moment, start and stop PULSE's analysis with the stream.
1109. An OBS dock showing PULSE's live moment meter.
1110. Streamer.bot and Mix It Up actions.
1111. A Twitch extension or chat command (!clip) that drops a marker.
1112. A Discord rich presence while editing (optional).
1113. A Notion or Airtable sync of projects and their status.
1114. A Google Sheets export of clips with titles, tags and links.
1115. Calendar events for deadlines and scheduled posts.
1116. A Frame.io style hand-off: send an export for review and receive comments back.
1117. Dropbox, Drive and iCloud project sync with conflict handling.
1118. A watch folder on a network drive shared by a team.
1119. An email or message when the overnight batch finishes, with thumbnails.
1120. A menu-bar app that shows batch progress and lets you start one.
1121. A quick-capture window: paste a link, choose a recipe, go.
1122. Finder Quick Actions for "Make shorts" and "Edit this VOD".
1123. A share-sheet extension: send a video to PULSE from any app.
1124. A Photos library importer for phone footage.
1125. An iPhone companion to record a second angle that arrives synced.
1126. A plug-in type for exporters (a new destination without waiting for a release).
1127. A plug-in type for caption styles.
1128. A plug-in type for layouts.
1129. A plug-in type for moment scorers written as small scripts.
1130. A plug-in gallery with signatures and permissions shown before install.
1131. A scripting console inside the app with the document open for inspection.
1132. Webhooks on job events.
1133. A dry-run mode for recipes that reports what would happen.
1134. A run history with logs and the ability to re-run a step.
1135. Recipes exported as files and shared.

## T. Recording and live (1136–1160)

1136. A replay buffer: keep the last few minutes in memory and save them with one key.
1137. A "clip that" key that saves the last sixty seconds and analyses it straight away.
1138. Voice chat recorded on its own track, so teammates can be turned down or bleeped on their own.
1139. A per-app audio capture picker (the game on one track, Discord on another).
1140. A noise gate and compressor on the mic while recording, monitored but not baked in.
1141. A scene-aware recorder: knows which OBS scene was live and stores it as metadata.
1142. A facecam recorded clean and full-frame beside the composited stream.
1143. A lighting and exposure check on the webcam before recording, with the fix in plain words.
1144. A test recording that checks levels, sync and dropped frames in ten seconds.
1145. Dropped-frame and encoder-lag warnings while recording.
1146. A disk-time-left readout while recording.
1147. A crash-safe container: a recording interrupted by a crash still opens.
1148. Automatic chapter markers at scene, game and title changes.
1149. A running transcript while recording, searchable afterward at once.
1150. A second-monitor dashboard while live: levels, dropped frames, moments marked so far.
1151. A countdown and an on-air light in the menu bar.
1152. A scheduled recording that starts with your stream schedule.
1153. A recording profile per game.
1154. HDR and high-frame-rate capture where the display supports it.
1155. A capture-card input as a source.
1156. A phone as a wireless webcam source.
1157. A guest recorder: a link for a guest to record a clean local track that uploads afterward.
1158. A backup audio recording at lower gain in case the main track clips.
1159. Push-to-mark with a voice note ("that was the funny bit") attached to the marker.
1160. A post-stream summary: length, moments marked, peaks found, ready to edit.

## U. Multicam and co-streams (1161–1180)

1161. A squad project: several players' VODs of one session, synced and searchable together.
1162. The best point of view per moment chosen automatically across players.
1163. A split screen of two players at the moment they meet.
1164. Voice chat aligned across recordings so a line is heard once.
1165. Each player's kill or death labelled with their name from their own HUD.
1166. A "from every angle" replay of one moment.
1167. A director's view: all angles in a grid with live audio meters.
1168. Angle suggestions by rule: wide for chaos, close for the reaction.
1169. A cutaway to the listener in podcast multicam (the nod, the laugh).
1170. Eye-line and screen-direction checks between angles.
1171. Colour and loudness matched across players' recordings.
1172. A sync check that plays two recordings a few frames apart, so an echo tells you they are off.
1173. Drift correction over long sessions between devices.
1174. A guest's vertical phone video laid beside landscape footage sensibly.
1175. A talk-show layout: host large, guests in a row, speaker highlighted.
1176. A debate layout with a timer per speaker.
1177. Angles renamed and ordered once, remembered per recurring setup.
1178. A proxy workflow for multicam so four angles scrub smoothly.
1179. A multicam short builder: the best angle per beat in a vertical frame.
1180. A shared-project hand-off so each player can export their own cut.

## V. Collaboration and review (1181–1200)

1181. ★ A review link with timecoded comments that come back onto the timeline as markers.
1182. Reviewers can draw on a frame and suggest a trim.
1183. Approve or request changes per clip, with the status on the card.
1184. Versions compared for a reviewer: what changed since they last looked.
1185. A read-only project for an editor's client.
1186. Roles: streamer, editor, manager, each with their own default page.
1187. An editor's inbox: recordings a streamer shared, with their notes and marks.
1188. A hand-off note template (what to make, style, deadline) attached to a project.
1189. Time-coded to-dos assigned to a person.
1190. A change log per project: who did what.
1191. Locking a timeline while someone edits it, with a takeover option.
1192. Project packages that carry only proxies for a remote editor, relinked later.
1193. Payment-friendly exports for freelancers: a summary of hours and deliverables.
1194. A style sheet per client (their styles, kits and rules) applied on open.
1195. A team library of sounds, templates and styles.
1196. Shared presets with a "who changed this" history.
1197. A comment digest by email or message at the end of the day.
1198. A public gallery page for a batch of approved clips.
1199. Guest approval: a guest receives the clips they appear in and can object before posting.
1200. A rights note per clip (who appears, what music, what was agreed).

## W. Import and media (1201–1225)

1201. Import straight from a Twitch account: pick a past broadcast from a list.
1202. Import from a YouTube channel's live archive by picking, not pasting.
1203. Kick, Facebook Gaming and TikTok Live archives as sources.
1204. Download only the stretch you need from a long VOD.
1205. A quality picker for downloads with the size shown.
1206. Chat, markers and metadata fetched with the VOD in one step.
1207. Resume a download on another network.
1208. A recording still being written (a live OBS file) opened and extended as it grows.
1209. A recordings library across projects: every source file, where it is used and what was made from it.
1210. Find the same footage in another project by fingerprint.
1211. Smart collections (this month's streams, every stream of one game).
1212. Faces grouped across the library, named once.
1213. Storage tiers: move old sources to an archive drive and keep proxies.
1214. A space report per project with what can be removed safely.
1215. Automatic proxy cleanup for projects marked finished.
1216. Source integrity checks (a checksum on import, verified before archive).
1217. Camera-card style ingest with verification for IRL cameras.
1218. Image sequences and animated images as sources.
1219. Layered image files with layers kept for overlays.
1220. Lottie and animated vector files as graphics.
1221. Subtitle files in more formats (ASS with styles, TTML).
1222. Audio from a separate recorder synced by waveform to a camera.
1223. Batch rename and tag on import by rule.
1224. Auto-tag recordings with the game, detected from the picture.
1225. A "what's in this recording" summary on import: games played, guests, the loudest minute.

## X. Privacy, safety and trust (1226–1245)

1226. A network monitor page: every connection the app made this session and why.
1227. An offline switch that blocks every network call and says what stops working.
1228. Cloud calls previewed: the exact text that will be sent, before it is.
1229. A redaction pass on text sent to a cloud model (names, handles, places).
1230. Per-project privacy rules ("never use cloud AI on this one").
1231. Local models for copy and translation as the default where the Mac can run them.
1232. Keys and tokens listed in one place with revoke buttons.
1233. A minors-on-screen warning from face detection, for creators who film in public.
1234. Bystander face blur as a one-click pass for IRL footage.
1235. Licence-plate and screen-content blur suggestions.
1236. A leaked-info scan of the picture: stream keys, emails, addresses, browser tabs.
1237. A check for another creator's footage inside a recording, with a fair-use note.
1238. Platform-policy hints per clip (violence, gambling, tobacco) before posting.
1239. An age-restriction risk estimate.
1240. A disclosure helper: adds "sponsored" or "AI-assisted" labels where a platform asks.
1241. An edit provenance record inside the export (what was changed by AI) using open content-credential standards.
1242. A deepfake guard: voice and face features that only work on yourself, with consent recorded.
1243. Encrypted project archives.
1244. A wipe command that removes a project, its caches and its analysis completely.
1245. A plain-language data map: where every kind of file lives on disk.

## Y. Accessibility and localization (1246–1265)

1246. The whole interface in Spanish, Portuguese, French, German, Japanese and Korean to begin with.
1247. Right-to-left interface layout.
1248. Dates, numbers and units following the system region everywhere.
1249. Full keyboard access to the timeline with spoken feedback.
1250. A VoiceOver rotor for cuts, markers and clips.
1251. An audio description of the picture for blind editors (what is on screen at the playhead).
1252. Sonified waveforms and meters (a tone that follows level).
1253. Captions for the app's own tutorial clips.
1254. Larger hit targets as a setting.
1255. Dynamic type through the whole interface.
1256. A dyslexia-friendly font option.
1257. Colour choices that never carry meaning alone: a shape or a label beside every colour code.
1258. Reduced-transparency and increased-contrast modes honoured throughout.
1259. Switch-control and voice-control labels on every control.
1260. A one-handed shortcut set.
1261. Sticky drags (click to pick up, click to drop) instead of holding the button.
1262. Time limits removed from toasts when assistive technology is on.
1263. An accessibility check for exports: caption contrast, flashing content, text size.
1264. A flashing-content (photosensitivity) scan with a softening pass.
1265. Community translations with an in-app way to suggest a better string.

## Z. Small things that add up (1266–1280)

1266. Remember the scroll position and selection on every page.
1267. Reopen the last sheet's choices next time.
1268. A recent-actions menu to repeat the last three commands.
1269. Copy a clip's link and paste it to jump there.
1270. Drag a clip out of PULSE into Finder or a chat to export it at once.
1271. Drop a still on the viewer to place it at the playhead.
1272. Double-click a number anywhere to type it.
1273. Arrow keys that nudge whatever has focus, everywhere.
1274. Paste a timecode to move the playhead.
1275. A scratchpad per project for links and ideas.
1276. A stopwatch that shows how long this session has been.
1277. A "where was I" banner on reopening a project: the last three things you did.
1278. Sensible names for everything the AI makes (no "Untitled 7").
1279. One format for every duration and date in the app.
1280. A quiet sound and a notification when a long job finishes, with the choice of neither.

## Moonshots (1281–1300)

1281. ★ A language model that plans the edit: it reads the whole transcript and the signals, writes the structure (hook, sections, payoffs, what to cut), and the existing editors carry it out.
1282. A companion for the stream PC, Windows included, that marks moments live and hands the recording to your Mac the moment the stream ends.
1283. A vision model that understands gameplay (who won the fight, what the joke on screen was) for games with no HUD templates.
1284. A model trained on your accepted and rejected clips, on your Mac, that replaces the hand-set weights.
1285. Style transfer from a creator's public videos, studied in bulk, as a private style of your own.
1286. Generated cutaways and reaction images for stories with no footage, clearly labelled.
1287. A voice model of you for fixing a flubbed word, held to recordings you approve.
1288. Lip-synced translation for a second-language channel.
1289. A virtual camera operator: a wide webcam cropped and moved like a second camera.
1290. Three-dimensional replays for games that expose demo files.
1291. Game-data overlays (damage, economy, positions) pulled from replay files.
1292. Instant highlights for esports from the game's spectator data.
1293. A shared model of what is funny, improved by opted-in creators without sharing footage.
1294. An editor's assistant that watches you edit and offers the next three actions.
1295. An interactive video export with chapters and choices for platforms that allow it.
1296. A Windows version, so the stream PC and the edit Mac run the same app.
1297. An iPad edition for reviewing and trimming with a pencil.
1298. A Vision Pro viewer: the timeline around you, the frame at full size.
1299. A marketplace where editors sell styles, templates and sound packs.
1300. A stream-to-video service on your own hardware: the stream ends, and a finished video is waiting for approval.
