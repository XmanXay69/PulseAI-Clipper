#!/usr/bin/env bash
# Builds a self-contained whisper-cli (static libraries, Metal shaders embedded, Accelerate BLAS) for
# bundling inside PULSE.app, so transcription works without Homebrew.
#
#   ./scripts/build-whisper.sh                       # → build/whisper/whisper-cli (arm64)
#   ARCHS="arm64 x86_64" ./scripts/build-whisper.sh  # universal
#
# Needs git, cmake and the Xcode command line tools.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
WHISPER_VERSION="${WHISPER_VERSION:-v1.7.6}"
ARCHS="${ARCHS:-arm64}"
SRC="$ROOT/build/whisper-src"
OUT="$ROOT/build/whisper"

if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  git clone --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggml-org/whisper.cpp "$SRC"
fi

echo "▸ Building whisper.cpp $WHISPER_VERSION for: $ARCHS"
cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="${ARCHS// /;}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_OPENMP=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_SDL2=OFF \
  -DWHISPER_CURL=OFF >/dev/null
cmake --build "$SRC/build" --config Release --target whisper-cli -j "$(sysctl -n hw.ncpu)"

mkdir -p "$OUT"
cp "$SRC/build/bin/whisper-cli" "$OUT/whisper-cli"
cp "$SRC/LICENSE" "$OUT/LICENSE-whisper.cpp.txt"
echo "▸ Linked libraries (must be system only):"
otool -L "$OUT/whisper-cli"
# Library lines are indented; the unindented ones name the file / architecture.
if otool -L "$OUT/whisper-cli" | grep -E "^[[:space:]]" | grep -vE "^[[:space:]]*(/usr/lib/|/System/Library/)"; then
  echo "✗ whisper-cli links a non-system library; it would not run on other Macs" >&2
  exit 1
fi
lipo -info "$OUT/whisper-cli"
echo "✓ $OUT/whisper-cli"
