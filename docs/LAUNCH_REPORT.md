# Beacon launch report

Beacon 1.0.0 (build 2) is public as of 2026-10-17. It is a macOS menu bar app for GitHub. It shows unread activity, pull requests that need a review, and your own open pull requests. The binary is Developer ID signed, notarized, and stapled.

People install it from the site, from the GitHub release, or with Homebrew:

```sh
brew install --cask avivhdr/tap/beacon
```

## Links

| | |
|---|---|
| Site | https://beacon-for-github.vercel.app |
| Repository | https://github.com/Avivhdr/beacon |
| Release | https://github.com/Avivhdr/beacon/releases/tag/v1.0.0 |
| Update feed | https://beacon-for-github.vercel.app/appcast.xml |
| Disk image | https://github.com/Avivhdr/beacon/releases/latest/download/Beacon.dmg |
| Homebrew tap | https://github.com/Avivhdr/homebrew-tap |
| CI | https://github.com/Avivhdr/beacon/actions/workflows/ci.yml |

## Permanent values

Do not change these. A new feed address or a new key leaves every installed copy unable to update.

- `SUFeedURL`: `https://beacon-for-github.vercel.app/appcast.xml`
- `SUPublicEDKey`: `GaHhzbvJpIsMlj66m8Ov0ZBep1fBFZsjRp8fM1rXHKI=`
- Notary profile: `focuspill-notary`
- The Sparkle private key stays in the login Keychain under account `beacon`. Aviv keeps the backup in Bitwarden. The key is not in this repository and not in this report.

## How to cut the next release

On a checkout of `main` at `/Users/avivhadar/repos/beacon`, bump `MARKETING_VERSION` in `project.yml`. Leave `CURRENT_PROJECT_VERSION` alone. The release script increments it. Then run `/release`. Do not change `SUFeedURL` or `SUPublicEDKey`.

## Follow-ups

- Store the exported Sparkle private key in Bitwarden, then delete the export from this Mac.

The social preview is set. GitHub has no API for that image, so it was uploaded in the repository settings. The card is `web/og.png` (1200×630). GitHub asks for 1280×640 for the sharpest card. 1200×630 is above the 640×320 minimum, and the settings page shows this image.

The cask now says `depends_on macos: :sonoma`. That is the same rule as before: macOS Sonoma or newer. Homebrew no longer warns about the old string form.

The rest of this file is the running log. Each phase lists what changed, how it was checked, and any decision made on the way. The plan is [LAUNCH_PLAN.md](LAUNCH_PLAN.md).

## Phase 0: bootstrap this Mac

Checked on 2026-10-16.

### Tools

All of these were already installed. Nothing was installed in this phase.

| Tool | Result |
|---|---|
| Xcode | `xcode-select -p` → `/Applications/Xcode-26.5.0.app/Contents/Developer`. `xcodebuild -version` → Xcode 26.5 (17F42). |
| `gh` | `gh auth status` → logged in as `Avivhdr`. |
| `xcodegen` | 2.45.4 |
| `create-dmg` | 1.3.0 |
| `node` | v24.14.1 |
| Vercel CLI | 63.1.2, `vercel whoami` → `avivhdr` |

### Repo

This session is the OpenForge worktree `/Users/avivhadar/.openforge/worktrees/beacon/AVIV-705` on branch `openforge/AVIV-705`. `main` is checked out in `/Users/avivhadar/repos/beacon`, so this worktree cannot check out `main` directly. Both pointed at `32537df` (`origin/main`). Later phases commit here and fast-forward `origin/main`.

`gh repo view Avivhdr/beacon` → private, description already set, homepage empty.

### Tests

`swift test` passed: 17 tests, 0 failures.

### Launch

`./scripts/build-app.sh` built `build/Beacon.app` (ad-hoc signature, executable `GitHubNotifications`, bundle id `com.avivhadar.github-notifications`).

`open build/Beacon.app` stayed running (`pgrep -lf GitHubNotifications`).

