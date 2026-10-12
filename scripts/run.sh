#!/bin/bash
# Build Shotleaf, sign it with the local signing certificate, install
# it to ~/Applications and (re)start it. A stable signature + one fixed place is
# what makes macOS permissions (Accessibility, Screen Recording) stick across
# rebuilds — an ad-hoc signature changes with every build.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=build/DerivedData
# Release by default: MLX (the built-in models) is several times slower unoptimised.
CONFIG="${CONFIG:-Release}"
DEST="$HOME/Applications/Shotleaf.app"

xcodebuild -project Shotleaf.xcodeproj -scheme Shotleaf -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" -quiet -skipMacroValidation ENABLE_DEBUG_DYLIB=NO build

pkill -x Shotleaf || true
# Wait until the old copy is really gone: a new one that still sees it running
# quits itself (single-instance guard).
for _ in $(seq 50); do pgrep -x Shotleaf >/dev/null || break; sleep 0.1; done
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$BUILD_DIR/Build/Products/$CONFIG/Shotleaf.app" "$DEST"
# The local signing certificate: "Shotleaf Local Signing", or the one made
# when the app was still called APILA (switching certificates resets the
# macOS permissions, so the old one stays until Developer ID signing).
IDENTITY=""
for name in "Shotleaf Local Signing" "APILA Local Signing"; do
  if security find-identity -p codesigning | grep -q "$name"; then IDENTITY="$name"; break; fi
done
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --entitlements App/Shotleaf.entitlements -s "$IDENTITY" "$DEST"
else
  echo "warning: no local signing certificate — ad-hoc build, permissions reset on rebuild" >&2
fi
open -g "$DEST" # in the background: keep the user's focus where it is
echo "Shotleaf started from $DEST"
