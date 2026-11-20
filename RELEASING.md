# Releasing Shotleaf

1. Add a section to `CHANGELOG.md` and bump `MARKETING_VERSION` in the Xcode project. Commit.
2. `scripts/make-release.sh` builds `build/release/Shotleaf.dmg`, `.sha256` and `.sha256.sig`.
   It needs, in the login keychain, the "Shotleaf Local Signing" certificate and the
   "Shotleaf Update Signing" key (`scripts/make-signing-cert.sh`, ADR-0069, ADR-0070). Both must be
   backed up: a new certificate makes macOS ask for every permission again, and without the key
   in-app updates stop (apps from 0.2.1 install nothing unsigned).
3. Push `main` to both remotes (`origin` Gitea, `github`) and wait for CI.
4. `gh release create vX.Y.Z build/release/Shotleaf.dmg build/release/Shotleaf.dmg.sha256 build/release/Shotleaf.dmg.sha256.sig --title "Shotleaf X.Y.Z" --notes-file <section>`,
   then `git push origin vX.Y.Z`. Keep the three file names: the app's updater looks for them.
5. The site rebuilds itself on a published release (`.github/workflows/site.yml`); by hand:
   `cd site && python3 build.py && npx wrangler@4 deploy`.
6. Homebrew: in `~/Projects/homebrew-tap` (GitHub `Syvyj/homebrew-tap`) set `version` and `sha256` in `Casks/shotleaf.rb`, commit, push.
7. Delete `build/ReleaseData` and `build/DerivedData`: the disk is small.

The first release's full audit is in `docs/first-release-checklist-2026-10.md`.
