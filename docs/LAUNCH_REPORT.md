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

Ask B: the feed stays on a free `*.vercel.app` address. The exact name is checked in Phase 5, before `SUFeedURL` is written into the app. No signed build ships with a placeholder feed URL.
