# PULSE versions

One folder per release. Each holds the release notes (`NOTES.md`) — the release workflow uses them as the
GitHub Release description — and the installer is attached to that release on GitHub:

| Version | Notes | Download |
|---|---|---|
| **1.0.1** | [versions/1.0.1](1.0.1/NOTES.md) | [PULSE-1.0.1.dmg](https://github.com/XmanXay69/PulseAI-Clipper/releases/download/v1.0.1/PULSE-1.0.1.dmg) |
| 1.0.0 | [versions/1.0.0](1.0.0/NOTES.md) | [PULSE-1.0.0.dmg](https://github.com/XmanXay69/PulseAI-Clipper/releases/download/v1.0.0/PULSE-1.0.0.dmg) |
| 0.1.0 (preview builds) | [versions/0.1.0](0.1.0/NOTES.md) | [all releases](https://github.com/XmanXay69/PulseAI-Clipper/releases) |

The always-current download is
[releases/latest/download/PULSE.dmg](https://github.com/XmanXay69/PulseAI-Clipper/releases/latest/download/PULSE.dmg).

## Making a new version

1. Bump `VERSION` (for example `1.1.0`).
2. Add `versions/1.1.0/NOTES.md` with what changed, and a row to the table above.
3. Commit with `[release]` in the message (or run **Actions → Release**). The workflow builds the universal
   app, checks the disk image, and publishes `v1.1.0` with `PULSE.dmg` and `PULSE-1.1.0.dmg` attached.
   Rebuilds of the same version are published as `v1.1.0-build.N`.

Installers themselves aren't committed to the repository (they're ~150 MB; GitHub caps files at 100 MB),
so each version folder links to its release instead.
