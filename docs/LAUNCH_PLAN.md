# Beacon launch plan

This is the runbook for taking Beacon from "runs on my Mac" to an open source, signed, auto-updating app with its own website. It's written for a Claude Code session on Aviv's personal Mac. Aviv will say something like "read docs/LAUNCH_PLAN.md and do it".

## How to run this plan

- Work through the phases in order. Each phase ends with a **Done when** list. Check every item for real (run the command, open the URL, look at the output) before moving on.
- Commit at the end of each phase with a plain message saying what changed. Push to `main` unless the phase says otherwise. Never add Claude or Anthropic as a co-author.
- Keep a running log in `docs/LAUNCH_REPORT.md`. After each phase, append what was done, how it was verified (commands and results), and any decision you made on the way. Phase 12 turns it into the final report.
- **Only stop to ask Aviv at the points marked "Ask Aviv".** Everything else is decided below, or is yours to decide sensibly. If something unexpected blocks you (a tool fails, an Apple service is down), try to fix it. Ask only when it needs something only Aviv can provide: a password, a login, a payment, a choice that can't be undone.
- When you ask, batch questions together, give a recommendation, and keep working on anything that doesn't depend on the answer.
- Focus Pill (`Avivhdr/focus-pill`, private, readable with `gh`) already does almost everything in this plan: XcodeGen, Developer ID signing, notarization, DMG, Sparkle, a release script, a `/release` skill and a Vercel site. **Read its `project.yml`, `package.sh`, `release.sh`, `ExportOptions.plist`, `Sources/FocusPill/Info.plist`, `.claude/skills/release/SKILL.md` and README sections "Code signing & notarization" and "Auto-updates" before Phase 2, and reuse what fits.** Example: `gh api repos/Avivhdr/focus-pill/contents/package.sh --jq .content | base64 -d`.

## Where things stand

- **The app.** Beacon is a macOS 14+ menu bar app. The icon shows unread PR activity and the review queue count, or the GitHub mark when nothing needs you. Clicking it opens a dark floating panel with three tabs: Unread, To review, and Mine (your own open PRs, in layers like Work and Private, grouped by collapsible repo). See `README.md` for behavior and config, and `DESIGN.md` for the look.
- **The code.** It's a SwiftPM package with a `Core` library (logic, tested with `swift test`, 17 tests) and an executable target `GitHubNotifications` (the app). `scripts/build-app.sh` wraps it in `build/Beacon.app` with an ad-hoc signature. There's no Xcode project, app icon, Sparkle, or release tooling yet.
- **Names still from before the rename** (all changed in Phase 1):
  - Bundle ID: `com.avivhadar.github-notifications`
  - Executable and Swift target: `GitHubNotifications`
  - Config: `~/.config/github-notifications/config.json`
  - State: `~/Library/Application Support/GitHubNotifications/state.json`
  - UserDefaults keys `hiddenPRs` and `collapsedRepos`, stored under the old bundle ID
- **The repo** is `github.com/Avivhdr/beacon`, **private** for now. It mentions Collibra repos and a colleague's GitHub login in tests and docs, and that gets cleaned up in Phase 3 before it goes public.
- **Name check.** `joryeugene/gitbeacon` is a similar GitHub-notifications menu bar app, and `lpbas/Beacon` is an unrelated Mac menu bar app. Aviv chose "Beacon" knowing that. Use "Beacon" as the app name and "Beacon for GitHub" where it needs telling apart (site title, App descriptions, the Homebrew cask description).

## Decisions already made (don't re-ask)

