# PULSE Dev: your own build that uses your Claude account

PULSE Dev is a copy of PULSE you build on your own Mac. It can ask the Claude Code that is already
installed and signed in there, so the features that need a language model run on your Claude plan
instead of an API key.

It is not the app that gets released, and it cannot be. Anthropic does not let other products offer a
Claude login to their users; the supported way for a released app to use Claude is an API key, which is
what the public PULSE has. A build you make for yourself, on your own Mac, running your own Claude Code,
is you using Claude Code. That is the line this stays behind. It is a reading of Anthropic's published
terms, not legal advice.

## Build it

On the Mac, in this repository's folder:

1. Have Xcode's command line tools (`xcode-select --install`).
2. Have Claude Code, signed in with your Claude account: run `claude` once in Terminal and sign in.
   The Claude desktop app's own sign-in is separate; the command needs its own.
3. Run:

   ```
   ./scripts/build-dev-app.sh --install
   ```

It builds `build/PULSE Dev.app`, asks Claude Code for one word to prove the connection works, prints
`CLAUDE-CHECK ok …` or `CLAUDE-CHECK failed: …` with the reason, and copies the app to `/Applications`.

Or hand the job to a Claude Code session on the Mac:

> Pull the branch `claude/exciting-bardeen-df149p`, run `./scripts/build-dev-app.sh --install`, and tell
> me what the CLAUDE-CHECK line says.

## Turn it on

In PULSE Dev: **Settings → AI Processing → Cloud AI provider → Claude Code (your Claude account)**.

- **Model** starts as `claude-opus-5-5`. Any full model name works, and so do `opus`, `sonnet`, `haiku`.
- **Claude Code command** is found on its own in the usual places (`~/.local/bin`, Homebrew, npm, a Node
  version manager). Fill it in only if yours is somewhere else.
- **Test Connection** asks for one word and shows which model answered.

PULSE Dev and the public PULSE share settings and projects. The public app keeps the choice but reads
it as "None (local only)".

## What uses it

| Feature | Where |
| --- | --- |
| Titles and captions for a clip | AI Clips → a clip → Generate |
| Caption translation | Captions → Translate |
| Planning a long video from its whole transcript | Edit My VOD → Plan with the model |
| What a studied video teaches | Edit Like a Reference → study a video or a link → Ask what it teaches |
| Working through a genre's videos, and merging what they teach | File → Study Library → Study |

## What is sent, and what it costs

Only text: the transcript, timecodes and PULSE's own measurements. Video and audio stay on the Mac, as
with an API key. PULSE starts `claude -p` in an empty folder with every tool, MCP server and skill
switched off, your own Claude Code instructions and hooks left out, and nothing saved afterwards. PULSE
never sees your login.

It counts against your Claude plan's usage limits, the same pool the Claude app and Claude Code draw
from. Titles and translations are small. Planning a three-hour stream sends its whole transcript and can
take several minutes. When a limit is reached, PULSE shows Claude Code's own message, which says when it
resets. An API key in the environment is removed before Claude Code starts, so nothing is billed to a
key by accident.

## How it is kept out of the public app

- Everything that starts Claude Code is inside `#if PULSE_DEV`
  (`Sources/PulseCore/AI/ClaudeCodeProvider.swift`, `Sources/PulseApp/Support/DevCheck.swift`, and the
  dev rows in Settings). Only `scripts/build-dev-app.sh` defines the flag.
- `scripts/build-app.sh`, which CI and the Release workflow use, looks for the bridge's marker in the
  finished binary and refuses to continue if it is there.
- CI builds the dev configuration on one runner, runs its tests, and checks the marker is in that build
  and not in the normal one (`DEV-GATE-OK` in the log).

## What has been checked

- Unit tests of the command line, reading the reply, every failure message, finding the command, the
  environment, running a stand-in program, a hung program being stopped, and cancelling.
- Real requests through Claude Code 2.1.325 on a Linux machine: a connection test, titles, a
  translation, an edit plan and a study of a short tutorial transcript, all answered by
  `claude-opus-5-5`.
- Not yet: a run on a Mac under a Claude Max sign-in. The first `./scripts/build-dev-app.sh` there is
  that test, and its CLAUDE-CHECK line is the result.

## If it stops working

| What you see | What to do |
| --- | --- |
| "PULSE couldn't find Claude Code on this Mac" | Install Claude Code, or give the path to `claude` in Settings |
| A message about signing in or `/login` | Run `claude` in Terminal and sign in |
| A message about a limit, with a reset time | Wait for the reset, or pick a smaller model |
| "hadn't answered after N minutes" | Try again, or a shorter recording |
| An error naming an option, after a Claude Code update | Claude Code changed its options; the list PULSE passes is in `ClaudeCodeCLI.arguments` |

Claude Code's documentation says `--bare`, which only accepts an API key, will one day be the default
for `claude -p`. If that lands, the bridge will need a flag to keep using the sign-in, or it will stop
working; the failure will be the sign-in message above.