This Mac had no Beacon config before that launch. The app created `~/.config/github-notifications/config.json` (defaults) and, after the first poll, `~/Library/Application Support/GitHubNotifications/state.json`. No old UserDefaults domain was present. Phase 1 migrates those two files.

### Credentials (for Phase 2, checked now)

- `security find-identity -v -p codesigning` lists `Developer ID Application: Aviv Hadar (8PYS6TK87H)`.
- `xcrun notarytool history --keychain-profile focuspill-notary` succeeded. Ask A is not needed.

## Phase 1: Xcode project, final identity, app icon

### What changed

- `project.yml` builds the `Beacon` app target from `Sources/Beacon` (renamed with `git mv`) and links the local `Core` package. Debug signs ad-hoc. Release signs with Developer ID Application, team `8PYS6TK87H`, Hardened Runtime, no entitlements.
- `Package.swift` exposes the `Core` library and keeps `CoreTests`. The app is no longer a SwiftPM executable.
- `Makefile` targets: `run`, `build`, `test`, `package`, `snapshots`, `icon`. `scripts/build-app.sh` is gone. `install.sh` builds Release and copies it to `/Applications/Beacon.app`. `scripts/replay.sh` uses the `Beacon` process name and the new state path.
- Bundle id `com.avivhadar.Beacon`, executable `Beacon`, config `~/.config/beacon/config.json`, state `~/Library/Application Support/Beacon/state.json`. `Migration.migrateIfNeeded()` copies the old config, state, and `hiddenPRs` / `collapsedRepos` when the new copies are missing. Old files stay.
- `Tools/generate-icon.swift` draws the ink squircle, radar rings, bearing ticks, and amber beam. PNGs live in the asset catalog. A second run produced the same `icon_128.png` hash (`7ee2d7c4cdef1b3680d9825c62fdbb2145af3c1b`).
- `--snapshot <dir>` (Debug only) writes 2x panel PNGs. `AppModel.loadPreview` and `PanelView`'s initial tab exist only in Debug.

### Checks

- `swift test` (what `make test` runs): 20 tests passed, including 3 migration tests. The original 17 still pass.
- `make build` succeeded. The built Info.plist has `CFBundleIdentifier` `com.avivhadar.Beacon`, `CFBundleExecutable` `Beacon`, `CFBundleShortVersionString` `1.0.0`, `CFBundleVersion` `1`, `LSUIElement` true, `LSMinimumSystemVersion` `14.0`, category `public.app-category.developer-tools`, and `CFBundleIconFile` `AppIcon`. The signature is ad-hoc.
- Migration on this Mac: both new files match the old ones byte for byte (`shasum -a 256`). Config hash `52c96ab2…`. State hash `e85343b7…` (0 feed items, 19 checked PRs). Old files are still in place. Neither defaults domain had `hiddenPRs` or `collapsedRepos`, so there was nothing to copy.
- `open build/Build/Products/Debug/Beacon.app` stayed running as `Beacon` (pid 64777). The config hash was unchanged after launch.
- `Beacon --snapshot` wrote eight 920×1200 PNGs into `snapshots/` (gitignored). Unread, To review, and Mine show the sample data on the right tab. Empty states show "No signal yet", "Queue empty", and "Nothing in flight".

### Decisions

- `make test` runs `swift test`, not `xcodebuild test`. The scheme `BeaconCoreTests` is there for Xcode. The fast path is the one the plan asked to keep.
- `Sources/Beacon/Info.plist` is an empty merge file until Phase 4 adds the Sparkle keys. No feed URL is baked in yet.
- `snapshots/` is gitignored. Phase 3 and Phase 5 copy the PNGs they publish.

## Phase 2: signing, notarization, DMG

Ask A was already satisfied in Phase 0. `package.sh` uses `NOTARY_PROFILE` (default `focuspill-notary`).

### What changed

- `ExportOptions.plist`: method `developer-id`, team `8PYS6TK87H`, manual Developer ID Application signing.
- `package.sh`: universal Release archive, export, notarize by polling `notarytool info`, staple, `spctl`, then a drag-to-Applications DMG with an ink background (`Tools/generate-dmg-background.swift`). The DMG is signed, notarized, and stapled. Output is `dist/Beacon-<version>.dmg`.

