# PULSE — 500 ways to make it better

A working list, grounded in what the app does today (1.4.0). Numbered so items can be referred to ("do 12, 40, 88").
Grouped by area; inside each group, roughly in the order a streamer would feel them. ★ = highest impact for the
money. Items already shipped are not listed.

## A. Import & media (1–25)

1. ★ Drag a Twitch/YouTube VOD URL onto the window and have PULSE download it with the built-in TubeGrab engine.
2. ★ Import a whole folder of VODs at once and queue them for the overnight batch in one step.
3. Watch folder: anything dropped into a chosen folder is imported (and optionally analyzed) automatically.
4. Show import progress per file (probe → proxy → waveform) with a cancel button on each row.
5. Detect duplicate imports by content hash, not just path, and offer "use the existing one".
6. Relink offline media automatically by searching sibling folders and the file's original name.
7. Bulk relink: pick a folder once and reconnect every missing file inside it.
8. Remember the last import folder per project, not globally.
9. Import audio-only recordings (podcast WAVs) straight into the long-form flow with a generated waveform visual.
10. Import a separate microphone track and sync it to the VOD by audio fingerprint (the voice companion, one click).
11. Import OBS multi-track recordings and split the audio tracks into Dialogue / Game / Music lanes automatically.
12. Read chapter markers embedded in MKV/MP4 files and show them on the timeline.
13. Import Twitch chat JSON next to the VOD by drag-and-drop onto the project (chat replay signal).
14. Import a YouTube transcript (.srt/.vtt) alongside the video to skip transcription.
15. Thumbnail strip generation in the background with a visible "ready in ~30 s" state instead of blank cards.
16. Proxy generation only when the source is above 1440p or a long GOP codec; otherwise skip and say so.
17. Media panel: filter by kind, role, tag, duration, "used in timeline / unused".
18. Media panel: list view with sortable columns (name, length, size, date, role).
19. Rename media inline (double-click) and search by any part of the name.
20. Folder tree in the media panel with drag-to-move and color labels.
21. "Reveal in Finder" and "Open with…" on every media item.
22. Trash with restore for media removed from a project.
23. Show codec/bitrate/fps/channel count on hover, and warn on variable-frame-rate sources.
24. Convert variable-frame-rate screen recordings to constant on import (optional) to prevent drift.
25. Import presets: "Twitch VOD", "OBS recording", "Podcast", each with the right roles and sync behaviour.

## B. Analysis & finding the moments (26–55)

26. ★ Chat-spike-aware moment finding by default when a chat log is present (laugh emotes, "CLIP IT", spam bursts).
27. ★ Kill/death/win detection for popular games from on-screen HUD cues (kill feed, "Victory", elimination banners).
28. Detect the streamer's own laughter vs. others' and weight it higher.
29. Scream / shout detection as its own signal (not just loudness), tuned to not fire on game explosions.
30. Silence-vs-game-audio separation: a "nobody is talking but the game is loud" band for better dead-air cuts.
31. Scene-change-aware segment edges so cuts don't land one frame after a loading screen.
32. Loading-screen / menu / "be right back" detection to skip automatically.
33. Detect "stream starting soon" and "stream ending" screens and trim them.
34. Learn per-game profiles (which signals matter for Valorant vs. Minecraft vs. Just Chatting).
35. Faster first pass: analyze at 8 kHz with a cheap model first, show candidates in 1/10 of the time, refine later.
36. Resume analysis from the last checkpoint after a crash without redoing transcription.
37. Transcription language auto-detect per stream (bilingual streamers).
38. Transcription quality setting with time estimate shown before starting (base / small / medium).
39. Show live partial transcripts in the Transcript panel while transcribing.
40. Speaker labels from chat names when a guest is introduced ("here's Mark") — suggestion only.
41. Confidence shading on transcript words; low-confidence words are easy to spot and fix.
42. One-click "re-transcribe this stretch" after fixing a name or a game term.
43. Custom vocabulary: game names, usernames, catchphrases → boosted in transcription.
44. Profanity map editable by the user (which words to bleep/star).
45. Face tracking confidence shown in the Facecam overlay estimate; manual override of the facecam rectangle.
46. Multiple facecam positions over a long stream (the overlay moves between segments) tracked separately.
47. Detect when the facecam is hidden (full-screen game) and disable punch-ins there.
48. Energy curve on the timeline ruler (excitement over time) as a toggleable strip.
49. "Why this moment?" popover: the signals that scored it (laughter 0.8, chat spike, loudness…).
50. Moment potential explained in plain words in the AI Clips card ("big laugh + chat spike").
51. Taste learning shown transparently: a page listing what PULSE learned from 👍/👎 and a reset button.
52. Negative examples: mark a moment as "never" and similar moments are demoted next time.
53. Per-project overrides of the aggressiveness slider with a live count of candidates.
54. Run analysis with the Mac asleep prevented (optional caffeinate-style assertion) and resume after sleep.
55. Analysis benchmark on first run to set realistic time estimates per Mac.

