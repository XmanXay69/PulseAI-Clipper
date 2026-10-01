#!/usr/bin/env bash
# Builds build/PULSE.app (release, Apple Silicon by default) and build/PULSE.zip.
#
#   ./scripts/build-app.sh                 # arm64 release
#   ARCHS="arm64 x86_64" ./scripts/build-app.sh   # universal
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
#
# Without SIGN_IDENTITY the app is ad-hoc signed, which is fine for running on your own Mac
# (right-click → Open the first time if Gatekeeper complains).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
ARCHS="${ARCHS:-arm64}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="$ROOT/build/PULSE.app"

echo "▸ Building PULSE $VERSION ($BUILD_NUMBER) for: $ARCHS"
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done
swift build -c release --product PULSE "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release --product PULSE "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "▸ Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PULSE" "$APP/Contents/MacOS/PULSE"
# SwiftPM resource bundles (if any target adds resources later).
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;
# On-device models (speaker embeddings) and their licenses.
cp Resources/Models/* "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "▸ Rendering icon"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/PULSE" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - --entitlements Resources/PULSE.entitlements "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements Resources/PULSE.entitlements "$APP"
fi
codesign --verify --verbose=2 "$APP"

echo "▸ Zipping"
rm -f "$ROOT/build/PULSE.zip"
ditto -c -k --keepParent "$APP" "$ROOT/build/PULSE.zip"
echo "✓ $APP"
echo "✓ $ROOT/build/PULSE.zip"