### Checks

`./package.sh` exited 0. App submission `27915e81-3553-4749-bcb1-bb69ee867dde`. DMG submission `fe58b78f-c231-49d7-8406-bf3f0954d472`. Both stapled.

- `lipo -archs` on the Release executable: `x86_64 arm64`.
- `xcrun stapler validate` on `dist/Beacon-1.0.0.dmg` and on `build/Build/Products/Release/Beacon.app`: "The validate action worked!"
- `spctl -a -vvv -t install dist/Beacon-1.0.0.dmg`: accepted, source `Notarized Developer ID`, origin `Developer ID Application: Aviv Hadar (8PYS6TK87H)`.
- Same `spctl` result on the app. `codesign` shows Hardened Runtime (`flags=0x10000(runtime)`), a timestamp, and `Notarization Ticket=stapled`.
- The mounted DMG contains `Beacon.app` and an `Applications` symlink.
- Quarantine: copied the app out of the DMG, set `com.apple.quarantine` to `0081;<time>;Safari;`. `spctl -a -vvv --type execute` on that copy was accepted, same origin. `open` started it. Gatekeeper translocated the bundle (the allow path) and the process stayed up. No block dialog. The test process was then quit.

## Phase 3: open source hygiene

The repository stays private. The homepage stays empty until the site exists.

### What changed

- Test fixtures and the `FiltersView` comment now use fictional names (`octo-org`, `mona`, `hubot`, `octocat`, `ci-bot`). The assertions are the same.
- `README.md` is written for someone who has not seen Beacon. It includes the three tab screenshots from the snapshot tool (`docs/screenshots/`), install steps for the DMG and `brew install --cask avivhdr/tap/beacon`, the macOS 14 and `gh auth login` requirements, the SSO note, the privacy statement, and the config reference. The Mine-tab example is `octo-org` plus an empty Private group. The website link is added in Phase 5, after the address is real.
- Added `LICENSE` (MIT, Copyright (c) 2026 Aviv Hadar), `CONTRIBUTING.md`, `SECURITY.md`, and issue forms for a bug report and a feature request. The bug form asks for the Beacon version, the macOS version, the output of `Beacon --dump`, and what happened.
- `gh repo edit` set the topics `macos`, `menubar`, `github`, `notifications`, `pull-requests`, `swiftui`. The description was already "Menu bar app for GitHub: notifications, reviews and your PRs".

### Checks

- `swift test`: 20 tests passed.
- `rg -i "collibra|koenvangeert"` on the tree, skipping build output: the only hits are `docs/LAUNCH_PLAN.md` and this report.

### History

`git log -p` contains company repository names (`collibra`, `collibra/dgc-core`) and a colleague login (`koenvangeert`), plus one other real login used as a fixture. A search for `gh[pousr]_[A-Za-z0-9]{20,}` and `github_pat_[A-Za-z0-9_]{20,}` found no token.

Those names are worth keeping out of the public history. This phase squashes the repository to one commit, `Initial public release`, and force-pushes `main`. The repository is still private. Later phases commit on top of that root.

### Decision

Ask B: the feed stays on a free `*.vercel.app` address. The host chosen in Phase 4 is `beacon-for-github.vercel.app`. No signed build ships with a placeholder feed URL.

## Phase 4: Sparkle auto-updates

### Feed address

`beacon-app.vercel.app` and `beacon.vercel.app` already serve other sites. The Vercel project `beacon-for-github` (team `aviv-hadars-projects`) received `https://beacon-for-github.vercel.app`. That is the permanent host. New installs will keep checking it.

The project had Vercel Authentication on. That would hide the feed from Sparkle, so deployment protection is off. `curl -sI https://beacon-for-github.vercel.app/appcast.xml` returned 200 with `content-type: application/xml`. The page is a placeholder until Phase 5. The channel is empty.

`SUFeedURL` is `https://beacon-for-github.vercel.app/appcast.xml`.

