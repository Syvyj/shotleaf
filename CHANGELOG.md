# Changelog

## 0.1.7

- A new setup guide. It starts by asking which tools you want, then asks only for the permissions those need, each explained where it's used. The completion model is clearly optional. Then you take your first screenshot right from the guide, and a last page shows how to use the rest.
- The guide no longer comes back at every launch for a permission that only a tool you turned off needs.
- The editor shows its main keys the first three times it opens: arrow, blur, crop and ⌘C. Close the hint and it stays gone.

## 0.1.6

- Privacy: text completion now stays off while macOS's secure input is on (password fields, `sudo` in a terminal, password managers), and in the apps listed in Settings › Clipboard › **Never in these apps**. That list now covers both the clipboard history and completion. Terminals are always left alone.
- **Report a Problem…** in the menu and in Settings opens a GitHub issue with your Shotleaf and macOS versions already filled in.
- Donations now go towards Apple's developer licence, so Shotleaf can install without the "Open Anyway" step. The site shows how much is collected.

## 0.1.5

- Fixed a crash: with text completion reading the screen, Shotleaf could quit when macOS couldn't read the text of a window.

## 0.1.4

- Privacy: text completion no longer takes what a password manager copies, a card number or an access token as a hint. Until now only the clipboard history skipped them, so the model could offer a just-copied password back as a suggestion (it never left the Mac). Both now go through one check. Thanks to the person who spotted it.

## 0.1.3

- Updates install themselves: **Update to Shotleaf…** in the menu downloads the new version, checks it against the release's checksum and Shotleaf's own signature, and restarts into it. No browser, no dragging, no "Open Anyway", and the settings and permissions stay. This works from 0.1.3 on; update to 0.1.3 itself by hand, quitting Shotleaf first.
- The disk image's window is light, so the names under the icons read on any Mac.

## 0.1.2

- Text from a screenshot: ⌘C copies all the text and closes the window, as in the screenshot editor. With part of the text selected, ⌘C copies just that and the window stays open.

## 0.1.1

- Shotleaf tells you when a new version is out: it checks GitHub at launch and once a day, and a newer release shows at the top of the menu and in Settings › General. "Check for Updates…" now answers right away. The check sends nothing about you and can be turned off in Settings › General.

## 0.1.0 — first public release

- Screenshots of an area, a window or the whole screen, with an editor: arrows, shapes, text, blur, crop, backgrounds and watermarks.
- Scrolling screenshots.
- Text from the screen, recognised on the Mac.
- Clipboard history with search, pinning, screenshots, and pasting several items at once.
- Snippets: abbreviations that expand anywhere, with dates, questions and pictures; folders can be shared or saved to Finder.
- Inline text completion from Gemma 4 E2B, running on the Mac.
- A setup guide for permissions and the completion model.
