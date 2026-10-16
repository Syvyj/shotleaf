#!/bin/bash
# The link previews (site/assets/og-en.png, og-uk.png, 1200×630): a small page in the site's
# fonts and colours with the app icon, shot by headless Chrome.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

shot() { # lang, headline, line under it
  cat > "$TMP/og.html" <<HTML
<!doctype html><meta charset="utf-8">
<link rel="stylesheet" href="file://$PWD/site/style.css">
<style>
  html, body { margin: 0; width: 1200px; height: 630px; overflow: hidden; }
  body { background: radial-gradient(560px 380px at 1010px 70px, rgba(198, 232, 107, .5), transparent 70%),
                     radial-gradient(520px 300px at -40px 660px, rgba(198, 232, 107, .28), transparent 70%), #f3f4ee;
         font-family: Geist, sans-serif; color: #0f150c; padding: 76px 90px; box-sizing: border-box; }
  img { width: 150px; height: 150px; margin: -12px 0 0 -14px; display: block; }
  .name { font-weight: 600; font-size: 26px; color: #2d4a19; margin: 14px 0 12px; }
  h1 { font-weight: 700; font-size: 64px; line-height: 1.04; letter-spacing: -.045em; margin: 0; max-width: 15em; }
  p { font-size: 25px; line-height: 1.5; color: #566151; margin: 26px 0 0; max-width: 36em; }
</style>
<img src="file://$PWD/App/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png">
<div class="name">Shotleaf</div>
<h1>$2</h1>
<p>$3</p>
HTML
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 \
    --window-size=1200,630 --virtual-time-budget=2000 --screenshot="$PWD/site/assets/og-$1.png" "file://$TMP/og.html" 2>/dev/null
}
shot en "Screenshots and clipboard history for&nbsp;Mac" "Mark up screenshots, copy text from any image, find everything you copied."
shot uk "Скріншоти та історія буфера обміну для&nbsp;Mac" "Позначайте скріншоти, копіюйте текст із будь-якого зображення, знаходьте все скопійоване."
ls -la site/assets/og-*.png
