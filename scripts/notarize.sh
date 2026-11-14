#!/usr/bin/env bash
# Sends a file to Apple's notary service, waits for the answer, and staples the ticket.
#
#   ./scripts/notarize.sh build/PULSE.dmg                    # notarize and staple the disk image
#   ./scripts/notarize.sh build/PULSE-notary.zip build/PULSE.app   # notarize the zip, staple the app in it
#
# Needs NOTARY_APPLE_ID, NOTARY_PASSWORD (app-specific) and NOTARY_TEAM_ID. When Apple says no, the reasons
# it gives are printed and the script fails: a release must not go out thinking it was notarized.
set -euo pipefail

FILE="$1"
TARGET="${2:-$1}"
: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID is not set}" "${NOTARY_PASSWORD:?NOTARY_PASSWORD is not set}" "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID is not set}"
AUTH=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")

echo "▸ Notarizing $(basename "$FILE") (a few minutes)"
answer="$(xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait --output-format json)" || { echo "$answer"; echo "::error::Sending $(basename "$FILE") to Apple's notary service failed"; exit 1; }
id="$(printf '%s' "$answer" | sed -nE 's/.*"id" *: *"([^"]+)".*/\1/p' | head -1)"
status="$(printf '%s' "$answer" | sed -nE 's/.*"status" *: *"([^"]+)".*/\1/p' | head -1)"
echo "  submission $id: $status"
if [ "$status" != "Accepted" ]; then
  echo "================ WHAT APPLE FOUND ================"
  [ -n "$id" ] && xcrun notarytool log "$id" "${AUTH[@]}" || true
  echo "::error::Apple did not notarize $(basename "$FILE") (status: ${status:-unknown}). The reasons are in the log above."
  exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "✓ $(basename "$TARGET") is notarized and carries its ticket"