| Topic | Decision |
|---|---|
| License | MIT, "Copyright (c) 2026 Aviv Hadar". |
| Repo | `Avivhdr/beacon`, made public in Phase 11 after the cleanup. |
| Bundle ID | `com.avivhadar.Beacon` (Focus Pill uses `com.avivhadar.FocusPill`). |
| Build system | XcodeGen `project.yml`, like Focus Pill. Keep `Package.swift` for `Core` so `swift test` stays fast. The generated `.xcodeproj` is git-ignored. |
| Signing | Developer ID Application, team `8PYS6TK87H` (the same paid team as Focus Pill), Hardened Runtime, notarized, stapled. |
| Download | A signed, notarized, stapled `.dmg` with the drag-to-Applications layout, plus a `.zip` for Sparkle. |
| Auto-update | Sparkle 2, automatic background checks on by default, and a "Check for Updates…" item in the ⋯ menu. A separate EdDSA key from Focus Pill's (`generate_keys --account beacon`). |
| Where updates live | `appcast.xml` on the website (`web/appcast.xml`, deployed by Vercel). The binaries are GitHub Release assets, because the repo is public, unlike Focus Pill's. |
| Website | A static site in `web/` (plain HTML, CSS and a little JS, no framework or build step, like Focus Pill), deployed by Vercel from `main`, styled per `DESIGN.md`. |
| Homebrew | Tap `Avivhdr/homebrew-tap`, cask `beacon`. Install with `brew install --cask avivhdr/tap/beacon`. |
| CI | GitHub Actions runs tests and an unsigned build on pushes and PRs. Signing and releasing stay local, like Focus Pill. |
| Versions | First public release is `1.0.0`, build `1`. |

## Ask Aviv (the only planned stops)

- **A. Apple credentials (Phase 2).** Check what's already on this Mac:
  - `security find-identity -v -p codesigning | grep "Developer ID Application"` should list `Aviv Hadar (8PYS6TK87H)`.
  - `xcrun notarytool history --keychain-profile focuspill-notary` should succeed. Reuse that profile, since notarization credentials are per team, not per app.

  Ask only if one of them is missing. Aviv then creates the certificate in Xcode → Settings → Accounts → Manage Certificates, or supplies an app-specific password from appleid.apple.com for `notarytool store-credentials`.
- **B. Website domain (Phase 5).** `SUFeedURL` is compiled into every build and can never move, so the feed's domain is permanent. Recommend a `*.vercel.app` subdomain (for example `beacon-app.vercel.app`, whatever is free) unless Aviv wants to buy a domain. Ask which, and get the final URL before Phase 4 bakes it into the app. You can build the app parts of Phase 4 first with a placeholder, as long as no signed build ships with it.
- **C. Vercel login (Phase 5)**, if `vercel whoami` fails. Ask Aviv to run `! vercel login` in the session.
- **D. Go public (Phase 11).** Show the cleanup summary from Phase 3 and ask before flipping the repo to public and creating the public tap repo.
- **E. Ship 1.0.0 (Phase 11).** Ask before the first real release, since it publishes a binary and a feed every future install trusts.

## Phase 0: bootstrap this Mac

1. Make sure these are installed. Install anything missing with Homebrew, without asking.
   - Xcode, and `xcode-select -p` points at it
   - `gh`, logged in as `Avivhdr` (`gh auth status`)
   - `xcodegen`
   - `create-dmg`
   - `node` and the Vercel CLI (`npm i -g vercel`)
2. Clone `Avivhdr/beacon` if this isn't already a clone, and work on `main`.
3. Run `swift test`.
4. Run `./scripts/build-app.sh`, launch `build/Beacon.app`, and confirm it runs. Aviv's real config on this Mac may differ from the work Mac, and that's fine.

**Done when** the tests pass and the app launches from a fresh clone.

## Phase 1: Xcode project, final identity, app icon

1. **XcodeGen.** Add `project.yml`, modeled on Focus Pill's:
   - An app target `Beacon` built from the app sources. Rename `Sources/GitHubNotifications` to `Sources/Beacon` (use `git mv`).
   - A dependency on the local package's `Core` library. Add a `.library(name: "Core", targets: ["Core"])` product to `Package.swift`.
   - A test target or scheme that runs `CoreTests`.
   - Settings: `MARKETING_VERSION: "1.0.0"`, `CURRENT_PROJECT_VERSION: "1"`, `LSUIElement: YES`, `LSMinimumSystemVersion` 14.0, `CFBundleDisplayName: Beacon`, category `public.app-category.developer-tools`.
   - Debug signs ad-hoc. Release signs with `Developer ID Application`, team `8PYS6TK87H`, Hardened Runtime on. Beacon doesn't need any entitlements: it's not sandboxed, makes outgoing HTTPS calls, and runs `gh`.
   - Git-ignore `Beacon.xcodeproj/`, `dist/`, `.sparkle-tools/` and `.vercel/`.
