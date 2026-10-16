#!/bin/bash
# Build Shotleaf for release: Release config, Apple silicon, build number = commit count,
# signed with the "Shotleaf Local Signing" certificate (scripts/make-signing-cert.sh) rather
# than ad hoc, so macOS keeps the user's permissions across updates (ADR-0069).
# Out: build/release/Shotleaf.dmg (the app and a link to Applications to drag it onto) and Shotleaf.dmg.sha256.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Shotleaf Local Signing"
security find-identity -v -p codesigning | grep -q "$IDENTITY" || { echo "no \"$IDENTITY\" certificate" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit your changes first: a release is built from a commit" >&2; exit 1; }

BUILD=$(git rev-list --count HEAD)
OUT=build/release
rm -rf "$OUT"
xcodebuild -project Shotleaf.xcodeproj -scheme Shotleaf -configuration Release \
  -derivedDataPath build/ReleaseData -destination 'generic/platform=macOS' -quiet -skipMacroValidation \
  ARCHS=arm64 CURRENT_PROJECT_VERSION="$BUILD" ENABLE_DEBUG_DYLIB=NO build
mkdir -p "$OUT"
APP="$OUT/Shotleaf.app"
cp -R build/ReleaseData/Build/Products/Release/Shotleaf.app "$APP"

# Inside out: bundled libraries first, then the app with its entitlements (no get-task-allow).
find "$APP/Contents/Frameworks" -maxdepth 1 \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null | while read -r lib; do
  codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$lib"
done
codesign --force --options runtime --timestamp=none --entitlements App/Shotleaf.entitlements -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow; then echo "get-task-allow left in" >&2; exit 1; fi
[ "$(lipo -archs "$APP/Contents/MacOS/Shotleaf")" = arm64 ] || { echo "not arm64-only" >&2; exit 1; }

VERSION=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Shotleaf.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Shotleaf -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT/Shotleaf.dmg"
rm -rf "$STAGE"
# The disk image stays unsigned: macOS blocks a quarantined image signed by a certificate it
# doesn't know before it even opens; an unsigned one opens, and only the app asks.
(cd "$OUT" && shasum -a 256 Shotleaf.dmg > Shotleaf.dmg.sha256)
echo "Shotleaf $VERSION ($BUILD): $OUT/Shotleaf.dmg ($(du -h "$OUT/Shotleaf.dmg" | cut -f1))"
cat "$OUT/Shotleaf.dmg.sha256"
