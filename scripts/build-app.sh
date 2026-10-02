#!/usr/bin/env bash
# Builds build/PULSE.app (release, Apple Silicon by default) and build/PULSE.zip.
#
#   ./scripts/build-app.sh                 # arm64 release
#   ARCHS="arm64 x86_64" ./scripts/build-app.sh   # universal
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
#
# If build/whisper/whisper-cli exists (./scripts/build-whisper.sh) it is bundled as the app's own
# transcriber, and build/models/ggml-*.bin as its default model (override with WHISPER_CLI / WHISPER_MODEL).
#
# Without SIGN_IDENTITY the app is ad-hoc signed, which is fine for running on your own Mac.
# ./scripts/make-dmg.sh turns the result into a drag-to-Applications disk image.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
ARCHS="${ARCHS:-arm64}"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
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
# Bundled fonts (TikTok Sans, OFL) — registered by the app at launch.
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"
WHISPER_CLI="${WHISPER_CLI:-$ROOT/build/whisper/whisper-cli}"
if [ -x "$WHISPER_CLI" ]; then
  echo "▸ Bundling whisper.cpp"
  cp "$WHISPER_CLI" "$APP/Contents/MacOS/whisper-cli"
  [ -f "$(dirname "$WHISPER_CLI")/LICENSE-whisper.cpp.txt" ] && cp "$(dirname "$WHISPER_CLI")/LICENSE-whisper.cpp.txt" "$APP/Contents/Resources/"
fi
WHISPER_MODEL="${WHISPER_MODEL:-$(ls "$ROOT"/build/models/ggml-*.bin 2>/dev/null | head -1 || true)}"
if [ -n "$WHISPER_MODEL" ] && [ -f "$WHISPER_MODEL" ]; then
  echo "▸ Bundling model $(basename "$WHISPER_MODEL")"
  cp "$WHISPER_MODEL" "$APP/Contents/Resources/"
fi
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "▸ Rendering icon"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/PULSE" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing ($SIGN_IDENTITY)"
# Inside-out: the bundled helper first, then the app (its own entitlements only).
if [ "$SIGN_IDENTITY" = "-" ]; then
  SIGN_FLAGS=(--force --sign -)
else
  SIGN_FLAGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
fi
if [ -f "$APP/Contents/MacOS/whisper-cli" ]; then
  codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/whisper-cli"
fi
codesign "${SIGN_FLAGS[@]}" --entitlements Resources/PULSE.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ Zipping"
rm -f "$ROOT/build/PULSE.zip"
ditto -c -k --keepParent "$APP" "$ROOT/build/PULSE.zip"
echo "✓ $APP"
echo "✓ $ROOT/build/PULSE.zip"
