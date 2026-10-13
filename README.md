# Shotleaf

Screenshots and clipboard history for the Mac. Shotleaf lives in the menu bar:

- **Screenshots** of an area, a window or the whole screen, with an editor for arrows, text, blur, backgrounds and watermarks.
- **Scrolling screenshots**: a whole page in one image.
- **Text from the screen**: copy words from any image or app, recognised on your Mac.
- **Clipboard history** with search, pinned items and screenshots; paste several items at once.
- **Snippets**: type an abbreviation anywhere and it expands, with dates, questions and pictures.
- **Text completion** as you type, from a small model that runs on your Mac.

Website: [shotleaf.syvyj.dev](https://shotleaf.syvyj.dev)

## Requirements

macOS 15 or later on Apple silicon (M1 or newer).

## Install

1. Download `Shotleaf.zip` from [Releases](https://github.com/Syvyj/shotleaf/releases/latest), unzip it and move **Shotleaf** to **Applications**.
2. Open it. Shotleaf isn't notarised by Apple, so the first time macOS says it can't check the app. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.
3. The setup guide asks for two permissions:
   - **Screen Recording**: screenshots and text from the screen. macOS asks you to reopen Shotleaf after this one.
   - **Accessibility**: text completion, snippets and pasting from the clipboard history. Shotleaf restarts by itself once it's on.
4. Text completion needs its model, Gemma 4 E2B (about 3.6 GB). Download it from the setup guide or **Settings › Completion**. Everything else works without it.

### After an update

macOS may stop trusting the new copy with its permissions even though the switches still look on. If screenshots or pasting stop working, open **System Settings › Privacy & Security**, remove Shotleaf with **–** from **Screen Recording** and **Accessibility**, and allow it again.

## Shortcuts

| | |
|---|---|
| Screenshot | ⌘⇧2 |
| Scrolling screenshot | ⌘⇧3 |
| Text from the screen | ⌘⇧1 |
| Clipboard history | ⇧⌘V |
| Snippets | ⇧⌘B |
| Edit the last screenshot | ⌃⌥⌘E |
| Edit an image from the clipboard | ⌃⌥⌘V |

⌘⇧3 is also the macOS full-screen screenshot, and some apps use ⇧⌘V or ⇧⌘B. Change any of them in **Settings › Shortcuts**.

## Privacy

Shotleaf has no account and sends nothing anywhere. Text recognition and completion run on your Mac. The only network requests are the model download from Hugging Face (when you ask for it) and, if you set one up, uploads to your own link server (`server/shots`).

Passwords copied from password managers aren't kept in the history.

## Where your data lives

| | |
|---|---|
| Clipboard history, snippets, recent screenshots, writing style | `~/Library/Application Support/Shotleaf` |
| Settings | `~/Library/Preferences/dev.syvyj.shotleaf.plist` |
| Completion model | `~/.cache/huggingface/hub/models--mlx-community--gemma-4-e2b-4bit` |
| Saved screenshots | the folder chosen in Settings (Desktop by default) |

### Uninstall

Quit Shotleaf, then delete the app and the folders above:

```bash
rm -rf /Applications/Shotleaf.app ~/Library/Application\ Support/Shotleaf ~/.cache/huggingface/hub/models--mlx-community--gemma-4-e2b-4bit
defaults delete dev.syvyj.shotleaf
```

## Reporting a problem

Open an [issue](https://github.com/Syvyj/shotleaf/issues) or write to shotleaf@syvyj.dev. If Shotleaf crashed, attach the newest `Shotleaf-*.ips` file from `~/Library/Logs/DiagnosticReports`.

## Building from source

Needs Xcode 26 or later.

```bash
scripts/make-signing-cert.sh   # once: a local certificate, so permissions survive rebuilds
scripts/run.sh                 # build, install to ~/Applications and start
```

Tests: `cd ShotleafKit && swift test`.

The code is in the `ShotleafKit` Swift package (`Core`, `CaptureKit`, `PerceptionKit`, `SettingsKit`, `EmbeddedKit`, `AppFeature`); `App/` is the thin app target. Design decisions are in `ARCHITECTURE_DECISIONS.md`.

## Support

If Shotleaf saves you time, you can [support the author](https://shotleaf.syvyj.dev/#support).

## Licence

[GPL-3.0-or-later](LICENSE). © 2026 Oleksii Ziuzin (Syvyj). Third-party components and their licences: `ShotleafKit/Sources/AppFeature/Resources/ThirdPartyNotices.txt`.
