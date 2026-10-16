# Beacon launch report

Running log for [LAUNCH_PLAN.md](LAUNCH_PLAN.md). Each phase lists what changed, how it was checked, and any decision made on the way.

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
