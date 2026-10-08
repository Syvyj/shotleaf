#!/bin/bash
# Build APILA, sign it with the local "APILA Local Signing" certificate, install
# it to ~/Applications and (re)start it. A stable signature + one fixed place is
# what makes macOS permissions (Accessibility, Screen Recording) stick across
# rebuilds — an ad-hoc signature changes with every build.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=build/DerivedData
DEST="$HOME/Applications/APILA.app"

xcodebuild -project APILA.xcodeproj -scheme APILA -configuration Debug \
  -derivedDataPath "$BUILD_DIR" -quiet ENABLE_DEBUG_DYLIB=NO build

pkill -x APILA || true
# Wait until the old copy is really gone: a new one that still sees it running
# quits itself (single-instance guard).
for _ in $(seq 50); do pgrep -x APILA >/dev/null || break; sleep 0.1; done
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$BUILD_DIR/Build/Products/Debug/APILA.app" "$DEST"
if security find-identity -p codesigning | grep -q "APILA Local Signing"; then
  codesign --force --options runtime --entitlements App/APILA.entitlements \
    -s "APILA Local Signing" "$DEST"
else
  echo "warning: 'APILA Local Signing' certificate not found — ad-hoc build, permissions reset on rebuild" >&2
fi
open "$DEST"
echo "APILA started from $DEST"
