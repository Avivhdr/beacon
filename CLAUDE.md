# Beacon

A native macOS menu bar app (SwiftUI in an AppKit shell) that shows what on GitHub needs you: unread PR activity, PRs waiting for your review, and your own open PRs. It reads the user's token from `gh auth token` and talks only to `api.github.com`.

## Layout

- `Sources/Core`: models, GitHub client (REST and GraphQL), the feed classifier, config and state. No UI. Logic changes here get tests in `Tests/CoreTests` (`swift test`).
- `Sources/Beacon`: the app. `AppDelegate` (menu bar item, floating panel, status icon), `Updater` (Sparkle), `AppModel` (state the views observe), `PanelView` (Unread, To review, and Mine; Merged sits under the Mine count and has no count), `FiltersView` (review category editor), `Theme` (palette, readout type, lamps, motion). The Xcode project comes from `project.yml` (`make build`). `Package.swift` stays for `Core` so `swift test` stays fast.
- `scripts/`: build and replay helpers. `README.md` is the user-facing reference for behavior and config keys.

## Design

Read [DESIGN.md](DESIGN.md) before changing any UI, here or on the website. One amber signal color, red and green for status only, uppercase mono readouts, hairlines instead of cards, motion that respects Reduce Motion.

## Launch work

[docs/LAUNCH_PLAN.md](docs/LAUNCH_PLAN.md) is the runbook for taking Beacon public: signing, notarization, Sparkle updates, the website, the Homebrew tap and releases. Progress goes into `docs/LAUNCH_REPORT.md`.

## Updates

`SUFeedURL` is `https://beacon-for-github.vercel.app/appcast.xml`. `SUPublicEDKey` is in `Sources/Beacon/Info.plist`. Both are permanent. A signed build must keep this feed URL. The private half of the update key stays in the login Keychain, Sparkle account `beacon`. Do not commit it, and do not print it.

## Conventions

- Match the surrounding code. Comments explain why, not what.
- Keep the README in sync when behavior or config keys change.
- Never add Claude or Anthropic as a co-author or mention them in commit messages (same rule as Focus Pill).
- The floating panel is a borderless `NSPanel`. Keep `hidesOnDeactivate = false`, and don't position it from the status item's window frame. On recent macOS that frame sits above the screen.
