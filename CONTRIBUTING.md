# Contributing

Beacon is a native macOS menu bar app. App code is SwiftUI in an AppKit shell. Shared logic lives in `Sources/Core` and has no UI.

## Build, test, snapshot

You need macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make test        # swift test, the Core rules
make run         # Debug build, then launch
make snapshots   # panel PNGs in snapshots/ (Debug only, not committed)
```

`project.yml` is the source of truth. `make build` runs `xcodegen generate`. Do not commit `Beacon.xcodeproj`.

`Beacon --dump` prints one refresh and saves nothing. `./scripts/replay.sh 24` forgets the last 24 hours of state and relaunches, so banners show again.

## Design

Read [DESIGN.md](DESIGN.md) before you change the panel or the website.

- Amber is the only signal color. Red and green mean status only.
- Counts are large and light. Labels are small uppercase mono readouts.
- Split sections with hairlines. Do not add cards, shadows, or text gradients.
- Motion means something changed, and it respects Reduce Motion.

## Pull requests

A pull request needs the GitHub Actions checks on this repository to pass before it is merged. Logic changes in `Sources/Core` need tests in `Tests/CoreTests`. Keep [README.md](README.md) in sync when behavior or config keys change.

Report security problems in private. See [SECURITY.md](SECURITY.md).
