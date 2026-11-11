# Changelog

## Unreleased

- Clipboard panel: ⌘1–⌘9 paste a row; a plain digit goes into the search (it used to paste a row when the search was empty, so a search couldn't start with a number).
- Updates: a release must be signed with Shotleaf's update key, checked before the download is even opened (from this version on).
- Snippets: your clipboard comes back as soon as the app has taken the snippet, instead of after a fixed 0.4 s (a slow app no longer pastes the old clipboard).
- Text completion runs on the model library's current interface; the suggestions are the same.

## 0.2.0

- Privacy: **Learn my style** is off until you turn it on, and it keeps nothing until the completion model is downloaded. Texts with card numbers, tokens, emails or phone numbers are never kept. (It used to be on from the start and keep texts even without the model; **Forget what I wrote** in Settings › Completion deletes what was kept.)
- Privacy: the clipboard history and **Blur private info** also recognise JWTs and API keys from AWS, GitHub, GitLab and Google.
- Privacy: a copy made in an app under **Never in these apps** is skipped even if you switch to another app right after it.
- Screenshot links: a shot over 5 MB goes as a JPEG that fits instead of failing. The link service deletes a picture when its link expires (within 15 minutes), not up to a day later.
- Screenshot links: **Delete last link** in the link menu takes the picture off the server at once, before the link expires. Works with the free service and with your own server (update `shots.py` there).
- Saving twice in the same second keeps both files ("… 2.png") instead of replacing the first.
- Snippets: a `{clipboard}` whose text contains `{cursor}` or `{?…}` is pasted as it is.
- "Save at 1x" with **After a screenshot: Save** uses the scale of the screen the shot came from.
- Text over 1 MB isn't kept in the clipboard history, and so doesn't slow every copy down.
- Several copies in a row are written to the history file once, not once each.
- The completion model leaves memory after 10 minutes without use (about 2 GB back).
- Closed snippet and watermark windows and a long editing session use less memory.
- If a picture for the clipboard history or the recent screenshots can't be written (disk full), Shotleaf says so.
- Updates: a release tagged with a capital V is recognised.

## 0.1.9

- Settings, the setup guide and the one-time ask now say donations support the author's work on Shotleaf and other apps (there's no separate goal for Apple's developer licence any more).
- Clipboard: right-click an entry for paste, plain text, copy, pin, save as snippet, actions and delete.
- Clipboard: drag an entry onto **Snippets** to open them, then drop it on a folder to save it there. Entries can also be dragged into other apps.
- The **Snippets** button's tip is no longer cut off at the panel's edge.
- Editor: with **Blur** picked, **Blur private info** finds faces, emails, phone numbers, card numbers and tokens on the screenshot and blurs them in one step (one ⌘Z undoes it). It runs on your Mac.
- Editor: a **Magnifier** (with the arrow, box and oval, key L): a circle that shows what's under it twice as big. Blurred parts stay blurred in it.
- Editor: **⌘V** pastes a picture from the clipboard on top of the shot. Move it, or drag a corner to resize it (it keeps its shape).
- Finder: right-click any picture › **Open With › Shotleaf** to mark it up in the editor. Shotleaf never becomes the default app for pictures.
- **Combine Images…** in the menu: pick two or more pictures and they open in the editor as one, laid out in rows with a gap.
- Save as: **JPEG under 1 MB / 500 KB / 200 KB** for mail and chats: the best quality that fits, and a smaller picture only when it has to be.
- Snippets: an abbreviation always starts with **;** (or another symbol). A bare word like `mail` used to go off in the middle of ordinary typing ("mail", "mailbox", "e-mail"); now the editor puts the ; in front as you type, and existing ones get it too (`mail` → `;mail`).
- Memory: a closed screenshot window no longer stays in memory with its picture. After a day of screenshots Shotleaf could grow past 1.5 GB; now it stays near what it uses at launch (about 50 MB).

## 0.1.8

- Setup guide: after your first screenshot, closing the editor brings the guide back to the front. It used to end up behind every other window.
- The guide's last page asks for support with a proper card and button, and says what donations are for.

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