## C. AI Clips & shorts (56–85)

56. ★ Vertical reframe that follows the action (ball / crosshair / HUD) in gameplay, not just the face.
57. ★ Split layouts that match the game: facecam on top for shooters, side-by-side for chatting.
58. Clip length presets per platform with their real limits (Shorts 60 s, TikTok 3 min, Reels 90 s).
59. Hook-first ordering: start the short on the payoff line, then show the setup ("but first…").
60. Auto title with 3 alternatives and a "more like this one" button.
61. Caption style preview per card before opening the editor.
62. Batch "Edit all like the first one": apply the layout/caption decisions of one clip to the rest.
63. Bulk rating with keyboard (J = 👎, K = 👍, arrows to move).
64. "Make it 20 % shorter" button that trims setup and tail by intelligence, not fixed seconds.
65. Combine two moments into one short (a callback joke) by multi-select → Merge.
66. Series detection: moments that reference each other (a running bit) get a "Part 1/2" tag.
67. Platform preview: how the short looks with TikTok's / Shorts' UI overlays, scrollable.
68. Safe-area violations flagged on the card ("caption under the TikTok caption area").
69. Shorts from a long-form edit: pick the top 3 moments of the YouTube edit as shorts in one click.
70. Clip "cover frame" picker for the first frame (what people see before it plays).
71. Comment-bait ending suggestions ("tell me in the comments") as optional text cards.
72. Auto hashtags from the transcript and game detection, editable.
73. Duplicate protection: warn when two shorts share > 50 % of the same stretch.
74. Export queue grouping: one folder per stream with the short's title as the file name.
75. Burn-in captions or sidecar .srt chosen per platform.
76. Short-form end card with a follow CTA, branded by the Brand Kit.
77. Sound effects on the hook word (whoosh/ding) as a per-short toggle.
78. Vertical "cinematic bars" option for gameplay that can't be cropped (top/bottom blur).
79. Blurred background fill from the same frame for 16:9 sources (standard on TikTok).
80. Speed ramp on the payoff (0.9× into the hit, 1.1× out) as a style option.
81. Motion-tracked emoji/sticker pinned to the face for reactions (opt-in, tasteful).
82. "Remove silence" per short with a sensitivity slider and live length readout.
83. One-click "A/B": generate two versions (different hook / caption style) side by side.
84. Share-ready sheet: title, description, hashtags copied with one button per platform.
85. Keep rejected clips in a "Maybe later" tray rather than deleting.

## D. Edit My VOD (long-form) (86–125)

86. ★ Story outline before building: PULSE proposes 3–5 chapters with names and lets you reorder them.
87. ★ "What to cut" transparency: a list of every removed stretch with reason and a restore toggle.
88. Length slider with a live preview of which sections survive as you drag it.
89. Hook variants: show 3 candidate hooks with playback and let you pick.
90. Cold open with a quick "what happened" title card before the hook (optional).
91. Chapter title lower-thirds at each chapter start, styled by the Brand Kit (opt-in).
92. Progress bar overlay for long videos (thin bar at the bottom) as a style option.
93. Timestamps for the YouTube description also include the hook and the end screen.
94. Auto-generate the YouTube title + description from the chapters, with 3 options.
95. "Tighten" pass: remove ums/ahs and false starts (filler removal already exists for shorts — bring it here).
96. Pause shortening instead of cutting: speed up 2–4 s pauses to 1.5× instead of jump cutting them.
97. Respect sentence boundaries by default (speaker-aware) once it's proven on real streams.
98. Reaction shots: when a friend talks, cut to the webcam (multicam-like) if a second feed exists.
99. End screen shows the project's actual next video thumbnail if the Thumbnail Studio has one.
100. Music per chapter chosen by the chapter's mood (fight → driving, story → ambient), not by whole-stream tags.
101. Music crossfades between chapters instead of fade out/in.
102. Music tempo matched to pacing (faster beds under high cut rates).
103. Memes: a user-editable meme list (text, color, tilt, sound) with on/off per meme.
104. Memes shown as thumbnails in the Extras question so you know what you're getting.
105. Sound effects library picker per effect kind (which whoosh, which boom).
106. "Less busy" / "More busy" buttons after the build that re-run only the effect passes.
107. Edit report as a readable page (what was cut, why, how many effects) with jump links to the timeline.
108. Side-by-side before/after of a cut stretch in the storyboard preview.
109. Storyboard: drag to reorder sections (non-chronological storytelling).
110. Storyboard: "add a moment here" from the transcript search.
111. Storyboard: keyboard navigation (space to preview, enter to keep, delete to drop).
112. Storyboard thumbnails as short looping previews on hover.
113. Chapter balance warning: one chapter is 6 minutes, the rest 1 minute each.
114. Pacing graph of the final edit (cuts per minute over time) with a target band.
115. Re-run with the same answers ("Edit again") after changing a setting, keeping the manual edits where possible.
116. Keep manual edits across re-runs: the second build merges into the same timeline instead of making a new one.
117. "Make it 10 % shorter/longer" after the build.
118. Versions: every Edit My VOD run saved as a named version you can switch between.
119. Promote a section to a short directly from the long-form timeline.
120. Smart intro: skip "mic check" and "can you hear me" openings automatically.
121. Outro detection: cut "raid / see you tomorrow" tails unless the user wants them.
122. Dead-air cut sensitivity slider with a live count of seconds removed.
123. Hard-floor rule: never cut inside a word; verify after every pass and auto-repair.
124. Hook title text from the transcript punchline rather than a generic title when confidence is high.
125. Title cards pick phrases from the actual transcript ("THE 1v4") when possible.