### What changed

- Sparkle 2.10.0. Focus Pill pins 2.9.4. 2.10.0 is the newer 2.x release, and its minimum is macOS 12, which covers Beacon's macOS 14.
- `generate_keys --account beacon` stored the private key in the login Keychain. The public key in `Sources/Beacon/Info.plist` is `GaHhzbvJpIsMlj66m8Ov0ZBep1fBFZsjRp8fM1rXHKI=`. No private-key file was written. Where to keep a backup is part of Ask E.
- Automatic checks are on. The interval is 86400 seconds.
- `Updater` starts Sparkle at launch. A scheduled find does not open a window. The status strip shows an amber "Update ready" readout. Clicking that readout, or "Check for Updates…", hides the panel, activates the app, and opens Sparkle's window.
- README and CLAUDE.md record that the feed URL and the public key are permanent.

### Checks

- The Release Info.plist has `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` true, and `SUScheduledCheckInterval` 86400. The feed URL is the real one.
- The Release binary contains the text "Check for Updates".
- Debug offer test. `defaults write com.avivhadar.Beacon SUFeedURL http://127.0.0.1:8765/appcast.xml`. The feed item was build 2, short version 1.0.1, signed with the beacon key. A scheduled check reported `offer 1.0.1 handle=false` (the strip path). A user check, Debug launch argument `--check-updates`, reported `offer 1.0.1 handle=true` (Sparkle's window). The override was deleted. `defaults read SUFeedURL` finds no key.
- The localhost test build allowed local networking so `http://127.0.0.1` could load. That key is not in the committed Info.plist, and it is not in the Release plist built from this tree.
- `swift test`: 20 passed.

## Phase 5: the website

Checked on 2026-10-16.

### Host

The Vercel project is `beacon-for-github` (`prj_y33QpldMZnPL8qerFUoKyLTBvNXF`) on team `aviv-hadars-projects`. Root directory is `web`. Framework preset is Other. Git is connected to `Avivhdr/beacon`, production branch `main`. Deployment protection stays off, so Sparkle can read the feed.

Production URL: https://beacon-for-github.vercel.app

The GitHub homepage is that URL. The repository is still private.

### What changed

`web/` is a static site: `index.html`, `styles.css`, `main.js`, an empty `appcast.xml`, a favicon, an apple touch icon, `og.png` at 1200×630, and the three panel screenshots.

The page follows `DESIGN.md`. There is no `PRODUCT.md`. The launch plan says not to stop for extra questions, so the page direction comes from `LAUNCH_PLAN.md` and `DESIGN.md`.

`.vercelignore` keeps local build folders out of a CLI deploy. `.gitignore` ignores `.env*` because `vercel link` wrote a local token file. That file is not committed.

### Checks

- Desktop (1280) and mobile (390) screenshots. The page matches the app: ink background, amber radar, uppercase readouts, hairline panel. At 390px the panel sits above the title, and the page does not scroll sideways.
- The copy button changes to "Copied".
- A Linux, iPhone, and iPad user agent hides the download and shows "Beacon is for macOS 14+." A Mac user agent shows the download.
- The skip link was one pixel into the viewport. It now sits fully above the page until it is focused.
- `.pill` sets `display`, which overrides the `hidden` attribute. `[hidden] { display: none !important; }` makes the Mac-only rule work.
- Lighthouse accessibility: 100 on `http://127.0.0.1:8766/` and 100 on the production URL.
- The design detector reported hover text `#f4a93b` on `#f4a93b`. The hover fill is an 8% amber wash on `#0c0f14`, not solid amber. Amber on ink is about 9.7:1. Lighthouse contrast checks passed, so this report leaves the color as it is.
- `curl -sI https://beacon-for-github.vercel.app/appcast.xml` returns 200 and `content-type: application/xml`. The body is an empty Sparkle channel titled Beacon.
- `curl` of `/project.yml`, `/.env.local`, and `/README.md` returns 404.

The first CLI deploy uploaded this Mac's build folders (about 7661 files). `vercel` did not apply `.gitignore` from this worktree. That deployment was removed. `.vercelignore` is in place. The push of this phase to `main` deployed from GitHub. `https://beacon-for-github-git-main-aviv-hadars-projects.vercel.app` is Ready and owns the production alias. The feed check above still passes.

### Decision

Ask B was already answered. The host is the address Phase 4 compiled into the app. No new question.

## Phase 6: release pipeline

Checked on 2026-10-16.

### What changed

- `release.sh` builds, notarizes, and writes `dist/Beacon-<version>.zip` plus `dist/appcast.xml`. A real run also publishes a GitHub release (`Beacon-<version>.zip`, `Beacon-<version>.dmg`, and the same disk image as `Beacon.dmg`), commits `project.yml` and `web/appcast.xml`, pushes `main`, checks the live feed and the download, and updates the Homebrew cask.
- `--dry-run` publishes nothing. It restores `CURRENT_PROJECT_VERSION` on the way out, including after a failure.
- `CHANGELOG.md` has the 1.0.0 notes. `generate_appcast --account beacon` embeds that section.
- `.claude/skills/release/SKILL.md` can only be started by a person.

### Checks

`./release.sh --dry-run` for 1.0.0, build 1 → 2.

- App submission `0b13bb97-6dfe-4d21-bb2f-1318169c76bc`: Accepted, stapled. `spctl` says Notarized Developer ID.
- Disk image submission `71d42d55-f779-4210-b3ce-1769e93cb478`: Accepted, stapled. `stapler validate` succeeded for the disk image and the app.
- `dist/Beacon-1.0.0.zip` has `Beacon.app` at the archive root. `dist/appcast.xml` is build 2, short version 1.0.0, enclosure length 2579891.
- `project.yml` is back to build 1. `web/appcast.xml` is still the empty channel. The dry run did not commit or publish.

### Decision

Binaries go to GitHub Releases. The feed stays on `https://beacon-for-github.vercel.app/appcast.xml`.

## Phase 7: Homebrew tap

Checked on 2026-10-16.

### What changed

`dist/homebrew-tap/Casks/beacon.rb` is ready. It is not in git, and the public tap does not exist yet. Ask D creates `Avivhdr/homebrew-tap`.

The cask installs `Beacon.app` from `Beacon-<version>.dmg`, depends on macOS Sonoma or later, sets `auto_updates true`, and removes `~/.config/beacon`, `~/Library/Application Support/Beacon`, and `~/Library/Preferences/com.avivhadar.Beacon.plist`.

The sha256 is the dry-run disk image `e405aa3320b4ba00b6a431179a180aa0869f6a05933c1f96fca259544514a650`. A real `./release.sh` replaces the version and the sha256, then pushes the tap when that directory is a git checkout.

### Decision

The tap stays local until Ask D.

## Phase 8: polish for people who aren't Aviv

Checked on 2026-10-16.

### What changed

- A missing `gh`, or a token GitHub rejects, opens a sign-in panel. It uses the radar, the two commands `brew install gh` and `gh auth login`, and a Try again pill. The status line reads SIGN IN.
- The ⋯ menu adds Open at Login (`SMAppService.mainApp`), About Beacon (the standard About panel, with the website and GitHub as credits), and Report a Bug. Report a Bug opens the bug-report issue form with the Beacon version, the macOS version, and the CPU architecture filled in.
- The Teammates note is now "Add teammates in the config when you want this category." The default Mine layer is still Open. The README Work/Private example stays.
- Beacon looks for `gh` on `PATH` first, then in `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, and `/usr/bin/gh`.

### Checks

- `swift test`: 21 passed. That includes `ghLookupUsesPathBeforeTheUsualInstallLocations`.
- `env GITHUB_TOKEN=bad build/Build/Products/Debug/Beacon.app/Contents/MacOS/Beacon --dump` printed `error: GitHub 401 on /user: Bad credentials`.
- `env -u GITHUB_TOKEN PATH=/usr/bin:/bin` with the same `--dump` still found Homebrew `gh`. The feed lines were `Teammates: 0 (Add teammates in the config when you want this category.)` and `mine/Open: 9`.
- Off-screen captures (`--snapshot-signin`) of both panels show the radar, the matching sentence, both commands in lower case, and Try again. A short `PATH` cannot hide `gh` on this Mac, because the install-path fallback is required for a Finder launch. The missing-`gh` panel uses the same sentence `TokenProvider` throws.
- `--try-login-item`: Open at Login was off. Register turned it on (`SMAppServiceStatus` raw value 1). Unregister restored it to off (raw value 0). System Settings was already open. Its process id did not change.
- `--simulate-wake` posted `NSWorkspace.didWakeNotification`. The observer called `start()` and printed `wake: polling resumed`.
- `--show-about` opened an on-screen Beacon window, 284 by 204 points. The bug URL was `https://github.com/Avivhdr/beacon/issues/new?template=bug_report.yml&beacon-version=1.0.0%20(1)&macos-version=27.0.1%20arm64`.
- `docs/screenshots/to-review.png` and `web/screenshots/to-review.png` show the new Teammates note.

### Decision

A login-item or Finder launch has a short `PATH`. The absolute `gh` fallback stays.

## Phase 9: CI

Checked on 2026-10-16.

### What changed

`.github/workflows/ci.yml` runs on every push and every pull request, on `macos-15`. The job runs `swift test`, installs XcodeGen, generates the Xcode project, and builds Debug with `CODE_SIGNING_ALLOWED=NO`. The README links the CI badge.

### Checks

Push `f16b38f` queued run [38968309744](https://github.com/Avivhdr/beacon/actions/runs/38968309744). The conclusion is success. The Test step, the XcodeGen install, project generation, and the unsigned build all succeeded.

### Decision

Signing and notarization stay on this Mac. CI does not sign the app.

## Phase 10: dry run of the whole release

Checked on 2026-10-16.

### What changed

`./release.sh --dry-run` built and signed 1.0.0 again, after the Phase 8 changes. It published nothing. `project.yml` is still build 1. `web/appcast.xml` is still the empty channel.

Debug launches can print the Sparkle result. Release builds do not. The menu item is unchanged.

### Checks

`./release.sh --dry-run` for 1.0.0, build 1 to 2. Exit 0.

- App submission `865137e6-9f6c-4e43-9395-31bce95b737b`: Accepted, stapled. `spctl` says Notarized Developer ID.
- Disk image submission `28b5382d-fb78-41b6-98af-f077cff3de80`: Accepted, stapled.
- `dist/Beacon-1.0.0.zip` has `Beacon.app` at the archive root. `dist/appcast.xml` is build 2, short version 1.0.0, minimum system 14.0, enclosure length 2600106.
- Disk image sha256 `3ccc908b9e667c0e2890cfb1522da49515b988b3648a6356b037e86936d2e493`. Zip sha256 `ef01cb06bd9ef9393563c4ec7a59d10eb457b62d44cc477a06b9c1926e62eb2a`.
- `project.yml` is build 1. `git status` was clean before the debug log lines in this phase. The live feed is still the empty 185-byte channel. `curl` returned HTTP 200 and `content-type: application/xml`.

The disk image was mounted and copied to `/Applications/Beacon.app`. The copy that was already there moved to `/tmp/Beacon-pre-phase10.app`. The installed app is 1.0.0 (2), Developer ID, stapled. `spctl -a -vvv` says Notarized Developer ID. It launched, and `tell application "Beacon" to quit` quit it.

Migration on that binary: the live config and state were moved aside, the legacy files stayed, and the app copied both into the Beacon paths. The user's files were then put back. `cmp` said the restore matched.

The app icon is the amber radar on a dark rounded square.

About Beacon, from this source: window 284 by 204. The text was "Beacon", "Version 1.0.0 (2)", "Website", and "GitHub". The bug URL was `https://github.com/Avivhdr/beacon/issues/new?template=bug_report.yml&beacon-version=1.0.0%20(2)&macos-version=27.0.1%20arm64`.

Check for Updates, user-initiated, against the live feed: Sparkle opened a 260 by 218 window. The text was "You’re up to date!" and "Beacon 1.0.0 is currently the newest version available." Assistive access is off for this session, so the installed app's menu was not clicked. The check used the same feed URL and the same menu action.

### Decision

The local cask still has the Phase 6 disk-image hash. A real `./release.sh` replaces that hash from the disk image it just built. The public tap is still not created.

## Phase 11: go public and ship 1.0.0

Checked on 2026-10-17.

Aviv approved the public step, then approved the 1.0.0 release. The Sparkle private-key backup goes in Bitwarden.

### What changed

`gh repo edit Avivhdr/beacon --visibility public --accept-visibility-change-consequences`.

Private vulnerability reporting is on.

The public tap is https://github.com/Avivhdr/homebrew-tap. The first tap commit is `6cf6626`, "Add the Beacon cask."

`./release.sh` from `/Users/avivhadar/repos/beacon` published 1.0.0. `MARKETING_VERSION` stayed `1.0.0`. The script moved `CURRENT_PROJECT_VERSION` from 1 to 2. Commit `8a67460` is `release: v1.0.0 (build 2)`. The tap commit `70c3238` is `beacon 1.0.0`.

The first notary submit lost the network (`NSURLErrorDomain` -1005) before it returned a submission id. Nothing was published. `project.yml` was restored to build 1, and the script was run again.

### Checks

- `gh repo view`: visibility PUBLIC. The repository is not private. The homepage is `https://beacon-for-github.vercel.app`.
- An anonymous `curl` of https://github.com/Avivhdr/beacon returned HTTP 200.
- While the repository was private, `PUT /repos/Avivhdr/beacon/private-vulnerability-reporting` returned 404. After it was public, the same call succeeded. `GET` returns `{"enabled":true}`.
- App submission `437a84fb-0158-4b8a-907b-a95cf30dd7a2`: stapled. `spctl` says Notarized Developer ID.
- Disk image submission `cf25af79-c2ae-4eab-ae2f-147a2170e00a`: stapled. `spctl` says Notarized Developer ID.
- The live feed shows `sparkle:shortVersionString` 1.0.0 and `sparkle:version` 2. The enclosure length is 2601802. `curl` of the enclosure returned HTTP 200 and 2601802 bytes. `releases/latest/download/Beacon.dmg` returned HTTP 200.
- The downloaded disk image sha256 is `26d2db1b5a5fd86eb29db567266a2f75aa981d4821640b1c351ae9aecbc42afc`. That matches the cask. The image was mounted. The app was copied out and given a quarantine attribute. `spctl -a -vvv --type execute` says Notarized Developer ID. The copy is 1.0.0 (2). `SUFeedURL` and `SUPublicEDKey` are the permanent values.
- `brew tap avivhdr/tap` and `brew install --cask avivhdr/tap/beacon` installed that build. Homebrew will not replace an app that is already in `/Applications`, so the dry-run app was moved to `/tmp/Beacon-pre-1.0.0-publish.app` first. The installed binary matches the downloaded release. It is 1.0.0 (2) and notarized.
- The site, in Chrome, shows version 1.0.0. The download link is visible and points at `releases/latest/download/Beacon.dmg`. The brew command on the page is `brew install --cask avivhdr/tap/beacon`.
- CI for `8a67460` succeeded: run 39039830561. The tag `v1.0.0` also ran CI, run 39039828713, and that succeeded.
- `PUT /repos/Avivhdr/beacon/social-preview` returned 404. The social preview image is not set. The homepage was already the Vercel site.

### Decision

The release is build 2, not build 1. `release.sh` always increments `CURRENT_PROJECT_VERSION`, and the dry run had put the committed number back to 1. `SUFeedURL` and `SUPublicEDKey` were not changed.

## Phase 12: final report

Checked on 2026-10-17.

The summary, the link table, the permanent values, the next-release steps, and the follow-ups are at the top of this file. The phase sections above are the record of how each step was checked.
