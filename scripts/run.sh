#!/bin/bash
# Build APILA, install it to ~/Applications (one fixed place, so macOS permissions
# attach to one app) and (re)start it.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=build/DerivedData
DEST="$HOME/Applications/APILA.app"

xcodebuild -project APILA.xcodeproj -scheme APILA -configuration Debug \
  -derivedDataPath "$BUILD_DIR" -quiet build

pkill -x APILA || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$BUILD_DIR/Build/Products/Debug/APILA.app" "$DEST"
open "$DEST"
echo "APILA started from $DEST"