## E. Extras & ask-first (126–140)

126. ★ Per-extra preview GIF/thumbnail in the question sheet so the choice is visual, not textual.
127. Extras presets: "Gaming", "Just Chatting", "Podcast" that tick sensible sets.
128. "Ask me once per project" option while keeping ask-first as the default.
129. Show the estimated extra time next to each extra (B-roll +1 min, beat sync +10 s).
130. Show which extras can't apply to this video (no facecam → facecam punch-ins greyed, with the reason).
131. B-roll: choose the source (YouTube Creative Commons / my own folder / both).
132. B-roll: a review tray after the build — swap or remove each cutaway with a thumbnail.
133. B-roll: avoid clips already used in the last N videos.
134. B-roll: download in parallel and continue the build while downloads finish (place when ready).
135. Beat sync: show the detected BPM per bed and allow "half-time / double-time" correction.
136. Replays: choose the slow-mo speed (0.5× / 0.35×) and the tag text.
137. Replays: optional "REPLAY" sting sound and a different grade (slightly desaturated) toggle.
138. Title cards: user-editable phrase list with per-mood sets.
139. Facecam punch-ins: pick the hold time and how many per video.
140. Loudness check: show the measured curve (short-term loudness over time) not just one number.

## F. Timeline editing (141–185)

141. ★ Clip thumbnails on video clips (filmstrip) that update with zoom level.
142. ★ Trim handles with a live two-up preview (frame before / after the cut) while dragging.
143. Ripple / roll / slip / slide trim modes with keyboard modifiers and on-screen hints.
144. Magnetic snapping to markers, clip edges, playhead and beat grid, with visible snap lines.
145. Razor at playhead across all tracks (⌘B) and razor-all-selected.
146. Blade tool previews the cut line under the mouse before clicking.
147. Multi-select with marquee and shift-click ranges; group/ungroup.
148. Track-level lock, mute, solo, hide, height presets (small / medium / large / waveform-only).
149. Track reordering by drag; track rename inline; track color.
150. Audio waveform rendering per clip with gain applied (louder clip → taller wave).
151. Clip gain line (rubber band) drawn on audio clips, drag to adjust, ⌥-click to add a keyframe.
152. Keyframe editor lane under a clip (position, zoom, opacity) with bezier handles.
153. Zoom to fit / zoom to selection / zoom to playhead shortcuts.
154. Timeline minimap (overview bar) with the viewport rectangle.
155. Nudge clips by frame (, and .) and by 10 frames (⇧, ⇧.).
156. Playhead follows while scrubbing the audio (audio scrub on/off).
157. JKL shuttle with speed display (–4× … 4×).
158. In/out range on the timeline (I/O) for range export, range render, and loop playback.
159. Loop a selection (⌥L) for caption and audio tuning.
160. Markers with colors, notes and a markers list panel (jump, rename, delete).
161. "To-do" markers that show up in the edit check.
162. Gap-close shortcut (delete gap) and "remove all gaps".
163. Insert vs. overwrite toggle visible in the toolbar with a highlight.
164. Replace-clip: drop a media item onto a clip to replace it, keeping timing.
165. Paste attributes (transform, color, audio) onto other clips.
166. Compound clip badge with "open inside / flatten" buttons on hover.
167. Transition handles: drag the edge of a transition to change its length.
168. Transition presets and a default transition (⌘T applies it to the selected edit).
169. Audio crossfade shapes (equal power / linear) with a visible curve.
170. Per-clip speed with a small ramp editor (ease in/out) and pitch preservation toggle.
171. Freeze frame at playhead (⇧F).
172. Reverse clip.
173. Split-screen (link) indicator between V1 and A1 pieces; alt-click to unlink one piece.
174. Timeline search: find a clip by name or a word spoken (jumps the playhead).
175. Undo history panel with named steps and "jump back to".
176. Auto-scroll modes while playing (page / smooth / off).
177. Clip color labels and a filter ("show only music").
178. Lock the playhead to the viewer frame when stepping frames (no drift at 29.97).
179. Timeline duration readout and remaining time to the target in the toolbar.
180. Display frames vs. seconds vs. timecode with drop-frame when needed.
181. Keyboard-only editing mode (every action reachable without the mouse) and a shortcut cheat sheet (?).
182. High-density mode: tighter track heights for 4-hour timelines, auto when > 300 clips.
183. Background rendering of effects-heavy regions, shown as a green/red bar on the ruler.
184. Nested timeline navigation breadcrumb when inside a compound.
185. Timeline snapshots ("checkpoint") you can name and revert to.