2. **A Makefile** with `run`, `build`, `test` and `package`, as in Focus Pill. Replace `scripts/build-app.sh` with `make` targets plus an `install.sh` that builds Release and copies the app to `/Applications/Beacon.app`. Keep `scripts/replay.sh` working: update its paths and process name.
3. **Final identity.** Rename the bundle ID to `com.avivhadar.Beacon`, the executable to `Beacon`, the config to `~/.config/beacon/config.json`, and the state to `~/Library/Application Support/Beacon/state.json`. Add a one-time migration that runs at launch before anything is read:
   - If the new config is missing and the old one exists, copy it over. Do the same for state.
   - If the new UserDefaults have no `hiddenPRs`/`collapsedRepos` but `UserDefaults(suiteName: "com.avivhadar.github-notifications")` does, copy them.
   - Leave the old files in place, so a rollback isn't destructive.

   Test the migration logic in `Core` where possible. Update `README.md`, `CLAUDE.md` and every script. Notification permission will be asked again under the new ID, which is expected.
4. **App icon.** Generate it with a script (`Tools/generate-icon.swift`, like Focus Pill's) so it's reproducible: an ink-colored macOS squircle with a radar scope (fine rings, bearing ticks) and an amber beam with a fading trail, per `DESIGN.md`. Keep it legible at 16pt. Put it in an asset catalog and wire up `ASSETCATALOG_COMPILER_APPICON_NAME`. The menu bar icon doesn't change.
5. **A snapshot tool**, for the README and the website. Add a `--snapshot <dir>` launch argument, compiled in Debug only (`#if DEBUG`). It renders the panel with built-in sample data (fictional names, no real people or orgs) for each tab and each empty state, at 2x, into PNGs. The earlier one-off version hosted `PanelView` in an `NSHostingView` inside an offscreen `NSWindow` placed at (-3000, -3000) with `orderFrontRegardless()`, waited about 1.5s so the entrance animations finished, then used `cacheDisplay(in:to:)`. Expose `AppModel.loadPreview(...)` and the panel's initial tab only under `#if DEBUG`.

**Done when:**
- `make test` passes.
- `make run` launches Beacon from Xcode's build with the new icon.
- An old config and state on this Mac migrated, and the panel shows the same data as before.
- `make snapshots` (or the equivalent command) writes the PNGs.

## Phase 2: signing, notarization, DMG

Ask Aviv (A) here only if the credential check fails.

1. Add `ExportOptions.plist` (method `developer-id`, team `8PYS6TK87H`) and a `package.sh` modeled on Focus Pill's macOS path:
   1. Archive a universal (arm64 and x86_64) Release build.
   2. Export it with the `developer-id` method. That re-signs Sparkle's nested code later on.
   3. Notarize the `.app` by submitting and polling `notarytool info`, not `--wait`. Then staple it.
   4. Run `spctl -a -vvv --type execute`.
   5. Build the `.dmg` with `create-dmg` (app plus an Applications link, dark background art in Beacon's style if it's cheap to do).
   6. Sign the `.dmg`, notarize it, and staple it.
   7. Write everything to `dist/`.
2. Use the existing `focuspill-notary` keychain profile, or set `NOTARY_PROFILE` at the top of the script.

**Done when** `./package.sh` produces `dist/Beacon-1.0.0.dmg`, and all three of these pass:
- `spctl -a -vvv -t install dist/Beacon-1.0.0.dmg`
- `stapler validate` on both the DMG and the app
- After adding a quarantine flag to a copy (`xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" Beacon.app`), it still opens with no Gatekeeper prompt.

## Phase 3: open source hygiene (repo still private)

1. Add `LICENSE` (MIT). Add `CONTRIBUTING.md` (how to build, test and snapshot, the design rules in short, and that PRs need green CI). Add `SECURITY.md` (report privately through GitHub's private vulnerability reporting).
2. Remove real people and company details:
   - Tests use the colleague login `koenvangeert` and `collibra/...` repos. Replace them with fictional ones (`octo-org/frontend`, `mona`, `hubot`, `octocat`) without changing what the tests check.
   - Clean the README's Collibra examples and the comment in `FiltersView.swift` the same way.
   - Run `grep -rni "collibra\|koenvangeert"` over the tree. The only acceptable hits are in `docs/LAUNCH_PLAN.md` and `docs/LAUNCH_REPORT.md`, which describe this cleanup.
3. Check git history too: `git log -p | grep -i -E "collibra|koenvangeert|gh[pousr]_|github_pat_"`. The history is short. If anything sensitive shows up, squash everything into one "Initial public release" commit before going public, and note that in the report. Company repo names in old test fixtures count as worth squashing. Keep the clean history if nothing turns up.
4. Rewrite `README.md` for strangers:
   - What Beacon is, with a screenshot from the snapshot tool.
   - Install: DMG and Homebrew.
   - Requirements: macOS 14 and `gh auth login`. Mention that SSO orgs need the token authorized for them.
   - Privacy: the token comes from `gh`, stays on the Mac, and only goes to `api.github.com`. No analytics.
   - The config reference, already in the README, kept accurate.
   - Building from source, and a link to the website.
5. Add `.github/ISSUE_TEMPLATE/bug_report.yml` (asks for the Beacon version, macOS version, and the output of `Beacon --dump`) and `feature_request.yml`.
6. Set the repo description, homepage (the site URL once known) and topics (`macos`, `menubar`, `github`, `notifications`, `pull-requests`, `swiftui`) with `gh repo edit`.

**Done when:**
- `grep` and the history check come back clean (or the squash is done).
- The README reads well to someone who has never heard of Beacon.
- The license and templates are in place.

## Phase 4: Sparkle auto-updates

1. Add Sparkle 2 through XcodeGen `packages:`, pinned to the same version as Focus Pill, or the latest 2.x if newer.
2. Create the key with the Sparkle tools, downloaded to `.sparkle-tools/` the way Focus Pill's `release.sh` does: `generate_keys --account beacon`. The private key stays in the login Keychain. Put the public key in the partial `Info.plist` as `SUPublicEDKey`, next to `SUFeedURL` (the URL from Ask B), `SUEnableAutomaticChecks: YES` and `SUScheduledCheckInterval: 86400`.
3. In the app:
   - Create an `SPUStandardUpdaterController` at launch.
   - Add "Check for Updates…" to the ⋯ menu in `PanelView`'s status strip.
   - Beacon has no Dock icon, so implement `SPUStandardUserDriverDelegate` with gentle scheduled update reminders. When an update is found in the background, show a small amber readout in the status strip ("UPDATE READY"). Clicking it brings up Sparkle's window, after `NSApp.activate()`.
4. Write down in `README.md` and `CLAUDE.md` that `SUFeedURL` and `SUPublicEDKey` are effectively permanent. Rotating the key or moving the feed strands every installed copy. Back up the private key: export it with `generate_keys --account beacon -x <file>`, ask Aviv where to keep it (a password manager), and delete the export afterwards. This is the only extra question in this phase. Fold it into Ask E if possible.

**Done when:**
- A Release build shows "Check for Updates…".
- Pointing a Debug build at a local test appcast (a temporary `SUFeedURL` override through `defaults write`) with a higher version offers the update. Revert the override afterwards.

## Phase 5: the website (Vercel)

Ask B and Ask C come up here.

1. Build `web/` as a static site, styled exactly per `DESIGN.md`. A single `index.html` plus `styles.css` and a small `main.js`, and no framework. Sections:
   - **Hero.** "Beacon" with a short line like "Know what on GitHub needs you", the panel screenshot (or a faithful HTML rebuild) with the counters rolling up on load, a radar sweep on a canvas, a Download button (`https://github.com/Avivhdr/beacon/releases/latest/download/Beacon.dmg`) and the `brew install --cask avivhdr/tap/beacon` command with a copy button.
   - **The three tabs**, each with a real screenshot and two lines of copy: Unread (comments, replies, mentions), To review (categories, hiding repos or single PRs, CI and stale readouts), Mine (layers, repos that fold, review state).
   - **Setup in three steps:** install, `gh auth login`, done. Then a short note on the config file.
   - **Privacy**, in a few plain sentences.
   - **Open source:** a link to the repo, the license, and a "Report a bug" link to the issue template.
   - **Footer:** version (read from the appcast at load time is fine), GitHub, and a "Made by Aviv Hadar" credit.
2. Add the details:
   - Favicon from the app icon, an Open Graph image (1200x630, from a snapshot), and `<title>Beacon for GitHub</title>`.
   - Honor `prefers-reduced-motion`, give images real alt text, meet WCAG AA contrast, and work on mobile. The download is Mac-only, so on other devices show "Beacon is for macOS 14+" instead of a button that does nothing.
3. Put `web/appcast.xml` in place with an empty channel, so the feed URL exists from day one.
4. Deploy:
   - `vercel link` with project name `beacon` (or whatever is free) and root directory `web`.
   - Connect the GitHub repo so every push to `main` deploys.
   - Get the production URL, and confirm it with Aviv (Ask B) if the subdomain differs from what was agreed.
5. Use the `frontend-design` and `impeccable:*` skills if they're installed, and look at the rendered page with `playwright-cli` screenshots at desktop and mobile widths before calling it done.

**Done when:**
- The production URL loads, looks like the app, and passes a Lighthouse accessibility run at 95 or above.
- `curl -sI <site>/appcast.xml` returns 200 with an XML content type.

## Phase 6: release pipeline

1. Write `release.sh`, adapted from Focus Pill's:
   - **Preflight:** on `main`, and a clean tree apart from `project.yml`.
   - **Version:** read `MARKETING_VERSION` and bump `CURRENT_PROJECT_VERSION` automatically.
   - **Build:** run `./package.sh`.
   - **Update archive:** zip the app with the bundle at the archive root (`ditto -c -k --keepParent`), named `Beacon-<version>.zip`.
   - **Appcast:** run `generate_appcast --account beacon --download-url-prefix https://github.com/Avivhdr/beacon/releases/download/v<version>/`. Add release notes from a `CHANGELOG.md` section for the version.
   - **GitHub Release:** create `v<version>` with the zip, `Beacon-<version>.dmg`, and the same DMG uploaded a second time as `Beacon.dmg`. The site's "latest" link points at that stable name.
   - **Publish the feed:** commit the bumped `project.yml` and `web/appcast.xml`, and push. The push is the Vercel deploy.
   - **Verify:**
     - Poll `<site>/appcast.xml` until it shows the new build.
     - `curl -sL` the enclosure URL, and check it returns 200 with a byte count equal to the feed's `length`.
     - Check that `releases/latest/download/Beacon.dmg` resolves.
   - **Bump the Homebrew cask** (Phase 7).
   - **`--dry-run`:** builds and signs into `dist/`, publishes nothing, and leaves no trace (restore the build number with a trap, as Focus Pill does).
2. Add `CHANGELOG.md` with a `1.0.0` entry describing the app.
3. Add `.claude/skills/release/SKILL.md`, adapted from Focus Pill's, with `disable-model-invocation: true`. Only a human starts a release.

**Done when** `./release.sh --dry-run` produces a signed zip, DMG and appcast in `dist/`, and leaves `git status` clean.

## Phase 7: Homebrew tap

1. Prepare `Avivhdr/homebrew-tap` with `Casks/beacon.rb`:
   - `version` and `sha256`
   - `url "https://github.com/Avivhdr/beacon/releases/download/v#{version}/Beacon-#{version}.dmg"`
   - `name "Beacon"`, `desc "Menu bar app for GitHub notifications, reviews and your PRs"`, `homepage` set to the site
   - `depends_on macos: ">= :sonoma"`, `auto_updates true`, `app "Beacon.app"`
   - `zap` covering `~/.config/beacon`, `~/Library/Application Support/Beacon` and the preferences plist
2. Creating the public tap repo waits for Ask D. Prepare the file under `dist/homebrew-tap/` until then.
3. Have `release.sh` update `version` and `sha256` and push the tap after each release.

**Done when** (after Phase 11) `brew install --cask avivhdr/tap/beacon` installs and launches 1.0.0, and `brew audit --cask --new avivhdr/tap/beacon` has no errors.

## Phase 8: polish for people who aren't Aviv

1. **First run without `gh`.** Today the status strip shows a red error. Replace that with a proper empty state in the panel, in the radar style, with the exact steps:
   - `brew install gh`
   - `gh auth login`
   - a "Try again" pill

   Do the same when the token is rejected.
2. **⋯ menu additions:**
   - **Open at Login:** a toggle using `SMAppService.mainApp`.
   - **About Beacon:** version, build, website and GitHub links. Use the standard About panel with custom credits, or a small window in the Beacon style.
   - **Report a Bug…:** opens a new GitHub issue with the bug template, the version, the macOS version and the architecture filled in, through URL query parameters.
3. **Config defaults for new users:**
   - The Mine tab gets a single "Open" layer, which is already the default.
   - Keep the README's example for Work/Private layers.
   - Make sure a fresh config shows nothing broken for someone with no teammates configured. The Teammates category note is acceptable but should read kindly.
4. **App Nap and sleep:** confirm polling resumes after wake. There's an observer already; test it once.

**Done when** each item has been tried on this Mac. For the first-run test, temporarily hide `gh` with `PATH` tricks or `GITHUB_TOKEN=bad`, and record the results in the report.

## Phase 9: CI

1. Add `.github/workflows/ci.yml` on `macos-15`, triggered by pushes and pull requests:
   - `swift test`
   - `xcodegen generate`
   - an unsigned `xcodebuild build` (`CODE_SIGNING_ALLOWED=NO`)
2. Add a CI badge to the README.

**Done when** the workflow is green on `main`.

## Phase 10: dry run of the whole release

Run `./release.sh --dry-run`. Then install the dry-run DMG on this Mac as a user would (mount it, drag the app to Applications, launch it) and check:
- the migration from the old config still works,
- the icon and the About panel look right,
- "Check for Updates…" reports that this is the latest version.

**Done when** all of that works and `git status` is clean.

## Phase 11: go public and ship 1.0.0

1. **Ask Aviv (D).** Show the Phase 3 cleanup summary. Once approved:
   - Make the repo public: `gh repo edit Avivhdr/beacon --visibility public --accept-visibility-change-consequences`.
   - Enable private vulnerability reporting.
   - Create the public `Avivhdr/homebrew-tap` and push the cask.
2. **Ask Aviv (E).** Once approved, run `./release.sh`, then verify from outside the machine:
   - **The feed.** `curl -sS <site>/appcast.xml` shows `1.0.0`, build 1, and an enclosure that returns 200 with a matching length.
   - **The DMG.** The latest DMG link downloads and mounts. The app passes `spctl -a -vvv` after the copy, with quarantine.
   - **Homebrew.** `brew install --cask avivhdr/tap/beacon` installs that build.
   - **The site.** It shows the download and the right version.
3. Set the repo's homepage URL to the site and upload a social preview image (the OG image) in repo settings. If the API can't do the upload, add it to the report's follow-ups.

## Phase 12: final report

Turn `docs/LAUNCH_REPORT.md` into the final report and commit it. It should contain:
- **A summary:** what Beacon is now, where it lives, and how people install it.
- **A table of links:** site, repo, latest release, appcast, DMG, Homebrew command, CI.
- **Each phase:** what was done, how it was verified (actual commands and results), and anything skipped or changed from this plan, with the reason.
- **Decisions made along the way.**
- **Secrets and permanent things:** where the EdDSA private key backup lives (not the key itself), the notary profile name, and the `SUFeedURL` and `SUPublicEDKey` values with a warning never to change them.
- **How to cut the next release:** bump `MARKETING_VERSION`, run `/release`.
- **Follow-ups for Aviv,** if any.

Then tell Aviv it's done, with the summary and the links, in a few lines.
