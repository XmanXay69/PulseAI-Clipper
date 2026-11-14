#!/usr/bin/env bash
# Builds "build/PULSE Dev.app": your own copy of PULSE that can ask the Claude Code installed and signed
# in on this Mac, so its model features (titles, translation, edit plans, studying a video) run on your
# Claude account instead of an API key. For your own Mac only; it is not the app that gets released.
# See docs/DEV-BUILD.md.
#
#   ./scripts/build-dev-app.sh             # build, then ask Claude Code for one word to prove it works
#   ./scripts/build-dev-app.sh --install   # also copy it to /Applications
#
# Needs Xcode's command line tools, and Claude Code (run "claude" once in Terminal and sign in).
set -euo pipefail

cd "$(dirname "$0")/.."
PULSE_DEV_BUILD=1 ./scripts/build-app.sh
APP="build/PULSE Dev.app"

echo "▸ Asking Claude Code for one word"
if "$APP/Contents/MacOS/PULSE" --claude-check; then
  echo "✓ Claude Code answered. In PULSE Dev, choose Settings → AI Processing → Provider → Claude Code (your Claude account)."
else
  echo "! Claude Code didn't answer; the line above says why. The app is built all the same: fix that, then"
  echo "  use Settings → AI Processing → Test Connection in PULSE Dev."
fi

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/PULSE Dev.app"
  ditto "$APP" "/Applications/PULSE Dev.app"
  echo "✓ Installed: /Applications/PULSE Dev.app"
fi