## G. Viewer & playback (186–205)

186. ★ Frame-accurate stepping with the actual frame displayed (no "nearest keyframe" jumps).
187. ★ Playback quality switch (full / half / quarter) that auto-drops under load and shows it.
188. Letterboxed monitor with a clean black surround and true 1:1 pixel preview mode.
189. Safe-area overlays per platform (TikTok, Shorts, Reels, YouTube) with toggles in the viewer.
190. Grid, center lines and thirds overlays.
191. On-canvas transform handles with rotation and corner scaling; ⇧ to constrain.
192. Direct crop on the canvas (drag the crop rectangle) for the zoom/pan properties.
193. Compare mode: wipe between current and the cached "before" (A/B grade, before/after enhance).
194. Audio meters next to the viewer with peak hold and clipping indicator.
195. Full-screen playback (⇧⌘F) with transport on hover.
196. Picture-in-picture viewer while working in Captions or AI Clips.
197. Caption preview exactly as burned in (same renderer as export) — already true; show a "match" badge.
198. Scrub sound with a subtle tick per frame (optional).
199. Mark in/out while playing with I/O keys and see the range on the ruler.
200. Transport bar timecode editable (type a time, press return).
201. Loop range playback button next to the loop toggle.
202. Viewer zoom (fit / 50 / 100 / 200) with pan by space-drag.
203. Display color management: tag the preview as sRGB vs. Rec.709 and warn on HDR sources.
204. Freeze the viewer while the timeline rebuilds (no black flash) — show the last frame dimmed.
205. Second-window viewer for a second monitor.

## H. Inspector & effects (206–230)

206. ★ Reset-per-property buttons and "reset section" with a short undo toast.
207. Sliders with precise text entry, scrub-with-drag on the number, and ⌥ for fine steps.
208. Keyframe buttons per property show the three states (none / at keyframe / between).
209. Keyframe navigation (previous / next keyframe) per property.
210. Show "AI" badge on AI-set values with a one-click "make mine" (strip the AI flag).
211. Animated property graphs inline (tiny sparkline of the curve).
212. Effects stack with drag reorder, per-effect bypass and presets.
213. Blur, sharpen, vignette, glow, chromatic edge, film grain as simple effects.
214. Text: shadow/outline/background each with their own section and live preview chip.
215. Text: font picker with previews and "recently used"; TikTok Sans, Inter, Montserrat, bundled.
216. Text: letter animations (per word pop) in addition to whole-block animations.
217. Text templates (lower third, callout, meme) with saved styles.
218. Shape layers (rectangle, arrow, circle highlight) for pointing at things.
219. Image overlays with drop shadow and masks (rounded, circle).
220. Mask/crop with feather for the facecam cutout (circle facecam like TikTok duets).
221. Chroma key for green-screen facecams and B-roll.
222. Auto-reframe a single clip from the inspector (not only via AI tools).
223. Copy/paste a single section (Transform only) between clips.
224. Inspector search (type "opac" to jump to Opacity).
225. Multi-clip editing: change one value on 10 selected clips at once.
226. Property "match" (set to the same as the previous clip).
227. Lock aspect while scaling; numeric aspect readout.
228. Inspector remembers the collapsed state per section.
229. Hover tooltips with the keyboard shortcut and a one-line explanation for every control.
230. "Why is this here?" on AI-generated clips (from which pass: polish / extra / meme).

## I. Captions (231–260)

