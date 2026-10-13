#!/bin/bash
# Gathers the licences of the libraries built into Shotleaf (from the SwiftPM
# checkouts) into one text shown in Settings → About → Third-party licences.
# Run after `swift build` in ShotleafKit, whenever dependencies change.
set -euo pipefail
cd "$(dirname "$0")/../ShotleafKit/.build/checkouts"
OUT="../../Sources/AppFeature/Resources/ThirdPartyNotices.txt"
mkdir -p "$(dirname "$OUT")"
{
  echo "Shotleaf uses the following open-source software. Thank you to their authors."
  echo
  for f in EventSource/LICENSE.md mlx-swift/LICENSE mlx-swift/Source/Cmlx/mlx/LICENSE mlx-swift/Source/Cmlx/mlx-c/LICENSE \
           mlx-swift/Source/Cmlx/metal-cpp/LICENSE.txt mlx-swift/Source/Cmlx/fmt/LICENSE mlx-swift/Source/Cmlx/json/LICENSE.MIT \
           mlx-swift-lm/LICENSE mlx-swift-lm/Libraries/MLXCXGrammar/xgrammar/LICENSE swift-asn1/LICENSE.txt swift-asn1/NOTICE.txt \
           swift-collections/LICENSE.txt swift-crypto/LICENSE.txt swift-crypto/NOTICE.txt swift-huggingface/LICENSE swift-jinja/LICENSE \
           swift-numerics/LICENSE.txt swift-transformers/LICENSE yyjson/LICENSE; do
    [ -f "$f" ] || { echo "missing licence: $f (moved? update the list)" >&2; exit 1; }
    echo "================================================================================"
    echo "$(dirname "$f" | sed 's|/Source/Cmlx/| — |; s|/Libraries/MLXCXGrammar/| — |')  ($(basename "$f"))"
    echo "================================================================================"
    cat "$f"
    echo
  done
  # Not built in: downloaded from Hugging Face when text completion is turned on.
  echo "================================================================================"
  echo "Gemma 4 E2B (mlx-community/gemma-4-e2b-4bit, from google/gemma-4-e2b) — model weights"
  echo "================================================================================"
  echo "Copyright Google LLC. Licensed under the Apache License, Version 2.0 (the full text is above)."
  echo "Downloaded by Shotleaf from Hugging Face on demand; not modified and not shipped inside the app."
  echo
} > "$OUT"
echo "wrote $(wc -c < "$OUT") bytes to $OUT"
