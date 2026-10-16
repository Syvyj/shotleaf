#!/bin/bash
# Pictures for the site's guide (site/assets/guide): Shotleaf's real windows with
# made-up data, in English and Ukrainian (GuideShots.swift, Debug builds only).
# Needs the "Shotleaf Local Signing" certificate, Shotleaf's Screen Recording
# permission and cwebp (brew install webp). The screen is covered for about a
# minute per language while the windows are shot: don't type meanwhile.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/GuideData/Build/Products/Debug/Shotleaf.app
xcodebuild -project Shotleaf.xcodeproj -scheme Shotleaf -configuration Debug -derivedDataPath build/GuideData \
  -quiet -skipMacroValidation ENABLE_DEBUG_DYLIB=NO CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" build
# The same signature as the installed app, so its Screen Recording permission applies.
codesign --force --options runtime --entitlements App/Shotleaf.entitlements -s "Shotleaf Local Signing" "$APP"

RAW=$(mktemp -d); trap 'rm -rf "$RAW"' EXIT
for lang in en uk; do
  open -n -W "$APP" --args --guide-shots "$RAW" -AppleLanguages "($lang)"
done

OUT=site/assets/guide
rm -rf "$OUT"; mkdir -p "$OUT"
for png in "$RAW"/*.png; do
  # Shot at 2×; 1600 px wide at most is plenty for the page.
  cwebp -quiet -q 86 -resize "$(( $(sips -g pixelWidth "$png" | awk '/pixelWidth/ {print $2}') > 1600 ? 1600 : 0 ))" 0 "$png" -o "$OUT/$(basename "${png%.png}").webp"
done
ls "$OUT" | wc -l | xargs echo "guide pictures:"
du -sh "$OUT"