231. ★ Word-level editing by typing straight into the caption on the viewer.
232. ★ Karaoke highlight styles (current word colored / boxed / bounced) with 6 presets.
233. Caption templates gallery with animated previews (not static chips).
234. Font size auto-fit to the safe area; never clip at the edge.
235. Max-lines and max-chars-per-line controls with live preview.
236. Per-speaker colors on by default for 2+ speakers with the speaker's name as a tag.
237. Emoji auto-insert on laughter/scream words (optional, tasteful set).
238. Keyword emphasis learns from your edits (words you bold get bolded later).
239. Punctuation and casing cleanup options (sentence case, strip filler words).
240. Caption timing offset slider (±200 ms) for whole tracks.
241. Shift all captions after a point (ripple timing) when you re-cut.
242. Spell-check against a user dictionary and game-name list.
243. Censor styles (★★★★, bleep, mute) per word with one click.
244. "Hide caption while a title card is on screen" automatic rule.
245. Caption position presets per platform (above the TikTok caption zone, etc.).
246. Export captions as .srt/.vtt/.ass with styling where supported.
247. Import external captions and re-time them to the cut.
248. Translate captions (local model) and keep both tracks.
249. Caption preview thumbnails per style in the AI Clips card.
250. Find & replace across captions (usernames, game terms).
251. Caption "readability score" (words per second) with a warning band.
252. Speaker labels as lower-third chips instead of in-line names.
253. Caption background blur (frosted) instead of solid box, as a style.
254. Text-shadow intensity presets (none / soft / hard) that look right on any background.
255. Auto line breaks at phrase boundaries (not mid-phrase).
256. Keyboard editing: tab to next word, enter to split a line, ⌫ to merge.
257. Audio scrub while editing a word (hear the word).
258. "Rebuild captions" after re-transcription keeps manual fixes where the word still exists.
259. Caption style sync: change the style once and apply to every short in the project.
260. Caption performance: cache rendered words so a 20-minute edit scrolls without hitches.

## J. Audio (261–290)

