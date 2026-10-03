#!/usr/bin/env bash
# Packages build/PULSE.app into build/PULSE.dmg: open it, drag PULSE into Applications, done.
#
#   ./scripts/build-app.sh && ./scripts/make-dmg.sh
#
# Optional (for a disk image macOS opens with no warning at all — needs an Apple Developer account):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"   signs the DMG
#   NOTARY_APPLE_ID, NOTARY_PASSWORD (app-specific), NOTARY_TEAM_ID  notarizes and staples it
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/PULSE.app"
DMG="$ROOT/build/PULSE.dmg"
VOLUME="PULSE"
[ -d "$APP" ] || { echo "✗ $APP not found — run ./scripts/build-app.sh first" >&2; exit 1; }

STAGE="$ROOT/build/dmg-stage"
RW="$ROOT/build/PULSE-rw.dmg"
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/PULSE.app"
ln -s /Applications "$STAGE/Applications"

echo "▸ Rendering window background"
"$APP/Contents/MacOS/PULSE" --render-dmg-background "$ROOT/build/dmg-bg"
tiffutil -cathidpicheck "$ROOT/build/dmg-bg/background.png" "$ROOT/build/dmg-bg/background@2x.png" \
  -out "$STAGE/.background/background.tiff" >/dev/null

echo "▸ Creating disk image"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 40 ))
# hdiutil on CI runners sometimes fails with "Resource busy" — show the error and retry.
retry() {
  local n
  for n in 1 2 3 4 5; do
    if "$@"; then return 0; fi
    echo "  (attempt $n failed, retrying)"; sleep $((n * 3))
  done
  return 1
}
rm -f "$RW"
retry hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW"
ATTACH_OUT="$(retry hdiutil attach -readwrite -noverify -noautoopen "$RW")"
MOUNT_DIR="$(echo "$ATTACH_OUT" | grep -E '/Volumes/' | sed -E 's|.*(/Volumes/.*)$|\1|')"
echo "  mounted at $MOUNT_DIR"

# Window layout through Finder. Cosmetic: if Finder can't be scripted (some CI machines), the image
# still works — it just opens as a plain icon window.
DISK_NAME="$(basename "$MOUNT_DIR")"
if ! perl -e 'alarm shift; exec @ARGV' 90 osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DISK_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "PULSE.app" of container window to {160, 190}
    set position of item "Applications" of container window to {480, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
then
  echo "  (Finder layout skipped — Finder not scriptable here)"
fi
# The disk's own icon. Added after the Finder step because Finder deletes it while laying out the window.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a C "$MOUNT_DIR" 2>/dev/null || echo "  (SetFile unavailable — disk keeps the generic icon)"
chmod -Rf go-w "$MOUNT_DIR" 2>/dev/null || true
sync
for attempt in 1 2 3 4 5; do
  hdiutil detach -quiet "$MOUNT_DIR" && break
  sleep 2
  [ "$attempt" = 5 ] && hdiutil detach -force "$MOUNT_DIR"
done

echo "▸ Compressing"
retry hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"
rm -f "$RW"

if [ -n "${SIGN_IDENTITY:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "▸ Signing disk image"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
  echo "▸ Notarizing (a few minutes)"
  xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" --wait
  xcrun stapler staple "$DMG"
fi

hdiutil verify -quiet "$DMG"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
