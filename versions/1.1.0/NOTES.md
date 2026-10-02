## PULSE 1.1.0

### New
- **Teach it your taste** — 👍 / 👎 on any clip (or moment in the storyboard). PULSE learns which ingredients
  you actually like — hook, energy, laughs, reactions, story, and tags like Funny or Hype — and re-ranks clips
  and Edit My VOD's picks with it (up to ±25 points once it has a few ratings). Settings → AI Features shows
  what it learned.
- **Chat replay as a signal** — drop in a Twitch or YouTube chat replay (TwitchDownloader JSON, chat-downloader
  JSON/CSV, YouTube `.live_chat.json`, or a `[h:mm:ss] name: message` text log). Chat bursts and laugh/hype
  emotes (KEKW, LUL, "W", "clip it", 💀…) are shifted back for reaction delay and boost those moments. Use the
  media row menu → Chat Replay to nudge it earlier/later if the VOD was trimmed.
- **Edit My VOD storyboard** — "Choose Moments…" shows every moment PULSE considered with a thumbnail, score
  and tags. Untick, swap in alternatives, pick the hook, rate them, watch the running length against your
  10–20 min target — then build.
- **Overnight batch** (File → Overnight Batch, ⌥⌘B) — queue several VODs; for each, PULSE makes a project,
  analyzes it, builds the best shorts and the YouTube edit, and can export everything into a folder per video.
  Keeps the Mac awake and notifies you when it's done.
- **Brand kit** (Settings → Brand Kit) — logo watermark (corner, size, opacity, kept clear of the platform UI
  on shorts), intro/outro clips for YouTube edits, caption style and highlight color. Applied automatically
  to new edits, or with one click (Inspector → Brand kit → Apply).
- **Calibrate the score with your real views** (Settings → Performance) — exports remember what PULSE
  predicted; import a YouTube Studio or TikTok analytics CSV and PULSE matches videos by title, learns which
  factors actually drove your views, and re-weights the coach (after 5 matched videos of a format).
- **Picks up where it left off** — quitting mid-analysis keeps the finished steps (audio, speech-to-text,
  video); reopening the project resumes automatically.
- **Report a Problem** (Help menu, Settings → General) — bundles the app log, system info and recent crash
  reports (never your media) into a zip on your Desktop and opens a pre-filled GitHub issue.
