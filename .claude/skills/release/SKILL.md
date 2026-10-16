---
name: release
description: Cut and publish a Beacon release (bump, build, sign, deploy, verify)
argument-hint: "[patch|minor|major|version] — omit to bump the patch, pass a bump kind, or an explicit version like 1.1.0"
# Only a human starts a release. This skill pushes to main, deploys the feed,
# publishes a GitHub release, and ships a binary to installed copies.
disable-model-invocation: true
---

Cut a new release of Beacon (macOS menu bar app, Sparkle auto-update).

The feed URL and the Sparkle public key are permanent. Do not change `SUFeedURL` or `SUPublicEDKey`.

Target version: read `$ARGUMENTS` against the current `MARKETING_VERSION` (`X.Y.Z`):

- Omitted, or `patch` — bump `Z` by 1.
- `minor` — bump `Y` by 1, reset `Z` to 0.
- `major` — bump `X` by 1, reset `Y` and `Z` to 0.
- Anything else — treat it as an explicit version, for example `1.1.0`. Stop and ask if it is not a valid `X.Y.Z`, or if it is not greater than the current version.
- The first public release is already `1.0.0` in `project.yml`. Do not bump it for that release.

## Steps

1. Use a checkout of `main` and `git pull`. This OpenForge worktree cannot check out `main`. Stop and ask if the tree has changes to anything other than `project.yml`, or if the checkout is not `main`. Do not stash or discard work.

2. In `project.yml`, bump only `MARKETING_VERSION`, except for the first `1.0.0` release.

   Do not touch `CURRENT_PROJECT_VERSION`. `release.sh` owns that number and increments it. Sparkle compares the build number. Do not commit the marketing bump yourself. The script commits it with the build number.

3. Run `./release.sh` from the repo root, with no flags, and show the output.

   The script builds the universal Release app, notarizes the app and the disk image, writes `Beacon-<version>.zip`, and signs `web/appcast.xml`. It creates GitHub release `v<version>` with the zip, `Beacon-<version>.dmg`, and the same disk image as `Beacon.dmg`. It commits `project.yml` and `web/appcast.xml` and pushes `main`. That push deploys the feed. It then checks the live feed, the update zip length, and `releases/latest/download/Beacon.dmg`. It updates the Homebrew cask and pushes the tap when that repo exists.

4. Verify from outside this machine:

   - `curl -sS https://beacon-for-github.vercel.app/appcast.xml` shows the new `sparkle:shortVersionString` and a `sparkle:version` one higher than the previous release.
   - The enclosure URL returns HTTP 200 and its byte count equals the `length` attribute in the feed.
   - `https://github.com/Avivhdr/beacon/releases/latest/download/Beacon.dmg` returns 200.

5. Report the version, the build number, the feed status, both download checks, and the GitHub release URL.

## Stop and ask first if

- The release tag already exists.
- The build or the tests fail.
- The feed does not go live inside the script's wait window.
- Anything would change `SUFeedURL` or `SUPublicEDKey`.

Do not add a co-author trailer to the release commit.