261. ★ Dialogue leveling preview before committing (listen to 10 s processed vs. raw).
262. ★ Loudness meter in the viewer (momentary / short-term / integrated) with target band.
263. Noise profile learned from a selected "silence" region (classic reduction gets a profile).
264. De-esser and plosive reducer in the enhance chain.
265. Voice EQ presets (warm / clear / radio) with before/after.
266. Auto-gain per speaker in a conversation so guests match the host.
267. Game audio vs. voice balance slider when the VOD has separate tracks.
268. Music auto-duck sensitivity and release time controls (not just dB).
269. Sidechain visualization: show the duck curve on the music clip.
270. Clip volume keyframes drawn on the clip; alt-drag to draw a curve.
271. Pan automation for left/right facecam positions (subtle).
272. Stereo → mono mic detection ("your mic is only on the left channel") with a one-click fix.
273. Audio gaps at cuts filled with room tone from the clip itself.
274. Clicks and pops detector with automatic fades (the cut-fade pass extended to user cuts).
275. Hum removal (50/60 Hz) with harmonics.
276. Voice isolation strength preview strip (0 / 50 / 100 %) on hover.
277. Bleep sound choice and a "mute instead of bleep" option.
278. Audio-only export of the edit (podcast version).
279. Normalize to a chosen target (−14 / −16 / −18 LUFS) in Export, not only check.
280. True-peak limiter at export with a readout of how much it worked.
281. Per-track meters in the timeline header.
282. Solo-in-place (hear this track with its effects) vs. raw solo.
283. Headphone/speaker calibration note in Settings (don't mix on laptop speakers warning).
284. Sound effects "humanize": random ±5 % pitch/volume so repeated whooshes don't sound copy-pasted.
285. Music library "energy" tag and a search ("calm", "driving", "sad").
286. Preview any library track from the Sounds panel with a scrubber and BPM shown.
287. Beat grid drawn on music clips (tick marks) when beat sync is on.
288. "Drop the music here" marker you place yourself.
289. Render the enhance chain progressively in playback priority order (what's under the playhead first).
290. Audio render cache size shown in Settings → Files with a clear button.

## K. Music & sound library (291–305)

291. ★ Bigger Creative Commons search with mood + BPM filters and a license line per track.
292. Favorite tracks and "never again" tracks.
293. Track preview waveform + "where does the drop happen" marker.
294. Loop points detection so a 90 s track tiles without a seam.
295. Stems: when a track has an instrumental version, prefer it under talking.
296. Per-project music volume default (some streamers want it louder).
297. Local music folder import (your own licensed tracks) into the same picker.
298. SFX packs: whoosh/boom/sting families you can switch wholesale.
299. Attribution block copied to the clipboard with one button in the export sheet.
300. Offline mode indicator in the picker ("using your library").
301. Smarter dedup: the same track under two names.
302. Download retries with resume for flaky connections.
303. Background pre-download of 5 tracks per mood when idle so edits never wait.
304. Show the YouTube page for a track (verify the license yourself) from the clip's inspector.
305. Sound effect pitch/speed variations generated from one sample.

## L. Color (306–317)

306. ★ One-click looks (Clean, Punchy, Film, Cold, Warm) with intensity, matched to gameplay vs. camera.
307. Auto white balance for the facecam only (not the game).
308. Facecam skin-tone protection when saturating.
309. LUT import (.cube) with intensity; LUT gallery with thumbnails.
310. Scopes: waveform and vectorscope in a small panel.
311. Match grade between two clips (the webcam from two days).
312. Highlight/shadow recovery sliders.
313. Vignette with center control.
314. Sharpening that respects the proxy (apply at export only).
315. Grain with size and amount.
316. Per-clip "grade off" toggle for comparing.
317. Save and apply grades as presets.

## M. Multicam & recording (318–332)

318. ★ Record with a countdown, a hotkey to mark "clip it" while live, and markers that survive into analysis.
319. Recording presets (1080p60 game + 720p30 cam + 48 kHz mic) with a disk-space estimate.
320. Separate audio tracks on recording (mic / desktop / game) by default.
321. Background recording status in the menu bar with elapsed time.
322. Auto-split recordings every N GB with seamless joins.
323. Live meters while recording with clipping warnings.
324. Camera preview with a face-centering guide before recording.
325. Multicam: sync by timecode when present, audio otherwise, show the confidence.
326. Multicam: color-matched angles automatically.
327. Multicam: switch on the beat / on speaker change with a sensitivity slider.
328. Multicam: picture-in-picture angle as a style (small cam + full game).
329. Multicam: keyboard 1–9 switching while playing records cuts (already) + undo last cut (⌘Z scoped).
330. Multicam: grid templates editor (drag the dividers).
331. Record a voice-over for a section (microphone to a new track) with punch in/out.
332. Screen recording of just one window with the window title as the clip name.

## N. Export & delivery (333–360)

333. ★ Export presets with real platform specs and a "will be re-encoded by YouTube" note (bitrate guidance).
334. ★ Hardware encoder detection and a warning if software fallback will be slow.
335. Export range (in/out) and "selected clips only".
336. Export chapters as a text file alongside the video and embed them as MP4 chapter markers.
337. Export a thumbnail PNG at a chosen frame automatically.
338. Export the description (title, timestamps, credits, hashtags) as a .txt next to the video.
339. Queue reordering by drag, pause/resume, and priority.
340. Estimated time per job from the first 5 % and a total for the queue.
341. Notifications when the queue finishes (system notification with "Reveal").
342. Low-power mode: export at low priority while you keep editing.
343. Two-pass encoding option for the highest quality at a given size.
344. Target file size option (fit under 2 GB / 500 MB).
345. ProRes / DNxHR for editors who finish elsewhere.
346. Alpha channel export for overlays (ProRes 4444).
347. Audio codec and bitrate choices with a plain-language description.
348. 10-bit HEVC for HDR-safe pipelines (later).
349. Frame-rate conversion options (match source / 30 / 60) with motion-smooth vs. drop.
350. Verify after export: reopen the file, check duration and audio, show a green check.
351. Export history with "re-export with the same settings".
352. "Export all shorts" naming pattern editor ({project}-{title}-{n}).
353. Burn-in watermark (Brand Kit logo) toggle per export.
354. Metadata: title, artist, comment embedded in the file.
355. Export in the background after closing the project (queue persists).
356. Direct "Save to iCloud/Dropbox folder" presets.
357. Send to Thumbnail Studio after export automatically if a design exists.
358. Loudness fix choice remembered per project.
359. Quick export (⌘E) with the last settings and no sheet.
360. Export preview: play the first 10 s as it will be encoded (bitrate artifacts visible).

## O. Thumbnails, reference & brand (361–375)

361. ★ Thumbnail picks ranked by face expression intensity and text space.
362. Thumbnail text suggestions from the title generator.
363. Face cutout (segmentation) for the "big face" thumbnail style.
364. Three-color schemes per project from the Brand Kit.
365. Reference style: show the measured stats as a card ("4 cuts/min, 0.6 zooms/min, captions yes").
366. Reference library with thumbnails and "last used".
367. Blend two references (50/50).
368. Reference "explain": which settings it changed and why.
369. Brand Kit: lower-third template, outro template, watermark position.
370. Brand Kit: fonts bundled per kit, with fallbacks.
371. Brand Kit: per-platform variants (TikTok vs. YouTube).
372. Brand Kit preview on the sample project.
373. Intro bumper from a template (3 s animated name card).
374. Social handles auto-filled into end screens.
375. Thumbnail A/B pairs exported together.

## P. Performance & reliability (376–400)

376. ★ Cold-start under 1.5 s; defer library scans and update checks until after the first window shows.
377. ★ Memory ceiling: cap decoded frame caches by RAM and show "memory pressure" in Performance settings.
378. Background analysis uses no more than N cores (setting) so the Mac stays usable.
379. Playback never blocks the main thread: all composition builds off-main with cancellation.
380. Timeline rebuild debounce (coalesce edits within 80 ms) to keep dragging smooth.
381. Waveform generation at import in the background with low priority.
382. Proxy playback toggle in the viewer with the quality shown.
383. Crash reports with the last 200 log lines bundled in Report a Problem.
384. Automatic recovery snapshot before every AI pass.
385. Project file versioning with migration tests for every model change.
386. Large-project mode: lazy-load thumbnails, virtualized media grids (the timeline already is).
387. Disk-space watchdog before exports and analysis, with a clear "free 3 GB" message.
388. Cache cleanup assistant (what's safe to delete, how much it frees).
389. Energy-aware scheduling: pause batch work on battery below 20 %.
390. Resume downloads / analysis after sleep without restarting.
391. Dependency check on launch (whisper binary, fonts) with a fix button.
392. First-run self-test (play a 1 s composition) to catch broken GPU/driver setups early.
393. Safe mode (disable GPU compositor) from the Help menu.
394. Smoke test on every CI run with a 2-hour synthetic VOD for timing regressions.
395. Telemetry-free performance log you can send with a bug report.
396. Unit tests for every timeline edit operation with random fuzzing (no overlaps, no gaps).
397. Undo stack memory cap with coalescing.
398. Thumbnail cache keyed by file hash so moved files keep thumbnails.
399. Background jobs panel with per-job CPU/time and cancel.
400. Graceful degrade when a model is missing (Speech instead of whisper) with a banner, not a failure.

## Q. UI & design system (401–440)

401. ★ A consistent 8-pt spacing grid and a type scale (11/12/13/15/20/28) applied everywhere.
402. ★ Elevation system: three shadow levels for panels, popovers and sheets; borders only where needed.
403. ★ Timeline clip redesign: rounded 6 pt, subtle top highlight, name chip, filmstrip, waveform tint.
404. Sidebar grouped into Workspace / Create / Deliver with section headers and a collapsed icon rail.
405. Top bar as a breadcrumb (Project › Section) with the save state as a dot, not text.
406. Hero on Home with a soft gradient, two primary cards with gradient borders, actions as a tidy grid.
407. Hover and pressed states on every card and button (lift + border brighten).
408. Focus rings for keyboard navigation that match the accent.
409. Icons: one consistent SF Symbols weight (medium) and size per context.
410. Empty states with an illustration and the one action that matters.
411. Toasts stacked bottom-center with icons and an undo action where relevant.
412. Progress everywhere as thin accent bars with ETA text, never spinners alone.
413. Sheets share one header component (icon, title, subtitle) — most do; finish the rest.
414. Inspector sections with disclosure arrows, reset icons and a per-section AI badge.
415. Panel tabs (Media / Sounds / Transcript …) as a segmented strip with icons and labels on hover.
416. Timeline track headers: colored kind stripe, compact controls, height drag handle.
417. Playhead with a glow and a timecode bubble when dragging.
418. Ruler with major/minor ticks that scale cleanly and a chapter band above it.
419. Viewer chrome: a monitor frame with the clip title, resolution and format in a quiet strip.
420. Transport bar: larger play button, loop and range buttons grouped, speed readout.
421. Status pills (LOCAL / dev) moved into one quiet system indicator with a popover.
422. Search as a command palette (⌘K): actions, settings, clips, words — one field.
423. Settings as a two-level list with search and "recently changed".
424. Light theme (full) and auto-switch with the system.
425. Accent color choice (pulse pink, electric blue, lime) and AI violet constant.
426. Reduce-motion support (no bounce animations) and larger-text support.
427. Window layouts: Edit / Captions / Color / Audio / Deliver presets that resize panels (the tabs exist; make them arrange panels).
428. Save and restore panel sizes per layout and per project.
429. Detachable panels (Inspector, Transcript) into their own windows.
430. Tooltips with shortcuts on every icon button (consistent format).
431. Keyboard shortcut editor in Settings with conflict detection.
432. Onboarding as a 4-step overlay on the real UI (spotlight), not a separate sheet.
433. Contextual help ("?" chips) that open the relevant doc section in a popover.
434. Activity feed with grouping (today / yesterday) and jump-to actions.
435. Batch window as a dashboard: per-VOD progress bars and a total ETA.
436. Edit check results as a side panel with "fix" buttons per issue, not an alert.
437. AI Clips cards with a hover video preview, the potential as a ring, and a one-line "why".
438. Storyboard rows with the moment's waveform strip and the payoff marked.
439. Notification center for finished jobs with "open" actions.
440. App icon refresh and a matching DMG background.

## R. Settings, help & onboarding (441–458)

441. ★ "Set up for my stream" wizard: platform, game, facecam yes/no, mic track → sets 20 settings at once.
442. Model manager: download / delete transcription models with sizes and speed estimates.
443. Settings search.
444. Import/export settings as a file (move to a new Mac).
445. Per-project settings override panel (which settings are project-level).
446. Reset to defaults per section.
447. Diagnostics page: GPU, encoder, disk, model versions, last errors, "copy for support".
448. Changelog shown on first launch after an update (the release notes you already write).
449. Sample projects per genre (gaming, podcast, IRL) to try features.
450. Tips on the Home page that rotate (one per day) with "don't show".
451. Shortcut cheat sheet printable page.
452. Privacy page that states what leaves the Mac (nothing unless cloud AI/online music are on).
453. Cloud AI provider setup with a "test" button and cost estimate per hour of video.
454. Update channel (stable / beta) with release notes diff.
455. Report a Problem attaches the current project's anonymized structure (no media) optionally.
456. "What's using my disk" page with per-project cache sizes.
457. Language of the UI (localization scaffolding).
458. Accessibility audit: every control reachable by VoiceOver with a sensible label.

## S. Workflow & automation (459–480)

459. ★ Command palette (⌘K) with fuzzy search over actions, clips, words, settings.
460. ★ Project templates: "Twitch VOD → 3 shorts + YouTube edit" as one button with saved answers.
461. Routine: watch a folder, run the batch nightly, export to a folder, done by morning.
462. Scriptable actions (shortcuts/AppleScript): import, analyze, edit, export.
463. Shortcuts app actions for the main flows.
464. Hotkey while any app is in front to "mark a moment" into the current recording.
465. Quick look previews of exports from Finder with the project link.
466. "Open in PULSE" Finder service for media files.
467. Clipboard: paste a YouTube URL anywhere to import.
468. Multi-window projects (two projects side by side) with drag-and-drop between them.
469. Project duplication with/without media and "trim project to used media".
470. Archive project (zip with media) and restore.
471. Collaboration lite: export a project review page (HTML) with the edit and comments.
472. Version compare: diff two timelines (what changed).
473. Smart folders in Projects (by game, by date, by status).
474. Project status board (Editing / Ready / Exported / Posted) with drag between columns.
475. Deadline reminders on projects.
476. Per-project notes panel with checklists.
477. Time tracking per project (how long edits take, trending down).
478. Statistics page: shorts made, minutes edited, dead air removed, hours saved.
479. Keyboard macro recorder for repetitive edits.
480. AppleScript/CLI export of the timeline as FCPXML / OTIO for Resolve/Premiere round trips.

## T. Moonshots (481–500)

481. Live "clip while streaming": PULSE watches the recording as it grows and proposes shorts in real time.
482. Direct publish to YouTube/TikTok with scheduling (OAuth, optional).
483. Analytics import (YouTube Studio CSV) that calibrates the coach automatically.
484. Voice clone for fixing a flubbed word (local model, consent-gated).
485. Generative B-roll (image → motion) for stories with no footage.
486. Auto-translate + dub for a second language channel.
487. Face-aware reframing that keeps two people in frame during conversations.
488. Game event API hooks (Riot, Steam) for exact kill timestamps.
489. "Edit like my last 10 videos" — a style learned from your own uploads.
490. Audience retention curve prediction before upload with a heat map on the timeline.
491. Co-stream editing: two VODs (yours + a friend's POV) synced and cut as multicam.
492. Highlight reels across a month of streams in one click.
493. Automatic chapter art (a frame + title) for the description.
494. Mobile companion to review and approve a cut from a phone.
495. Plugin API for custom effects and signals.
496. Community meme/SFX packs with ratings.
497. Hardware control surface support (Stream Deck buttons for mark/clip/export).
498. Local LLM "editor assistant" chat: "make the hook punchier", "cut the intro" → applies to the timeline.
499. Edit-by-transcript document mode (strike words to cut, like a doc).
500. A fully keyboard-driven "speed editor" mode: J/K/L, mark, cut, next — a whole VOD in minutes.
